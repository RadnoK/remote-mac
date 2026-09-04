#!/bin/bash
# Builds AppIcon.icns from the asset-catalog-shaped PNG set.
# iconutil expects @2x naming, the catalog uses -2x, hence the rename.
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
