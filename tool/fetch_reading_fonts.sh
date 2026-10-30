#!/usr/bin/env bash
#
# Trae la tipografía de lectura que no venía con la app (F47, paso 1): las
# cinco de «Apariencia» del marco de lectura son Lora, Source Sans 3, Inter y
# Nunito —que ya viajan con la app, ver tool/fetch_inter_font.sh y
# tool/fetch_creation_fonts.sh— y esta:
#
#   - Atkinson Hyperlegible Next (y su itálica): la del Braille Institute,
#     dibujada para que cada letra se distinga de las parecidas (la l, la I y
#     el 1; la O y el 0) con poca visión. La de quien necesita leer sin
#     esfuerzo.
#
# Con la SIL Open Font License 1.1, como las demás: el script baja el OFL.txt
# de su carpeta del repositorio y se niega a seguir si no dice eso. La
# licencia queda al lado de la fuente, en assets/fonts/.
#
# Archivos variables (eje "wght"), sin los corchetes del nombre original, y
# fijados a un commit concreto de github.com/google/fonts: una actualización
# ahí no cambia lo que se lee sin que nadie lo note. Suman unos 240 KB.
#
# Uso:
#   tool/fetch_reading_fonts.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FONTS_REF="95f4904fc8bcf26d3420fe315560c96417c6dec7"
BASE_URL="https://raw.githubusercontent.com/google/fonts/$FONTS_REF/ofl"

DEST="$ROOT/assets/fonts"
mkdir -p "$DEST"

FOLDER="atkinsonhyperlegiblenext"
LICENSE="AtkinsonHyperlegibleNext-OFL.txt"

# archivo de origen | nombre en assets/fonts
FILES=(
  "AtkinsonHyperlegibleNext[wght].ttf|AtkinsonHyperlegibleNext-Variable.ttf"
  "AtkinsonHyperlegibleNext-Italic[wght].ttf|AtkinsonHyperlegibleNext-Italic-Variable.ttf"
)

echo "Bajando la licencia de $FOLDER..." >&2
curl -sSL --fail --max-time 30 "$BASE_URL/$FOLDER/OFL.txt" -o "$DEST/$LICENSE"
if ! grep -q "SIL OPEN FONT LICENSE Version 1.1" "$DEST/$LICENSE"; then
  echo "La licencia de $FOLDER no es la SIL OFL 1.1: no se sigue." >&2
  rm -f "$DEST/$LICENSE"
  exit 1
fi

for entry in "${FILES[@]}"; do
  IFS='|' read -r source target <<<"$entry"
  # Los corchetes del nombre van codificados en la dirección.
  encoded="${source//\[/%5B}"
  encoded="${encoded//\]/%5D}"
  echo "Bajando $source..." >&2
  curl -sSL --fail --max-time 60 "$BASE_URL/$FOLDER/$encoded" -o "$DEST/$target"
done

echo "Listo: assets/fonts/ actualizado." >&2
