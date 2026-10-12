#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app_icons="Clicky/Assets.xcassets/AppIcon.appiconset"
for pixels in 16 32 64 128 256 512; do
    sips -z "$pixels" "$pixels" "$app_icons/icon-1024.png" \
        --out "$app_icons/icon-$pixels.png" >/dev/null
done

menu_icons="Clicky/Assets.xcassets/ClickyMark.imageset"
sips -z 18 18 Design/ClickyMenuMark.png --out "$menu_icons/mark.png" >/dev/null
sips -z 36 36 Design/ClickyMenuMark.png --out "$menu_icons/mark@2x.png" >/dev/null
echo "Exported macOS app and menu bar icon sizes."
