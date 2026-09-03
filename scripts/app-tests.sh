#!/bin/bash
# Run the unit tests over App/Sources.
#
# `make test` covers the two SwiftPM packages; App/Sources is an Xcode target, so
# it needs xcodebuild. The test bundle is hostless and unsigned — it exists to
# execute plain functions, not to launch the app.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Per-checkout derived data. A fixed path would be shared by every worktree open
# at once, and this repo routinely has a dozen: two concurrent runs then collide
# the way `make test`'s /tmp/duo-loc-check already does, except here the symptom
# is tests failing rather than a build stalling, which reads as a real regression.
# `APP_TESTS_DD` overrides, as GALLERY_DD does for the gallery.
DD="${APP_TESTS_DD:-/tmp/duo-app-tests-$(printf %s "$REPO" | shasum | cut -c1-8)}"

# Exported before xcodegen for the reason install.sh and row-state-gallery.sh
# state: the spec reads $DUO_TEAM_ID for DEVELOPMENT_TEAM, and regenerating
# without it writes an EMPTY team, which breaks the next `make install` rather
# than anything here. A fork sets its own.
export DUO_TEAM_ID="${DUO_TEAM_ID:-RS59HDH7Y3}"

cd "$REPO"
# Only when the spec has actually moved. Regenerating on every `make test` would
# rewrite project.pbxproj and so invalidate the incremental build that
# check_localizable_keys.py runs a few lines later in the same target.
if [ ! -f App/DuoUpdater.xcodeproj/project.pbxproj ] \
   || [ App/project.yml -nt App/DuoUpdater.xcodeproj/project.pbxproj ]; then
  xcodegen generate --spec App/project.yml --project App >/dev/null
fi

set +e
OUT="$(xcodebuild -project App/DuoUpdater.xcodeproj \
                  -scheme DuoUpdaterAppTests -configuration Debug \
                  -derivedDataPath "$DD" \
                  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
                  test 2>&1)"
STATUS=$?
set -e
if [ $STATUS -ne 0 ]; then
  echo "$OUT" | grep -E "error:|failed|✘|Test Case .* failed" | head -40
  echo "✗ App tests failed (full log: rerun scripts/app-tests.sh)"
  exit $STATUS
fi
echo "$OUT" | grep -E "Test run with|Executed .* tests" | tail -2
echo "✓ App tests"
