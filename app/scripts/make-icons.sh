#!/bin/sh
# Regenerates app/Resources/AppIcon.icns and the 16pt status-item PNGs from
# app/Resources/icon.png (1024x1024, copied from easy-otp/assets/icon.png).
set -eu
cd "$(dirname "$0")/.."

SRC=Resources/icon.png
SET=build/AppIcon.iconset
rm -rf "$SET"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SRC" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SRC" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
sips -z 16 16 "$SRC" --out Resources/StatusIcon.png >/dev/null
sips -z 32 32 "$SRC" --out Resources/StatusIcon@2x.png >/dev/null
echo "Resources/AppIcon.icns Resources/StatusIcon.png Resources/StatusIcon@2x.png"
