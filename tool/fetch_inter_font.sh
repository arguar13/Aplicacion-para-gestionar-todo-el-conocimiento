#!/usr/bin/env bash
#
# Trae la tipografía Inter para empaquetarla con la app, en vez de bajarla
# en tiempo de ejecución como hacía `google_fonts` —ver la decisión 12 en
# docs/arquitectura.md—. SIL Open Font License 1.1, verificado contra el
# LICENSE.txt real del propio repositorio.
#
# Un solo archivo variable (`InterVariable.ttf`, eje "wght") en vez de un
# archivo estático por variante: la app solo usa dos pesos —Regular y
# Medium, los dos únicos que emplea la escala tipográfica por defecto de
# Material 3—, y Flutter sabe elegir la instancia correcta de un mismo
# archivo variable según el `weight:` declarado en pubspec.yaml para cada
# entrada.
#
# Fijado a un commit concreto del repositorio oficial, no a una rama: así
# una actualización ahí no cambia la tipografía de esta app sin que nadie
# lo note.
#
# Uso:
#   tool/fetch_inter_font.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INTER_REF="353b61b9f4430d5f420d56605a6e7993e0941470"
BASE_URL="https://raw.githubusercontent.com/rsms/inter/$INTER_REF"

DEST="$ROOT/assets/fonts"
mkdir -p "$DEST"

echo "Bajando InterVariable.ttf..." >&2
curl -sSL --fail --max-time 60 \
  "$BASE_URL/docs/font-files/InterVariable.ttf" \
  -o "$DEST/InterVariable.ttf"

curl -sSL --fail --max-time 30 "$BASE_URL/LICENSE.txt" -o "$DEST/LICENSE.txt"

echo "Listo: assets/fonts/ actualizado." >&2
