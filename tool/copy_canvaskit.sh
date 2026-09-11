#!/usr/bin/env bash
#
# Copia CanvasKit desde el propio SDK de Flutter instalado hacia `web/`,
# para que `flutter_bootstrap.js` lo cargue local y no desde la CDN de
# Google (ver la decisión 9 en docs/arquitectura.md).
#
# Distinto de `fetch_sqlite3_wasm.sh` a propósito: ese trae un binario de
# otro proyecto, versionado aparte, así que hay que bajarlo de un release y
# dejarlo commiteado. CanvasKit en cambio **ya está en el disco**, adentro
# del SDK de Flutter que arma el resto de la build: copiarlo de ahí es lo
# que garantiza que la versión coincide siempre con la que compiló la app,
# sin un archivo commiteado que se pueda desincronizar en la próxima
# actualización de Flutter. Por eso `web/canvaskit/` está en `.gitignore`
# y este script corre antes de cada build en vez de una vez y listo.
#
# Uso:
#   tool/copy_canvaskit.sh
#   flutter build web

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FLUTTER_BIN="$(command -v flutter)"
FLUTTER_ROOT="$(cd "$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")" && pwd)"
SOURCE="$FLUTTER_ROOT/bin/cache/flutter_web_sdk/canvaskit"

if [ ! -d "$SOURCE" ]; then
  echo "No se encontró CanvasKit en $SOURCE — ¿corriste 'flutter precache --web' o compilaste para web alguna vez?" >&2
  exit 1
fi

DEST="$ROOT/web/canvaskit"
rm -rf "$DEST"
cp -r "$SOURCE" "$DEST"

echo "CanvasKit copiado a web/canvaskit/ desde $FLUTTER_ROOT" >&2
