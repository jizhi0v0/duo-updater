#!/usr/bin/env bash
# Compile the shipping App and CLI in Release without signing or installing them.
# This is a PR gate; signing and notarization remain in the release workflow.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/App"
PYTHON="${PYTHON:-python3}"
DD="${UNSIGNED_RELEASE_DD:-$("$PYTHON" "$REPO/scripts/derived_data_path.py" unsigned-release "$REPO")}"
XCODEGEN="$("$REPO/scripts/pinned-xcodegen.sh")"

# CI generated this revision's project before restoring its cache. Local runs
# still regenerate: source additions can change the project without editing the
# spec. This flag skips generation only, never either Release build below.
if [ "${XCODE_PROJECT_PREGENERATED:-0}" != 1 ] \
   || [ ! -f "$APP_DIR/DuoUpdater.xcodeproj/project.pbxproj" ]; then
    (cd "$APP_DIR" && "$XCODEGEN" generate)
fi
# Use the same committed dependency revisions as notarize.sh.
pins_dir="$APP_DIR/DuoUpdater.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$pins_dir"
if ! cmp -s "$APP_DIR/Package.resolved" "$pins_dir/Package.resolved"; then
    cp "$APP_DIR/Package.resolved" "$pins_dir/Package.resolved"
fi

PACKAGE_ARGS=(COMPILER_INDEX_STORE_ENABLE=NO)
if [ -n "${XCODE_CLONED_SOURCE_PACKAGES:-}" ]; then
    PACKAGE_ARGS+=(-clonedSourcePackagesDirPath "$XCODE_CLONED_SOURCE_PACKAGES")
fi

for scheme in DuoUpdater duo-cli; do
    echo "Building $scheme (Release, signing disabled)"
    xcodebuild -project "$APP_DIR/DuoUpdater.xcodeproj" \
        -scheme "$scheme" -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$DD" \
        "${PACKAGE_ARGS[@]}" \
        -onlyUsePackageVersionsFromResolvedFile \
        ARCHS=arm64 \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
        build
done

for product in "$DD/Build/Products/Release/DuoUpdater.app/Contents/MacOS/DuoUpdater" \
               "$DD/Build/Products/Release/duo-cli"; do
    if [ ! -x "$product" ]; then
        echo "::error::Release build produced no executable at $product" >&2
        exit 1
    fi
    # Project-level ARCHS does not constrain Swift package targets for a generic
    # macOS destination. The command-line setting above does; these are the two
    # shipping arm64-only products, not universal dependencies for Intel hosts.
    if [ "$(lipo -archs "$product")" != arm64 ]; then
        echo "::error::Release product is not arm64-only: $product" >&2
        exit 1
    fi
done
echo "App and CLI unsigned Release builds passed."
