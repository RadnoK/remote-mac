#!/bin/bash
# Builds AppIcon.icns from the asset-catalog-shaped PNG set.
#
# iconutil requires an .iconset directory with @2x naming. The catalog already
# uses that convention, but the rename below also accepts a -2x set, so a
# catalog exported by a tool that prefers dashes still builds.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Resources/AppIcon.appiconset"
OUT="$ROOT/dist"
SET="$OUT/AppIcon.iconset"

rm -rf "$SET"; mkdir -p "$SET"
for f in "$SRC"/icon_*.png; do
  base="$(basename "$f" .png)"
  cp "$f" "$SET/${base/-2x/@2x}.png"
done
iconutil -c icns "$SET" -o "$OUT/AppIcon.icns"
echo "Built $OUT/AppIcon.icns"
