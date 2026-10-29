#!/usr/bin/env bash
#
# Trae las tipografías de «Lo creado» (F43): las de las presentaciones y las
# infografías, empaquetadas con la app como Inter —ver la decisión 12 en
# docs/arquitectura.md y tool/fetch_inter_font.sh—, para que una diapositiva
# se dibuje igual sin internet, con Gemma, y en el PDF que se exporta.
#
# Seis pares de títulos y texto (ver `CreationFontPair`), con siete familias
# además de Inter, que ya venía:
#
#   - Playfair Display (y su itálica): serif de alto contraste para títulos.
#   - Lora (y su itálica): serif de libro, para leer.
#   - Source Sans 3: sans humanista, el texto de la serif de libro.
#   - Space Grotesk: grotesca geométrica, la de los mazos técnicos.
#   - Nunito: sans redondeada y amable.
#   - Caveat: manuscrita, para títulos de pizarra y papel.
#   - JetBrains Mono: monoespaciada, para cifras, fechas y datos.
#
# Todas con la SIL Open Font License 1.1: el script baja el OFL.txt de cada
# una de su propia carpeta del repositorio y se niega a seguir si no dice eso,
# así una fuente que algún día cambie de licencia no entra sin que nadie lo
# note. La licencia queda al lado de cada fuente, en assets/fonts/.
#
# Archivos variables (eje "wght") en vez de uno estático por peso: un solo
# archivo cubre del Regular al Black, y la app elige la instancia con
# `FontVariation` además del `fontWeight` (ver `CreationFontPair`). Se guardan
# sin los corchetes del nombre original (`Lora[wght].ttf`), que en una ruta de
# asset se vuelven un problema en la web.
#
# Fijado a un commit concreto de github.com/google/fonts, no a una rama: así
# una actualización ahí no cambia el dibujo de un mazo ya hecho sin que nadie
# lo note. En total suman unos 2,7 MB.
#
# Uso:
#   tool/fetch_creation_fonts.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FONTS_REF="9862abc066c9b83bf84c3e8ed1fc2d8d48f9bbf0"
BASE_URL="https://raw.githubusercontent.com/google/fonts/$FONTS_REF/ofl"

DEST="$ROOT/assets/fonts"
mkdir -p "$DEST"

# carpeta del repositorio | archivo de origen | nombre en assets/fonts
FILES=(
  "playfairdisplay|PlayfairDisplay[wght].ttf|PlayfairDisplay-Variable.ttf"
  "playfairdisplay|PlayfairDisplay-Italic[wght].ttf|PlayfairDisplay-Italic-Variable.ttf"
  "lora|Lora[wght].ttf|Lora-Variable.ttf"
  "lora|Lora-Italic[wght].ttf|Lora-Italic-Variable.ttf"
  "sourcesans3|SourceSans3[wght].ttf|SourceSans3-Variable.ttf"
  "spacegrotesk|SpaceGrotesk[wght].ttf|SpaceGrotesk-Variable.ttf"
  "nunito|Nunito[wght].ttf|Nunito-Variable.ttf"
  "caveat|Caveat[wght].ttf|Caveat-Variable.ttf"
  "jetbrainsmono|JetBrainsMono[wght].ttf|JetBrainsMono-Variable.ttf"
)

# carpeta del repositorio | nombre de su licencia en assets/fonts
LICENSES=(
  "playfairdisplay|PlayfairDisplay-OFL.txt"
  "lora|Lora-OFL.txt"
  "sourcesans3|SourceSans3-OFL.txt"
  "spacegrotesk|SpaceGrotesk-OFL.txt"
  "nunito|Nunito-OFL.txt"
  "caveat|Caveat-OFL.txt"
  "jetbrainsmono|JetBrainsMono-OFL.txt"
)

for entry in "${LICENSES[@]}"; do
  IFS='|' read -r folder target <<<"$entry"
  echo "Bajando la licencia de $folder..." >&2
  curl -sSL --fail --max-time 30 "$BASE_URL/$folder/OFL.txt" -o "$DEST/$target"
  if ! grep -q "SIL OPEN FONT LICENSE Version 1.1" "$DEST/$target"; then
    echo "La licencia de $folder no es la SIL OFL 1.1: no se sigue." >&2
    rm -f "$DEST/$target"
    exit 1
  fi
done

for entry in "${FILES[@]}"; do
  IFS='|' read -r folder source target <<<"$entry"
  # Los corchetes del nombre van codificados en la dirección.
  encoded="${source//\[/%5B}"
  encoded="${encoded//\]/%5D}"
  echo "Bajando $source..." >&2
  curl -sSL --fail --max-time 60 "$BASE_URL/$folder/$encoded" -o "$DEST/$target"
done

echo "Listo: assets/fonts/ actualizado." >&2
