#!/usr/bin/env bash
#
# Trae la librería nativa de PDFium para poder correr las pruebas de lectura
# de PDF.
#
# Por qué hace falta: en la app, el complemento `pdfium_flutter` empaqueta el
# binario dentro del paquete de cada plataforma y no hay nada que preparar.
# Pero `flutter test` corre en la máquina de desarrollo, fuera de ese
# empaquetado, así que ahí hay que darle la ruta a mano. Sin esto, la prueba
# del lector de PDF se salta —lo dice en su mensaje— y el lector quedaría sin
# verificar.
#
# Uso:
#   export PDFIUM_PATH="$(tool/fetch_pdfium.sh)"
#   flutter test
#
# Solo escribe en `.pdfium/`, que está en .gitignore.

set -euo pipefail

# La misma versión que fija `pdfium_dart`, para probar contra lo que la app
# va a usar de verdad y no contra otra cosa.
RELEASE="chromium%2F7811"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/.pdfium"

case "$(uname -s)" in
  Linux*)  PLATFORM="linux";  LIB="lib/libpdfium.so" ;;
  Darwin*) PLATFORM="mac";    LIB="lib/libpdfium.dylib" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="win"; LIB="bin/pdfium.dll" ;;
  *) echo "Sistema no reconocido: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCH="x64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Arquitectura no reconocida: $(uname -m)" >&2; exit 1 ;;
esac

TARGET="$DEST/$PLATFORM-$ARCH/$LIB"

# Ya estaba: no se vuelve a bajar.
if [ -f "$TARGET" ]; then
  echo "$TARGET"
  exit 0
fi

URL="https://github.com/bblanchon/pdfium-binaries/releases/download/$RELEASE/pdfium-$PLATFORM-$ARCH.tgz"

mkdir -p "$DEST/$PLATFORM-$ARCH"
# Todo el ruido va a stderr: la salida estándar es solo la ruta, para poder
# hacer PDFIUM_PATH="$(tool/fetch_pdfium.sh)".
echo "Bajando PDFium desde $URL" >&2
curl -sSL --fail --max-time 300 "$URL" \
  | tar -xz -C "$DEST/$PLATFORM-$ARCH" >&2

if [ ! -f "$TARGET" ]; then
  echo "El archivo bajado no contiene $LIB" >&2
  exit 1
fi

echo "$TARGET"
