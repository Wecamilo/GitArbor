#!/bin/bash
#
# package_release.sh — gera o pacote de distribuição do Git Arbor.
#
# Uso:
#   Scripts/package_release.sh <versão>        ex.: Scripts/package_release.sh v1.0.0
#
# Resultado (na pasta dist/):
#   GitArbor-<versão>.zip          o app, pronto para arrastar para Aplicativos;
#   GitArbor-<versão>.zip.sha256   soma de verificação SHA-256 do zip.
#
# O app recebe assinatura ad hoc (sem certificado da Apple). Ela garante a integridade do
# pacote, mas o Gatekeeper pede liberação manual na primeira abertura; o README explica como.
# Usado pela automação .github/workflows/release.yml a cada etiqueta v*.
#
set -euo pipefail

if [[ $# -ne 1 ]]; then
    printf 'Uso: %s <versão>\n' "$0" >&2
    exit 2
fi
readonly VERSION="${1#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([.-][0-9A-Za-z.-]+)?$ ]] \
    || { printf 'Erro: versão inválida: %s\n' "$1" >&2; exit 2; }

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIST="$ROOT/dist"
readonly APP="$DIST/Git Arbor.app"
readonly ZIP_NAME="GitArbor-$VERSION.zip"

cd "$ROOT"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

rm -rf "$DIST"
mkdir -p "$DIST"
"$ROOT/Scripts/make_bundle.sh" "$DIST" "$VERSION" "$BUILD"

printf '==> Assinando (ad hoc)\n'
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

printf '==> Compactando\n'
# `ditto` preserva a estrutura e as permissões do pacote .app dentro do zip.
ditto -c -k --keepParent "$APP" "$DIST/$ZIP_NAME"
(cd "$DIST" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")

printf '==> Pronto: dist/%s\n' "$ZIP_NAME"
cat "$DIST/$ZIP_NAME.sha256"
