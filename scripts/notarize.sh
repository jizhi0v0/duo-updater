#!/usr/bin/env bash
#
# Build a notarization-ready Release app, submit it with notarytool, staple the
# accepted ticket, and emit a final distributable zip.
#
# Prerequisite:
#   xcrun notarytool store-credentials <profile-name> ...
#
# Usage:
#   NOTARYTOOL_PROFILE=<profile-name> make notarize
#   # or
#   NOTARY_PROFILE=<profile-name> scripts/notarize.sh
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/App"
DD="${DERIVED_DATA:-/tmp/duo-notary-dd}"
# Exported so verify-localizations.sh can name this directory in the one message
# whose whole content is "delete the derived-data directory" — the release path
# uses a different one from `make install`, and a remedy naming the wrong
# directory is worse than one naming none.
export DERIVED_DATA="$DD"
BUILD_APP="$DD/Build/Products/Release/DuoUpdater.app"
STAGE_DIR="${DIST_DIR:-$REPO/dist/notarize}"
STAGE_APP="$STAGE_DIR/DuoUpdater.app"
SUBMIT_ZIP="$STAGE_DIR/DuoUpdater-notary-upload.zip"
FINAL_ZIP="${FINAL_ZIP:-$REPO/dist/DuoUpdater-notarized.zip}"
RESULT_JSON="$STAGE_DIR/notary-result.json"
LOG_JSON="$STAGE_DIR/notary-log.json"
# The Developer ID team the build signs with, and the identity every gate in
# this script checks against. A fork must set DUO_TEAM_ID to its own team --
# see README "Building from source". Exported so App/project.yml picks it up.
TEAM="${DUO_TEAM_ID:-RS59HDH7Y3}"
export DUO_TEAM_ID="$TEAM"
PROFILE="${NOTARYTOOL_PROFILE:-${NOTARY_PROFILE:-}}"

say() { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v xcodegen >/dev/null || die "xcodegen not found — brew install xcodegen"
command -v python3 >/dev/null || die "python3 not found"
xcrun notarytool --help >/dev/null 2>&1 || die "xcrun notarytool unavailable"
xcrun --find stapler >/dev/null 2>&1 || die "xcrun stapler unavailable"

[ -n "$PROFILE" ] || die $'NOTARYTOOL_PROFILE is required.\nStore credentials first with:\n  xcrun notarytool store-credentials <profile-name> ...'

mkdir -p "$STAGE_DIR" "$(dirname "$FINAL_ZIP")"
rm -rf "$STAGE_APP" "$SUBMIT_ZIP" "$RESULT_JSON" "$LOG_JSON" "$FINAL_ZIP"

say "Generating Xcode project from App/project.yml"
( cd "$APP_DIR" && xcodegen generate >/dev/null )

say "Building Release (Developer ID + hardened runtime)"
xcodebuild -project "$APP_DIR/DuoUpdater.xcodeproj" \
           -scheme DuoUpdater -configuration Release \
           -derivedDataPath "$DD" build >/dev/null

[ -d "$BUILD_APP" ] || die "build produced no app at $BUILD_APP"

# The compiled string catalog has to have landed, and the build will not tell
# you when it hasn't — see scripts/verify-localizations.sh. Shipping is the one
# place where missing it is unrecoverable, so it gates notarization.
say "Verifying every language landed in the product"
"$REPO/scripts/verify-localizations.sh" "$BUILD_APP"


say "Re-signing Sparkle helper tools"
identity="$(codesign -dvv "$BUILD_APP" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
[ -n "$identity" ] || die "could not determine signing identity from $BUILD_APP"
"$REPO/scripts/sign-sparkle-helpers.sh" "$BUILD_APP" "$identity" yes

say "Verifying signing prerequisites for notarization"
sig="$(codesign -dvv "$BUILD_APP" 2>&1)"
ents="$(codesign -d --entitlements :- "$BUILD_APP" 2>&1 || true)"
case "$sig" in *"adhoc"*) die "product is AD-HOC signed";; esac
case "$sig" in *"TeamIdentifier=$TEAM"*) ;; *) die "product is not signed by team $TEAM";; esac
case "$sig" in *"flags=0x10000(runtime)"*) ;; *) die "hardened runtime is not enabled";; esac
case "$ents" in *"com.apple.security.get-task-allow"*) die "get-task-allow entitlement is present";; esac
printf '   %s\n' "$(printf '%s\n' "$sig" | sed -n 's/^Authority=/Authority=/p' | head -n 1)"
printf '   %s\n' "$(printf '%s\n' "$sig" | sed -n 's/^TeamIdentifier=/TeamIdentifier=/p')"
printf '   %s\n' "$(printf '%s\n' "$sig" | sed -n 's/^CodeDirectory .* flags=/CodeDirectory flags=/p')"

say "Copying app into notarization staging"
ditto "$BUILD_APP" "$STAGE_APP"

say "Creating upload archive"
ditto -c -k --sequesterRsrc --keepParent "$STAGE_APP" "$SUBMIT_ZIP"

say "Submitting to Apple notary service"
xcrun notarytool submit "$SUBMIT_ZIP" \
    --keychain-profile "$PROFILE" \
    --wait \
    --output-format json > "$RESULT_JSON"

submission_id="$(python3 - <<'PY' "$RESULT_JSON"
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
print(data.get("id", ""))
PY
)"
status="$(python3 - <<'PY' "$RESULT_JSON"
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
print(data.get("status", ""))
PY
)"

[ -n "$submission_id" ] || die "notarytool returned no submission id"
printf '   submission id : %s\n' "$submission_id"
printf '   status        : %s\n' "$status"

if [ "$status" != "Accepted" ]; then
    say "Fetching notarization log"
    xcrun notarytool log "$submission_id" \
        --keychain-profile "$PROFILE" \
        "$LOG_JSON" >/dev/null
    die "notarization was not accepted. See $LOG_JSON"
fi

say "Stapling ticket to app bundle"
xcrun stapler staple -q "$STAGE_APP"

say "Validating stapled ticket"
xcrun stapler validate -q "$STAGE_APP"

say "Creating final distributable zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGE_APP" "$FINAL_ZIP"

cat <<EOF

$(printf '\033[1;32m✓ Notarized successfully.\033[0m')
   app        : $STAGE_APP
   zip        : $FINAL_ZIP
   submission : $submission_id
   result     : $RESULT_JSON
EOF
