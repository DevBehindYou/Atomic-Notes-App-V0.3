#!/usr/bin/env bash
# Rebuilds the README art in Project-Images/README from the HTML templates in this folder.
# The templates use the App's bundled fonts (assets/fonts) and the screens in Project-Images/Mockups.
#
#   CHROME="/path/to/chrome" bash Project-Images/README/src/render.sh
#
# Needs Google Chrome or Chromium (headless). Run it from any folder.
set -euo pipefail

CHROME="${CHROME:-google-chrome}"
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="$(dirname "$SRC")"
PROFILE="$(mktemp -d)"

shot() { # page width height scale out [background]
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --default-background-color="${6:-00000000}" --force-device-scale-factor="$4" \
    --window-size="$2,$3" --user-data-dir="$PROFILE" \
    --screenshot="$OUT/$5" "file://$SRC/$1" >/dev/null 2>&1
}

shot hero.html 1280 640 2 hero.png
shot og.html 1200 630 1 og-banner.png F4F5F1FF
shot tiers.html 1280 372 2 tiers.png

for pair in 03:notes 04:checklist 05:editor 12:encryption 14:energy 15:convert-coins 18:notifications \
            09:security 08:cloud-sync 10:danger-zone 07:database 13:energy-popup 16:coin-store; do
  shot "frame.html?n=${pair%%:*}" 340 720 2 "screen-${pair#*:}.png"
done

rm -rf "$PROFILE"
echo "Art written to $OUT"
