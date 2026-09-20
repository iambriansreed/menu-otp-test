#!/bin/sh
# Regenerates app/Resources/AppIcon.icns and the 16pt status-item PNGs.
#
# Two 1024x1024 sources, because the two icons want opposite things:
#   icon.png   the app icon: a full-bleed charcoal tile with the glyph on it. It runs edge
#              to edge with no rounding of its own, because macOS 26 masks every app icon
#              into the system squircle; artwork that rounds itself and leaves the corners
#              transparent gets the system's default grey showing through them.
#   glyph.png  the bare QR glyph, white on transparent. The status item draws it as a
#              template image, which uses the alpha alone and ignores the colour, so it
#              must not carry the tile.
set -eu
cd "$(dirname "$0")/.."

SRC=Resources/icon.png
GLYPH=Resources/glyph.png
SET=build/AppIcon.iconset
rm -rf "$SET"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SRC" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SRC" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
sips -z 16 16 "$GLYPH" --out Resources/StatusIcon.png >/dev/null
sips -z 32 32 "$GLYPH" --out Resources/StatusIcon@2x.png >/dev/null
echo "Resources/AppIcon.icns Resources/StatusIcon.png Resources/StatusIcon@2x.png"
