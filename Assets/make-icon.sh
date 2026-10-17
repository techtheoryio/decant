#!/bin/sh
# Renders Assets/AppIcon.svg into Sources/Decant/Resources/AppIcon.icns. Needs rsvg-convert (brew install librsvg).
set -e
cd "$(dirname "$0")/.."
set_dir=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set_dir" Sources/Decant/Resources
for s in 16 32 128 256 512; do
  rsvg-convert -w $s -h $s Assets/AppIcon.svg -o "$set_dir/icon_${s}x${s}.png"
  rsvg-convert -w $((s * 2)) -h $((s * 2)) Assets/AppIcon.svg -o "$set_dir/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$set_dir" -o Sources/Decant/Resources/AppIcon.icns
