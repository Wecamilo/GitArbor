#!/bin/bash
# Testa, empacota, assina e instala o Git Arbor em ~/Applications.
# Uso: ./build_app.sh [--no-launch]
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

LAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=0 ;;
        *) echo "Uso: $0 [--no-launch]" >&2; exit 2 ;;
    esac
done

# MAJOR.MINOR vem do arquivo VERSION (mudado à mão); o último número conta os commits
# desde essa mudança. O build conta todos os commits e nunca volta atrás.
RELEASE="$(tr -d '[:space:]' < VERSION)"
PATCH="$(git rev-list --count "$(git log -1 --format=%H -- VERSION)..HEAD")"
VERSION="$RELEASE.$PATCH"
BUILD="$(git rev-list --count HEAD)"
APP_NAME="Git Arbor.app"
EXECUTABLE="GitArbor"
BUNDLE_ID="io.github.gitarbor.GitArbor"
export BUNDLE_ID SWIFT_BUILD_ROOT="$HOME/Library/Caches/GitArbor/SwiftPM"

SUPPORT="$HOME/Library/Application Support/Git Arbor"
SIGNING_DIR="$SUPPORT/Signing"
SIGNING_KEYCHAIN="$SIGNING_DIR/gitarbor-signing.keychain-db"
SIGNING_PASSWORD_FILE="$SIGNING_DIR/keychain-password"
SIGNING_IDENTITY="Git Arbor Local Signing"

echo "==> Testando..."
mkdir -p "$SWIFT_BUILD_ROOT"
swift test --scratch-path "$SWIFT_BUILD_ROOT" 2>&1 | grep -E "Test run|✘|error:" || true
if ! swift test --scratch-path "$SWIFT_BUILD_ROOT" >/dev/null 2>&1; then
    echo "ERRO: há testes falhando. Instalação cancelada." >&2
    exit 1
fi

echo "==> Preparando a identidade de assinatura (estável entre versões)..."
# Assinatura estável: o Chaves continua liberando a chave do GitHub para o app depois de cada atualização.
mkdir -p -m 700 "$SIGNING_DIR"
if [ ! -e "$SIGNING_KEYCHAIN" ]; then
    openssl rand -hex 32 > "$SIGNING_PASSWORD_FILE"
    chmod 600 "$SIGNING_PASSWORD_FILE"
    TMP_SIGN="$(mktemp -d)"
    P12_PASS="$(openssl rand -hex 16)"
    openssl req -new -newkey rsa:2048 -nodes -x509 -sha256 -days 3650 \
        -subj "/CN=$SIGNING_IDENTITY/O=Git Arbor Local" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" \
        -keyout "$TMP_SIGN/key.pem" -out "$TMP_SIGN/cert.pem" >/dev/null 2>&1
    LEGACY=""
    if [[ "$(openssl version)" == OpenSSL\ 3* ]]; then LEGACY="-legacy"; fi
    openssl pkcs12 ${LEGACY:+$LEGACY} -export -out "$TMP_SIGN/id.p12" -inkey "$TMP_SIGN/key.pem" \
        -in "$TMP_SIGN/cert.pem" -name "$SIGNING_IDENTITY" -passout "pass:$P12_PASS" >/dev/null 2>&1
    KC_PASS="$(<"$SIGNING_PASSWORD_FILE")"
    security create-keychain -p "$KC_PASS" "$SIGNING_KEYCHAIN"
    security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
    security unlock-keychain -p "$KC_PASS" "$SIGNING_KEYCHAIN"
    security import "$TMP_SIGN/id.p12" -k "$SIGNING_KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$SIGNING_KEYCHAIN" >/dev/null
    rm -rf "$TMP_SIGN"
fi
security unlock-keychain -p "$(<"$SIGNING_PASSWORD_FILE")" "$SIGNING_KEYCHAIN"
CERT_SHA1="$(security find-certificate -c "$SIGNING_IDENTITY" -Z "$SIGNING_KEYCHAIN" | awk '/^SHA-1 hash:/{print $3; exit}')"
if ! [[ "$CERT_SHA1" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "ERRO: certificado de assinatura não encontrado." >&2
    exit 1
fi
REQUIREMENT="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$CERT_SHA1\""

TARGET_DIR="$HOME/Applications"
APP_DIR="$TARGET_DIR/$APP_NAME"
mkdir -p "$TARGET_DIR"
STAGING_ROOT=$(mktemp -d "$TARGET_DIR/.GitArbor-install.XXXXXX")
STAGED_APP="$STAGING_ROOT/$APP_NAME"
trap 'rm -rf "$STAGING_ROOT"' EXIT
"$DIR/Scripts/make_bundle.sh" "$STAGING_ROOT" "$VERSION" "$BUILD"

echo "==> Assinando..."
codesign --force --keychain "$SIGNING_KEYCHAIN" -s "$CERT_SHA1" --timestamp=none \
    -i "$BUNDLE_ID" -r="designated => $REQUIREMENT" "$STAGED_APP"
codesign --verify --deep --strict -R="$REQUIREMENT" "$STAGED_APP"

echo "==> Substituindo a instalação (a anterior fica guardada)..."
BACKUPS="$SUPPORT/Previous Builds.noindex"
mkdir -p "$BACKUPS"
for OLD_PID in $(pgrep -x "$EXECUTABLE" || true); do
    if [ "$(ps -p "$OLD_PID" -o comm=)" = "$APP_DIR/Contents/MacOS/$EXECUTABLE" ]; then
        # Pede para fechar; o Git Arbor não guarda nada pendente, então, se o pedido for
        # recusado ou demorar, encerra o processo com o sinal de término.
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do kill -0 "$OLD_PID" 2>/dev/null || break; sleep 0.1; done
        kill -0 "$OLD_PID" 2>/dev/null && kill -TERM "$OLD_PID" 2>/dev/null
        for _ in $(seq 1 50); do kill -0 "$OLD_PID" 2>/dev/null || break; sleep 0.1; done
        kill -0 "$OLD_PID" 2>/dev/null && { echo "A versão anterior não encerrou. Instalação cancelada." >&2; exit 1; }
    fi
done
BACKUP="$BACKUPS/$(date +%Y%m%d-%H%M%S)"
if [ -d "$APP_DIR" ]; then mkdir -p "$BACKUP"; mv "$APP_DIR" "$BACKUP/$APP_NAME.backup"; fi
if ! mv "$STAGED_APP" "$APP_DIR"; then
    [ -d "$BACKUP/$APP_NAME.backup" ] && mv "$BACKUP/$APP_NAME.backup" "$APP_DIR"
    exit 1
fi
codesign --verify --deep --strict -R="$REQUIREMENT" "$APP_DIR"
touch "$APP_DIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" >/dev/null 2>&1 || true
# Guarda só as três builds anteriores mais recentes.
ls -1 "$BACKUPS" | sort -r | tail -n +4 | while IFS= read -r OLD; do rm -rf -- "$BACKUPS/$OLD"; done || true

INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
if [ "$LAUNCH" = "1" ]; then
    open "$APP_DIR"
    for _ in $(seq 1 50); do pgrep -f "$APP_DIR/Contents/MacOS/$EXECUTABLE" >/dev/null && break; sleep 0.1; done
    if pgrep -f "$APP_DIR/Contents/MacOS/$EXECUTABLE" >/dev/null; then
        echo "==> Git Arbor $INSTALLED aberto."
    else
        echo "AVISO: o app não abriu." >&2
        exit 1
    fi
fi
echo "==> Sucesso! Git Arbor $INSTALLED (build $BUILD) instalado em: $APP_DIR"
