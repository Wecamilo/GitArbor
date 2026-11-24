#!/bin/bash
# Compila em modo Release e monta o pacote "Git Arbor.app" (ainda sem assinatura).
# Uso: Scripts/make_bundle.sh <pasta de saída> <versão> <build>
# Usado pelo build_app.sh (instalação local) e pelo package_release.sh (versão para baixar).
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Uso: $0 <pasta de saída> <versão> <build>" >&2
    exit 2
fi
OUT_DIR="$1"
VERSION="$2"
BUILD="$3"

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$ROOT"

APP_NAME="Git Arbor.app"
EXECUTABLE="GitArbor"
BUNDLE_ID="${BUNDLE_ID:-io.github.gitarbor.GitArbor}"

SWIFT_BUILD_ROOT="${SWIFT_BUILD_ROOT:-$HOME/Library/Caches/GitArbor/SwiftPM}"
mkdir -p "$SWIFT_BUILD_ROOT"

echo "==> Compilando em modo Release..."
swift build -c release --scratch-path "$SWIFT_BUILD_ROOT"
BIN_DIR="$(swift build -c release --scratch-path "$SWIFT_BUILD_ROOT" --show-bin-path)"

APP="$OUT_DIR/$APP_NAME"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"
chmod 755 "$CONTENTS/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/"

cat << PLIST > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Git Arbor</string>
    <key>CFBundleDisplayName</key><string>Git Arbor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
    <key>CFBundleLocalizations</key><array><string>pt-BR</string></array>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Sua central do GitHub, explicada. Licença MIT.</string>
    <key>NSFaceIDUsageDescription</key><string>O Git Arbor usa a sua digital para abrir a sua central do GitHub.</string>
</dict>
</plist>
PLIST
plutil -lint "$CONTENTS/Info.plist" >/dev/null
echo "APPL????" > "$CONTENTS/PkgInfo"
xattr -cr "$APP"
echo "==> Pacote montado: $APP ($VERSION, build $BUILD)"
