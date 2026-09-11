#!/usr/bin/env bash
#
# Trae los archivos que hacen falta para reconocer texto en imágenes en la
# web: la librería de Tesseract compilada a WebAssembly y los datos
# entrenados de español e inglés. Apache-2.0 los tres orígenes —ver la
# decisión 10 en docs/arquitectura.md—.
#
# Por qué no vienen de un paquete de Dart: no existe uno que empaquete
# Tesseract-WASM para Flutter web con sus assets, a diferencia de
# sherpa_onnx_web. Se traen sueltos, igual que sqlite3.wasm y
# drift_worker.js, y quedan commiteados en el repositorio junto al resto
# de `web/` porque viajan con la app que se sirve a quien la use.
#
# Fuentes:
#   - tesseract.js y su worker: el paquete de npm, bajado directo del
#     registro (no de una CDN, que este entorno bloquea).
#   - El núcleo en WebAssembly: el paquete tesseract.js-core, en la
#     versión que declara compatible el tesseract.js elegido.
#   - Los datos entrenados: el repositorio tessdata_fast de tesseract-ocr,
#     la variante que el propio proyecto Tesseract recomienda para uso
#     interactivo en vez del "best" —más preciso, pero mucho más lento—.
#
# Solo se trae la variante SIMD+LSTM del núcleo: todos los navegadores con
# soporte real de WebAssembly llevan años soportando SIMD, así que sumar
# las otras tres variantes solo agrandaría la descarga sin que nadie real
# las fuera a usar.
#
# Uso:
#   tool/fetch_tesseract_web.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TESSERACT_JS_VERSION="6.0.1"
TESSERACT_CORE_VERSION="6.1.2"
# Un commit fijo del repositorio de datos, no una rama: así una
# actualización ahí no cambia lo que esta app reconoce sin que nadie lo
# note.
TESSDATA_REF="87416418657359cb625c412a48b6e1d6d41c29bd"

DEST_JS="$ROOT/web/tesseract"
DEST_DATA="$ROOT/web/tessdata"
mkdir -p "$DEST_JS" "$DEST_DATA"

echo "Bajando tesseract.js $TESSERACT_JS_VERSION..." >&2
curl -sSL --fail --max-time 120 \
  "https://registry.npmjs.org/tesseract.js/-/tesseract.js-$TESSERACT_JS_VERSION.tgz" \
  -o "$WORK/tesseract.tgz"
tar -xzf "$WORK/tesseract.tgz" -C "$WORK"
cp "$WORK/package/dist/tesseract.min.js" "$DEST_JS/"
cp "$WORK/package/dist/worker.min.js" "$DEST_JS/"
cp "$WORK/package/dist/tesseract.min.js.LICENSE.txt" "$DEST_JS/"

echo "Bajando tesseract.js-core $TESSERACT_CORE_VERSION..." >&2
curl -sSL --fail --max-time 180 \
  "https://registry.npmjs.org/tesseract.js-core/-/tesseract.js-core-$TESSERACT_CORE_VERSION.tgz" \
  -o "$WORK/tesseract-core.tgz"
tar -xzf "$WORK/tesseract-core.tgz" -C "$WORK" \
  package/tesseract-core-simd-lstm.wasm \
  package/tesseract-core-simd-lstm.wasm.js \
  package/LICENSE
cp "$WORK/package/tesseract-core-simd-lstm.wasm" "$DEST_JS/"
cp "$WORK/package/tesseract-core-simd-lstm.wasm.js" "$DEST_JS/"
cp "$WORK/package/LICENSE" "$DEST_JS/tesseract-core.LICENSE.txt"

echo "Bajando los datos entrenados de inglés y español..." >&2
BASE_URL="https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/$TESSDATA_REF"
curl -sSL --fail --max-time 120 "$BASE_URL/eng.traineddata" -o "$DEST_DATA/eng.traineddata"
curl -sSL --fail --max-time 120 "$BASE_URL/spa.traineddata" -o "$DEST_DATA/spa.traineddata"
curl -sSL --fail --max-time 60 "$BASE_URL/LICENSE" -o "$DEST_DATA/LICENSE"

echo "Listo: web/tesseract/ y web/tessdata/ actualizados." >&2
