#!/bin/bash
#
# make_bundle.sh — compila o Git Arbor em modo Release e monta o pacote "Git Arbor.app".
#
# Uso:
#   Scripts/make_bundle.sh <pasta de saída> <versão> <build>
#
# O pacote é gerado sem assinatura. Quem chama decide como assinar:
#   build_app.sh            identidade local estável, para instalar neste Mac;
#   package_release.sh      assinatura ad hoc, para distribuição.
#
# Variáveis de ambiente:
#   BUNDLE_ID         Identificador do app (padrão: io.github.gitarbor.GitArbor).
#   SWIFT_BUILD_ROOT  Pasta de compilação do SwiftPM (padrão: ~/Library/Caches/GitArbor/SwiftPM).
#
set -euo pipefail

die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }

if [[ $# -ne 3 ]]; then
    printf 'Uso: %s <pasta de saída> <versão> <build>\n' "$0" >&2
    exit 2
fi
readonly OUT_DIR="$1"
readonly VERSION="$2"
readonly BUILD="$3"
[[ -d "$OUT_DIR" ]] || die "a pasta de saída não existe: $OUT_DIR"

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_NAME="Git Arbor.app"
readonly EXECUTABLE="GitArbor"
readonly BUNDLE_ID="${BUNDLE_ID:-io.github.gitarbor.GitArbor}"
readonly SWIFT_BUILD_ROOT="${SWIFT_BUILD_ROOT:-$HOME/Library/Caches/GitArbor/SwiftPM}"

cd "$ROOT"
mkdir -p "$SWIFT_BUILD_ROOT"

printf '==> Compilando (Release)\n'
swift build -c release --scratch-path "$SWIFT_BUILD_ROOT"
BIN_DIR="$(swift build -c release --scratch-path "$SWIFT_BUILD_ROOT" --show-bin-path)"

printf '==> Montando %s %s (build %s)\n' "$APP_NAME" "$VERSION" "$BUILD"
readonly APP="$OUT_DIR/$APP_NAME"
readonly CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
install -m 755 "$BIN_DIR/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"
install -m 644 "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
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
plutil -lint "$CONTENTS/Info.plist" >/dev/null || die "Info.plist inválido."
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Atributos estendidos (ex.: quarentena, Finder) invalidam a assinatura feita em seguida.
xattr -cr "$APP"
