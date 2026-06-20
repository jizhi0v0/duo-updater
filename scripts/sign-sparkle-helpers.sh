#!/usr/bin/env bash
#
# Re-sign Sparkle's nested helper executables/bundles with our own identity.
# Sparkle ships some internal helpers ad-hoc signed; Xcode re-signs the framework
# itself, but not every nested updater/XPC helper inside it. Apple notarization
# rejects those unless we re-sign them explicitly.
#
set -euo pipefail

APP_PATH="${1:-}"
IDENTITY="${2:-}"
TIMESTAMP_MODE="${3:-none}"   # "none" or "yes"

die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ -n "$APP_PATH" ] || die "usage: sign-sparkle-helpers.sh <app-path> <codesign-identity> [none|yes]"
[ -n "$IDENTITY" ] || die "missing codesign identity"
[ -d "$APP_PATH" ] || die "app not found: $APP_PATH"

FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
[ -d "$FRAMEWORK" ] || exit 0

if [ "$TIMESTAMP_MODE" = "yes" ]; then
    timestamp_flag=(--timestamp)
else
    timestamp_flag=(--timestamp=none)
fi

sign_target() {
    local path="$1"
    [ -e "$path" ] || return 0
    codesign --force --sign "$IDENTITY" \
        "${timestamp_flag[@]}" \
        --options runtime \
        --preserve-metadata=identifier,entitlements,flags \
        --generate-entitlement-der \
        "$path"
}

sign_target "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign_target "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign_target "$FRAMEWORK/Versions/B/Updater.app"
sign_target "$FRAMEWORK/Versions/B/Autoupdate"
sign_target "$FRAMEWORK"
sign_target "$APP_PATH"
