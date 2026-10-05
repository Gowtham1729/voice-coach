#!/usr/bin/env bash
# Copies the launch-film assets into Remotion's public/ folder.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="promo-2026-10-04/assets"
DST="public/promo-2026-10-04"

mkdir -p "$DST/ui" "$DST/product" "$DST/brand" "$DST/icons" "$DST/fonts"

cp "$SRC"/components/*.png "$DST/ui/"
cp "$SRC/product/docs/01-home.png" "$SRC/product/docs/09-new-mimic.png" "$DST/product/"
cp "$SRC/brand/brand-mark.png" "$DST/brand/"
cp "$SRC/brand/icons/arrow-down.svg" "$SRC/brand/icons/LICENSE" "$DST/icons/"
cp "$SRC/fonts/space-grotesk-bold.ttf" "$SRC/fonts/dm-sans.ttf" \
  "$SRC/fonts/Space-Grotesk-OFL.txt" "$SRC/fonts/DM-Sans-OFL.txt" "$DST/fonts/"

echo "Synced promo assets into $DST"
