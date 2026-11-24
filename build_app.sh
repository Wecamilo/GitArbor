#!/bin/bash
#
# build_app.sh — compila, testa, assina e instala o Git Arbor em ~/Applications.
#
# Uso:
#   ./build_app.sh [opções]
#
# Opções:
#   --no-launch   Instala sem abrir o app ao final.
#   -h, --help    Mostra esta ajuda.
#
# Variáveis de ambiente:
#   INSTALL_DIR       Pasta de destino (padrão: ~/Applications).
#   SWIFT_BUILD_ROOT  Pasta de compilação do SwiftPM (padrão: ~/Library/Caches/GitArbor/SwiftPM).
#
# Requisitos:
#   macOS 15 ou superior, Swift 6.2 ou superior (Xcode ou Command Line Tools) e OpenSSL.
#
# Etapas:
#   1. Executa a suíte de testes; qualquer falha interrompe a instalação.
#   2. Garante uma identidade de assinatura local e estável (criada na primeira execução).
#   3. Monta o pacote .app (Scripts/make_bundle.sh) e o assina com essa identidade.
#   4. Encerra a instância em execução, substitui a instalação e guarda a anterior como backup.
#   5. Abre a nova versão e confirma que ela iniciou.
#
# Versão:
#   MAJOR.MINOR vem do arquivo VERSION; PATCH é o número de commits desde a última alteração
#   desse arquivo; BUILD é o total de commits (sempre crescente). Fora de um repositório Git,
#   usa PATCH = 0 e BUILD = 1.
#
# Assinatura:
#   A identidade é um certificado autoassinado, válido só neste Mac, guardado num chaveiro
#   dedicado em "~/Library/Application Support/Git Arbor/Signing". Como ela não muda entre
#   versões, o macOS continua liberando ao app a chave do GitHub guardada no Chaves sem
#   pedir nova autorização a cada atualização. Para distribuição pública, use
#   Scripts/package_release.sh.
#
# Códigos de saída:
#   0  sucesso
#   1  falha (testes, assinatura, instalação ou inicialização)
#   2  uso incorreto
#
set -euo pipefail

# --------------------------------------------------------------------------------------------
# Configuração
# --------------------------------------------------------------------------------------------

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_NAME="Git Arbor.app"
readonly EXECUTABLE="GitArbor"
readonly TARGET_DIR="${INSTALL_DIR:-$HOME/Applications}"
readonly APP_DIR="$TARGET_DIR/$APP_NAME"
readonly SUPPORT_DIR="$HOME/Library/Application Support/Git Arbor"
readonly BACKUP_DIR="$SUPPORT_DIR/Previous Builds.noindex"
readonly BACKUPS_TO_KEEP=3
readonly SIGNING_DIR="$SUPPORT_DIR/Signing"
readonly SIGNING_KEYCHAIN="$SIGNING_DIR/gitarbor-signing.keychain-db"
readonly SIGNING_PASSWORD_FILE="$SIGNING_DIR/keychain-password"
readonly SIGNING_IDENTITY="Git Arbor Local Signing"

export BUNDLE_ID="${BUNDLE_ID:-io.github.gitarbor.GitArbor}"
export SWIFT_BUILD_ROOT="${SWIFT_BUILD_ROOT:-$HOME/Library/Caches/GitArbor/SwiftPM}"

# --------------------------------------------------------------------------------------------
# Funções auxiliares
# --------------------------------------------------------------------------------------------

