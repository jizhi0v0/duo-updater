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

# Per checkout, and the dead ones reclaimed — see scripts/derived_data_path.py,
# which app-tests.sh and row-state-gallery.sh already go through. This used to be
# a fixed /tmp/duo-dd shared by every worktree open at once, which is a couple of
# dozen here: two concurrent builds collide on one derived-data directory, and
# the failure reads as a broken build rather than as contention. Two runs in the
# SAME checkout still share it — the one collision left, and not worth a lock.
# `DERIVED_DATA` overrides, and is exported so the checks this script calls can
# name the directory they want you to delete.
DD="${DERIVED_DATA:-$(python3 "$REPO/scripts/derived_data_path.py" install "$REPO")}"
export DERIVED_DATA="$DD"
PRODUCT="$DD/Build/Products/Release/DuoUpdater.app"
DEST="/Applications/DuoUpdater.app"
# The Developer ID team the build signs with, and the identity every gate in
# this script checks against. A fork must set DUO_TEAM_ID to its own team --
# see README "Building from source". Exported so App/project.yml picks it up.
TEAM="${DUO_TEAM_ID:-RS59HDH7Y3}"
export DUO_TEAM_ID="$TEAM"
BUNDLE_ID="com.duoupdater.app"

say() { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v xcodegen >/dev/null || die "xcodegen not found — brew install xcodegen"

say "Generating Xcode project from App/project.yml"
( cd "$APP_DIR" && xcodegen generate >/dev/null )

say "Building Release (Developer ID signing)"
# To a file rather than to /dev/null. xcodebuild prints compile errors on
# STDOUT, so discarding it left a failed install showing thirteen lines that say
# only "** BUILD FAILED **" — the reason existed and was thrown away, and the
# only way to see it was to reconstruct the command by hand. Per process, not
# just per checkout: a second run in this checkout would otherwise truncate the
# log the first one is about to quote from.
mkdir -p "$DD"
LOG="$DD/install-$$.log"
set +e
xcodebuild -project "$APP_DIR/DuoUpdater.xcodeproj" \
           -scheme DuoUpdater -configuration Release \
           -derivedDataPath "$DD" build > "$LOG" 2>&1
STATUS=$?
set -e
if [ $STATUS -ne 0 ]; then
  # `|| true` because `set -o pipefail` is on and a grep that matches nothing
  # exits 1 — which under errexit would abort this script before it prints the
  # log path, turning "here is what broke" back into silence.
  grep -E "error:|warning: .*(signing|provisioning)|\*\* BUILD FAILED" "$LOG" | head -40 || true
  die "build failed — full log: $LOG"
fi

[ -d "$PRODUCT" ] || die "build produced no app at $PRODUCT (log: $LOG)"

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

# Same bar as the release build. Here it matters for a different reason: an
# app that has silently lost its translations looks exactly like a bug in the
# localization you are in the middle of testing, and you will chase it there.
say "Verifying every language landed in the product"
"$REPO/scripts/verify-localizations.sh" "$PRODUCT"

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
# `-g` keeps it behind whatever the developer is actually looking at. A menu-bar
# app has nothing to show on launch, so activating it only steals focus — and a
# rebuild-install loop steals it once per build.
open -g "$DEST"

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
