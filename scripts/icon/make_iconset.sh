#!/usr/bin/env bash
#
# Render the Duo cat into the app's AppIcon asset catalog at every size macOS
# asks for — both the light squircle (out/cat.svg) and the dark "moonlit"
# appearance (out/cat-dark.svg) — plus the runtime imageset, the standalone
# AppIconDark.png master, and a DuoUpdater.icns fallback.
#
# Re-run after editing cat.py (the icon source):  python3 cat.py && ./make_iconset.sh
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SVG="$HERE/out/cat.svg"
SVG_DARK="$HERE/out/cat-dark.svg"
SET="$REPO/App/Resources/Assets.xcassets/AppIcon.appiconset"
RUNTIME="$REPO/App/Resources/Assets.xcassets/AppRuntimeIcon.imageset"
ICONSET="$HERE/out/DuoUpdater.iconset"

command -v rsvg-convert >/dev/null || { echo "need rsvg-convert (brew install librsvg)"; exit 1; }
[ -f "$SVG" ]      || { echo "missing $SVG — run: python3 cat.py"; exit 1; }
[ -f "$SVG_DARK" ] || { echo "missing $SVG_DARK — run: python3 cat.py"; exit 1; }

mkdir -p "$SET" "$RUNTIME" "$ICONSET"

render()      { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$2"; }
render_dark() { rsvg-convert -w "$1" -h "$1" "$SVG_DARK" -o "$2"; }

# Asset-catalog PNGs — one file per pixel size, light + dark appearances.
for px in 16 32 64 128 256 512 1024; do
  render      "$px" "$SET/icon_${px}.png"
  render_dark "$px" "$SET/dark_${px}.png"
done

cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "dark_16.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "dark_32.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "dark_32.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "dark_64.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "dark_128.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "dark_256.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "dark_256.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "dark_512.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "dark_512.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "dark_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# Top-level asset-catalog Contents.json (created once if missing).
XC="$REPO/App/Resources/Assets.xcassets/Contents.json"
[ -f "$XC" ] || cat > "$XC" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON

# Runtime imageset (AppIcon.swift re-applies this so the Dock/⌘-Tab icon
# tracks the live appearance) + standalone dark master used by the project.
cp "$SET/icon_1024.png" "$RUNTIME/light.png"
cp "$SET/dark_1024.png" "$RUNTIME/dark.png"
cp "$SET/dark_1024.png" "$REPO/App/Resources/AppIconDark.png"

cat > "$RUNTIME/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "filename" : "light.png", "scale" : "1x" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "mac", "filename" : "dark.png", "scale" : "1x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# Standalone .icns (handy for docs / non-Xcode use) — light appearance.
declare -a MAP=( "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x"
                 "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256"
                 "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x" )
for m in "${MAP[@]}"; do
  px="${m%%:*}"; name="${m##*:}"
  render "$px" "$ICONSET/${name}.png"
done
iconutil -c icns "$ICONSET" -o "$HERE/out/DuoUpdater.icns"

echo "✓ wrote asset catalog (light + dark): $SET"
echo "✓ synced runtime imageset + AppIconDark.png"
echo "✓ wrote $HERE/out/DuoUpdater.icns"