# Arquivos e pastas temporários, removidos ao sair (com sucesso ou não).
TEMP_PATHS=()
cleanup() { (( ${#TEMP_PATHS[@]} )) && rm -rf -- "${TEMP_PATHS[@]}"; return 0; }
trap cleanup EXIT

step() { printf '==> %s\n' "$*"; }
warn() { printf 'Aviso: %s\n' "$*" >&2; }
die()  { printf 'Erro: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Espera até `tentativas` × 0,1 s pela condição; retorna 0 se ela ficou verdadeira.
wait_until() {
    local tentativas="$1"; shift
    local i
    for ((i = 0; i < tentativas; i++)); do
        "$@" && return 0
        sleep 0.1
    done
    "$@"
}

process_alive() { kill -0 "$1" 2>/dev/null; }
process_gone()  { ! process_alive "$1"; }
app_running()   { pgrep -f "$APP_DIR/Contents/MacOS/$EXECUTABLE" >/dev/null; }

# --------------------------------------------------------------------------------------------
# Argumentos
# --------------------------------------------------------------------------------------------

LAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=0 ;;
        -h|--help)   usage; exit 0 ;;
        *)           usage >&2; exit 2 ;;
    esac
done

cd "$ROOT"

# --------------------------------------------------------------------------------------------
# Versão
# --------------------------------------------------------------------------------------------

RELEASE="$(tr -d '[:space:]' < VERSION)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VERSION_COMMIT="$(git log -1 --format=%H -- VERSION)"
    PATCH="$(git rev-list --count "${VERSION_COMMIT:+$VERSION_COMMIT..}HEAD")"
    BUILD="$(git rev-list --count HEAD)"
else
    PATCH=0
    BUILD=1
fi
readonly VERSION="$RELEASE.$PATCH"

# --------------------------------------------------------------------------------------------
# 1. Testes
# --------------------------------------------------------------------------------------------

step "Executando os testes"
mkdir -p "$SWIFT_BUILD_ROOT"
TEST_LOG="$(mktemp)"
TEMP_PATHS+=("$TEST_LOG")
if ! swift test --scratch-path "$SWIFT_BUILD_ROOT" >"$TEST_LOG" 2>&1; then
    grep -E "✘|error:" "$TEST_LOG" >&2 || tail -n 30 "$TEST_LOG" >&2
    die "há testes falhando; instalação cancelada."
fi
grep -E "Test run with" "$TEST_LOG" || true

# --------------------------------------------------------------------------------------------
# 2. Identidade de assinatura
# --------------------------------------------------------------------------------------------

create_signing_identity() {
    local tmp p12_password keychain_password legacy=""
    tmp="$(mktemp -d)"
    # A chave privada temporária é removida ao sair, mesmo se algo falhar no meio.
    TEMP_PATHS+=("$tmp")

    openssl rand -hex 32 > "$SIGNING_PASSWORD_FILE"
    chmod 600 "$SIGNING_PASSWORD_FILE"
    keychain_password="$(<"$SIGNING_PASSWORD_FILE")"
    p12_password="$(openssl rand -hex 16)"

    openssl req -new -newkey rsa:2048 -nodes -x509 -sha256 -days 3650 \
        -subj "/CN=$SIGNING_IDENTITY/O=Git Arbor Local" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1

    # O OpenSSL 3 gera PKCS#12 com algoritmos que o `security` do macOS não importa.
    [[ "$(openssl version)" == OpenSSL\ 3* ]] && legacy="-legacy"
    openssl pkcs12 ${legacy:+"$legacy"} -export -out "$tmp/identity.p12" \
        -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$SIGNING_IDENTITY" \
        -passout "pass:$p12_password" >/dev/null 2>&1

    security create-keychain -p "$keychain_password" "$SIGNING_KEYCHAIN"
    security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
    security unlock-keychain -p "$keychain_password" "$SIGNING_KEYCHAIN"
    security import "$tmp/identity.p12" -k "$SIGNING_KEYCHAIN" -P "$p12_password" \
        -T /usr/bin/codesign >/dev/null
    # Permite que o codesign use a chave sem exibir um pedido de autorização.
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$keychain_password" "$SIGNING_KEYCHAIN" >/dev/null

    rm -rf "$tmp"
}

step "Preparando a identidade de assinatura"
mkdir -p -m 700 "$SIGNING_DIR"
if [[ ! -e "$SIGNING_KEYCHAIN" ]]; then
    step "Criando identidade local (somente na primeira execução)"
    create_signing_identity
fi
security unlock-keychain -p "$(<"$SIGNING_PASSWORD_FILE")" "$SIGNING_KEYCHAIN"
CERT_SHA1="$(security find-certificate -c "$SIGNING_IDENTITY" -Z "$SIGNING_KEYCHAIN" \
    | awk '/^SHA-1 hash:/ { print $3; exit }')"
[[ "$CERT_SHA1" =~ ^[[:xdigit:]]{40}$ ]] || die "certificado de assinatura não encontrado em $SIGNING_KEYCHAIN."

# O requisito fixa o identificador e o certificado: é o que o Chaves usa para reconhecer o app.
readonly REQUIREMENT="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$CERT_SHA1\""

# --------------------------------------------------------------------------------------------
# 3. Montagem e assinatura
# --------------------------------------------------------------------------------------------

mkdir -p "$TARGET_DIR"
# A pasta temporária fica no mesmo volume do destino, para a troca final ser um `mv` atômico.
STAGING_DIR="$(mktemp -d "$TARGET_DIR/.GitArbor-install.XXXXXX")"
TEMP_PATHS+=("$STAGING_DIR")
readonly STAGED_APP="$STAGING_DIR/$APP_NAME"

"$ROOT/Scripts/make_bundle.sh" "$STAGING_DIR" "$VERSION" "$BUILD"

step "Assinando"
codesign --force --keychain "$SIGNING_KEYCHAIN" --sign "$CERT_SHA1" --timestamp=none \
    --identifier "$BUNDLE_ID" -r="designated => $REQUIREMENT" "$STAGED_APP"
codesign --verify --deep --strict -R="$REQUIREMENT" "$STAGED_APP"

# --------------------------------------------------------------------------------------------
# 4. Instalação
# --------------------------------------------------------------------------------------------

step "Encerrando a versão em execução"
for pid in $(pgrep -x "$EXECUTABLE" || true); do
    # Só encerra a cópia instalada em $APP_DIR, nunca outra cópia do app.
    [[ "$(ps -p "$pid" -o comm=)" == "$APP_DIR/Contents/MacOS/$EXECUTABLE" ]] || continue
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    if ! wait_until 50 process_gone "$pid"; then
        # O app não mantém estado pendente, então o encerramento forçado é seguro.
        kill -TERM "$pid" 2>/dev/null || true
        wait_until 50 process_gone "$pid" || die "a versão em execução não encerrou; instalação cancelada."
    fi
done

step "Instalando em $APP_DIR"
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)"
if [[ -d "$APP_DIR" ]]; then
    mkdir -p "$BACKUP"
    mv "$APP_DIR" "$BACKUP/$APP_NAME.backup"
fi
if ! mv "$STAGED_APP" "$APP_DIR"; then
    # Restaura a versão anterior se a troca falhar.
    [[ -d "$BACKUP/$APP_NAME.backup" ]] && mv "$BACKUP/$APP_NAME.backup" "$APP_DIR"
    die "não foi possível mover o app para $APP_DIR."
fi
codesign --verify --deep --strict -R="$REQUIREMENT" "$APP_DIR"

# Atualiza o registro do Launch Services (ícone, nome e versão no Finder).
touch "$APP_DIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_DIR" >/dev/null 2>&1 || true

# Mantém apenas os backups mais recentes.
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((BACKUPS_TO_KEEP + 1)) \
    | while IFS= read -r old; do rm -rf -- "$old"; done

# --------------------------------------------------------------------------------------------
# 5. Inicialização
# --------------------------------------------------------------------------------------------

INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
if (( LAUNCH )); then
    step "Abrindo o Git Arbor"
    open "$APP_DIR"
    wait_until 50 app_running || die "o app foi instalado, mas não iniciou."
fi

step "Git Arbor $INSTALLED_VERSION (build $BUILD) instalado em $APP_DIR"
