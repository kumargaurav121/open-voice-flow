#!/usr/bin/env bash
# Builds Resources/AppIcon.icns from Resources/AppIcon.svg (needs rsvg-convert: brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")/.."
set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir"
for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" Resources/AppIcon.svg -o "$set_dir/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) Resources/AppIcon.svg -o "$set_dir/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$set_dir" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
