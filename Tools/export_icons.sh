#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

master="Design/ClickyAppIcon.png"
iconset=".clicky-icon-export.iconset"
if [[ -e "$iconset" ]]; then
    echo "Icon export directory already exists: $iconset" >&2
    exit 1
fi
mkdir "$iconset"
trap 'rm -rf "$iconset"' EXIT
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((points * scale))
        suffix=""
        if [[ "$scale" == 2 ]]; then suffix="@2x"; fi
        sips -z "$pixels" "$pixels" "$master" \
            --out "$iconset/icon_${points}x${points}${suffix}.png" >/dev/null
    done
done
iconutil -c icns "$iconset" -o Clicky/Resources/Clicky.icns

logo="Clicky/Assets.xcassets/ClickyLogo.imageset"
sips -z 128 128 "$master" --out "$logo/logo.png" >/dev/null
sips -z 256 256 "$master" --out "$logo/logo@2x.png" >/dev/null

menu_icons="Clicky/Assets.xcassets/ClickyMark.imageset"
sips -z 18 18 Design/ClickyMenuMark.png --out "$menu_icons/mark.png" >/dev/null
sips -z 36 36 Design/ClickyMenuMark.png --out "$menu_icons/mark@2x.png" >/dev/null
echo "Exported macOS app and menu bar icon sizes."
