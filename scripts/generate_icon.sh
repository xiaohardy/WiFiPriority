#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICONSET="Resources/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/draw_icon.swift "$ICONSET/icon_512x512@2x.png"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" \
            "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" \
            "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png"; do
    read -r size name <<< "$spec"
    sips -s format png -z "$size" "$size" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
