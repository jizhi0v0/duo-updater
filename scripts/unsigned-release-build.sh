#!/usr/bin/env bash
# Compile the shipping App and CLI in Release without signing or installing them.
# This is a PR gate; signing and notarization remain in the release workflow.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/App"
PYTHON="${PYTHON:-python3}"
DD="${UNSIGNED_RELEASE_DD:-$("$PYTHON" "$REPO/scripts/derived_data_path.py" unsigned-release "$REPO")}"
XCODEGEN="$("$REPO/scripts/pinned-xcodegen.sh")"

(cd "$APP_DIR" && "$XCODEGEN" generate)
# XcodeGen recreates the workspace without its pins. Use the same committed
# dependency revisions as notarize.sh, rather than resolving movable tags.
pins_dir="$APP_DIR/DuoUpdater.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$pins_dir"
cp "$APP_DIR/Package.resolved" "$pins_dir/Package.resolved"

for scheme in DuoUpdater duo-cli; do
    echo "Building $scheme (Release, signing disabled)"
    xcodebuild -project "$APP_DIR/DuoUpdater.xcodeproj" \
        -scheme "$scheme" -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$DD" \
        -onlyUsePackageVersionsFromResolvedFile \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
        build
done

for product in "$DD/Build/Products/Release/DuoUpdater.app/Contents/MacOS/DuoUpdater" \
               "$DD/Build/Products/Release/duo-cli"; do
    if [ ! -x "$product" ]; then
        echo "::error::Release build produced no executable at $product" >&2
        exit 1
    fi
done
echo "App and CLI unsigned Release builds passed."
