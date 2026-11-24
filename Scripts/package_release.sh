#!/bin/bash
# Gera a versão para baixar: dist/GitArbor-<versão>.zip com o app assinado "ad hoc"
# (sem conta paga de desenvolvedor da Apple). Usado pela automação de versões do GitHub.
# Uso: Scripts/package_release.sh <versão>     ex.: Scripts/package_release.sh 1.0.0
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Uso: $0 <versão>" >&2
    exit 2
fi
VERSION="${1#v}"

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$ROOT"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

"$ROOT/Scripts/make_bundle.sh" "$DIST" "$VERSION" "$BUILD"
APP="$DIST/Git Arbor.app"

echo "==> Assinando (ad hoc)..."
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

ZIP_NAME="GitArbor-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$DIST/$ZIP_NAME"
(cd "$DIST" && shasum -a 256 "$ZIP_NAME" | tee "$ZIP_NAME.sha256")
echo "==> Pronto: dist/$ZIP_NAME"
