#!/bin/bash
# Renders the icon shown on the About page from the app icon, NineRings/AppIcon.icon, with Icon Composer's own tool,
# into NineRings/Assets.xcassets/AboutIcon.imageset: the light and the dark rendition, 96 points at 3x. Run it again
# whenever the app icon changes; a package test (AppRulesTests) fails until it is.
#
#   scripts/render-about-icon.sh
#
# Why a copy: an iOS app cannot load its own icon. UIImage(named: "AppIcon") works in a local build, whose asset
# catalog holds the icon as flat images, but crashes the app from TestFlight and the App Store, where the icon is
# processed again for each device.
set -euo pipefail
cd "$(dirname "$0")/.."

ICON=NineRings/AppIcon.icon
OUT=NineRings/Assets.xcassets/AboutIcon.imageset
DEVELOPER=$(xcode-select -p)
ICTOOL="$DEVELOPER/../Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -x "$ICTOOL" ]] || ICTOOL="$DEVELOPER/usr/bin/ictool"

mkdir -p "$OUT"
for rendition in Default Dark; do
    file="$OUT/about-icon-$(echo "$rendition" | tr '[:upper:]' '[:lower:]').png"
    "$ICTOOL" "$ICON" --export-image --output-file "$file" --platform iOS --rendition "$rendition" \
        --width 96 --height 96 --scale 3 > /dev/null
    [[ -s "$file" ]] || { echo "Icon Composer made no $file" >&2; exit 1; }
done

# What the copy was rendered from, so that a test can tell when the app icon has changed since.
(cd NineRings && find AppIcon.icon -type f ! -name .DS_Store -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) \
    | shasum -a 256 | cut -d' ' -f1 > scripts/about-icon-source.sha256
echo "Rendered $OUT from $ICON ($(cat scripts/about-icon-source.sha256))."
