#!/usr/bin/env bash
#
# Build DuoUpdater with a STABLE Developer ID signature and deploy the single
# canonical copy to /Applications.
#
# Why this exists: macOS keys TCC grants (Full Disk Access — the gate behind the
# "DuoUpdater would like to access data from other apps" prompt — plus App
# Management, Accessibility, Automation) to the app's code identity. An ad-hoc
# signature pins the grant to the binary's CDHash, so every rebuild invalidates
# it and the prompt comes back. A Developer ID signature gives a team-based
# *designated requirement* that is identical across rebuilds, so a grant given
# once persists forever. This script builds that way and refuses to deploy an
# ad-hoc binary (see the verification gate below).
#
# Usage:  make install   (or)   scripts/install.sh
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/App"
DD="${DERIVED_DATA:-/tmp/duo-dd}"
PRODUCT="$DD/Build/Products/Release/DuoUpdater.app"
DEST="/Applications/DuoUpdater.app"
TEAM="RS59HDH7Y3"
BUNDLE_ID="com.duoupdater.app"

say() { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v xcodegen >/dev/null || die "xcodegen not found — brew install xcodegen"

say "Generating Xcode project from App/project.yml"
( cd "$APP_DIR" && xcodegen generate >/dev/null )

say "Building Release (Developer ID signing)"
xcodebuild -project "$APP_DIR/DuoUpdater.xcodeproj" \
           -scheme DuoUpdater -configuration Release \
           -derivedDataPath "$DD" build >/dev/null

[ -d "$PRODUCT" ] || die "build produced no app at $PRODUCT"

say "Re-signing Sparkle helper tools"
identity="$(codesign -dvv "$PRODUCT" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
[ -n "$identity" ] || die "could not determine signing identity from $PRODUCT"
"$REPO/scripts/sign-sparkle-helpers.sh" "$PRODUCT" "$identity" none

# --- Verification gate: refuse to ship an ad-hoc / wrong-identity binary. ---
# An ad-hoc signature is exactly the regression this whole script guards against,
# so fail loudly here rather than silently deploying something whose TCC grant
# will break on the next rebuild. Shared with scripts/build-cli.sh — see there
# for why `duo` is held to the same bar.
say "Verifying signature identity"
"$REPO/scripts/verify-signature.sh" "$PRODUCT" "$TEAM"

say "Quitting any running instance"
osascript -e 'tell application "DuoUpdater" to quit' 2>/dev/null || true
sleep 1
pkill -f "DuoUpdater.app/Contents/MacOS/DuoUpdater" 2>/dev/null && sleep 1 || true

say "Deploying single canonical copy → $DEST"
# Replace the bundle's CONTENTS in place; never delete the bundle itself.
#
# `rm -rf "$DEST"` followed by a fresh copy is what corrupted this machine's
# Background Task Management record. BTM stores the registered daemon by PATH
# ("$DEST/Contents/Library/LaunchDaemons/com.duoupdater.helper.plist"); deleting
# the bundle makes that path vanish, and BTM keeps the item while permanently
# losing its resolution — `effectiveDisposition: FATAL ERROR - fullPath is nil,
# container=(null)` on every query, `register()` refused with "Operation not
# permitted" forever after, and the Login Items switch unable to fix it. The only
# way out was `sudo sfltool resetbtm` plus a restart, which clears every app's
# background-item approvals, not just ours.
#
# Staging beside the destination and rsyncing over it keeps the bundle directory
# (and therefore the registered plist path) continuously present. Unregistering
# the daemon first would also work, but would force the user through the Login
# Items approval again on every single `make install`.
STAGE="$(dirname "$DEST")/.DuoUpdater.install.$$"
rm -rf "$STAGE"
ditto "$PRODUCT" "$STAGE"
if [ -d "$DEST" ]; then
  # -E carries extended attributes and resource forks; without them the copy can
  # land with a broken signature. Verified below either way.
  rsync -aE --delete "$STAGE/" "$DEST/"
  rm -rf "$STAGE"
else
  mv "$STAGE" "$DEST"
fi
# Strip quarantine so Gatekeeper doesn't prompt on this locally-built,
# un-notarized Developer ID app.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# The in-place replace above must not have disturbed the signature — a broken one
# would only surface later as a launch failure or a silently dropped TCC grant.
codesign --verify --deep --strict "$DEST" 2>/dev/null \
  || die "deployed bundle fails signature verification — the in-place copy damaged it"

# When we replace an existing app in place, Dock / LaunchServices can keep the
# old icon registration around briefly — especially if the previous build was
# first seen before its asset catalog or icns was in place. Touch the bundle and
# re-register it so the system notices the fresh AppIcon metadata immediately.
say "Refreshing app registration metadata"
touch "$DEST" "$DEST/Contents/Info.plist" "$DEST/Contents/Resources/AppIcon.icns" 2>/dev/null || true
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$lsregister" ]; then
  "$lsregister" -f "$DEST" >/dev/null 2>&1 || true
fi

say "Relaunching"
open "$DEST"

cat <<EOF

$(printf '\033[1;32m✓ Installed and running.\033[0m')
   identity : Developer ID Application (team $TEAM)
   location : $DEST

One-time manual step (macOS won't let a script grant this):
  • System Settings → Privacy & Security → Full Disk Access → add $DEST
  • Then quit & reopen DuoUpdater so it picks up the grant.
Because the signature is identity-based, this grant survives every future
rebuild — you won't see the "access data from other apps" prompt again.

If the prompt still appears after granting (stale ad-hoc TCC record):
  tccutil reset SystemPolicyAllFiles $BUNDLE_ID
EOF
