#!/usr/bin/env bash
#
# Trae los dos archivos que drift necesita para compilar la base de datos a
# WebAssembly: el binario de sqlite3 y el worker que hospeda la base en un
# hilo aparte del navegador.
#
# Por qué hace falta: a diferencia de sherpa_onnx_web, que empaqueta su
# propio WASM adentro del paquete de Dart, drift documenta estos dos
# archivos como algo que cada proyecto tiene que traer a mano y dejar en
# `web/`. No vienen con `flutter pub get`.
#
# Se bajan de los releases de GitHub del propio drift, en la versión exacta
# que fija `pubspec.lock` — mezclar versiones distintas de paquete y binario
# es la fuente más común de errores confusos en el foro del proyecto.
#
# Uso:
#   tool/fetch_sqlite3_wasm.sh
#
# Escribe directo en `web/sqlite3.wasm` y `web/drift_worker.js`: a
# diferencia de PDFium, que solo hace falta para correr las pruebas en esta
# máquina, estos dos archivos viajan con la app que se sirve a quien la use,
# así que quedan versionados en el repositorio como el resto de `web/`.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# La misma versión que fija pubspec.lock para `drift`: los releases de
# GitHub usan el tag `drift-X.Y.Z`, y los dos archivos solo son compatibles
# entre sí cuando salen del mismo release.
DRIFT_VERSION="$(awk '/^  drift:$/{found=1} found && /version:/{print; exit}' "$ROOT/pubspec.lock" | sed -E 's/.*"([0-9.]+)".*/\1/')"

if [ -z "$DRIFT_VERSION" ]; then
  echo "No se pudo leer la versión de drift desde pubspec.lock" >&2
  exit 1
fi

BASE_URL="https://github.com/simolus3/drift/releases/download/drift-$DRIFT_VERSION"

echo "Bajando sqlite3.wasm y drift_worker.js del release drift-$DRIFT_VERSION" >&2

curl -sSL --fail --max-time 300 "$BASE_URL/sqlite3.wasm" -o "$ROOT/web/sqlite3.wasm"
curl -sSL --fail --max-time 300 "$BASE_URL/drift_worker.js" -o "$ROOT/web/drift_worker.js"

echo "Listo: web/sqlite3.wasm y web/drift_worker.js actualizados a drift-$DRIFT_VERSION" >&2
