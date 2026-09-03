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

# Per PROCESS, not just per checkout. Two runs in one checkout (a `make test`
# alongside a manual invocation) would otherwise truncate and append to one
# file, and the gates below read it: one run's count answering for another, or a
# false "ran nothing" because the other run truncated it mid-grep.
mkdir -p "$DD"
LOG="$DD/app-tests-$$.log"
set +e
xcodebuild -project App/DuoUpdater.xcodeproj \
           -scheme DuoUpdaterAppTests -configuration Debug \
           -derivedDataPath "$DD" \
           CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
           test > "$LOG" 2>&1
STATUS=$?
set -e

# `|| true` on every filter below, deliberately. `set -o pipefail` is on, so a
# grep that matches nothing returns 1 and — with errexit restored — would abort
# the script mid-report: on the failure path before it can print why, and on the
# SUCCESS path the moment Xcode rewords its console summary, turning a green run
# into a build failure with no message at all.
if [ $STATUS -ne 0 ]; then
  # A crash or timeout prints "** TEST EXECUTE FAILED **" and "Restarting after
  # unexpected exit"; a missing xcodebuild prints neither, nor anything else this
  # matched before. Without those patterns the failure path printed the log path
  # and nothing else.
  grep -E "error:|✘|recorded an issue|Test Case .* failed|\*\* TEST|Testing failed" \
    "$LOG" | head -40 || true
  echo "✗ App tests failed — full log: $LOG"
  exit $STATUS
fi

# A bundle that runs NO tests exits 0. Renaming App/Tests, or a sources entry
# that stops matching, would otherwise leave `make test` green forever while
# nothing at all executes — the vacuity that `make gallery`'s blank-tile gate and
# the repo's "计时测试要防空过" rule both exist to catch.
# Counted from the PER-CASE lines, not from the run summary. Measured: with a
# case marked `.disabled()`, swift-testing's summary still reads "Test run with
# 9 tests" — it counts what it knows about, not what it ran — so a summary-based
# gate passes while a case sits switched off. Only cases that actually executed
# get a "Test x() passed" line.
#
# Occurrences, NOT lines, and no `^` anchor. swift-testing runs cases in
# parallel and its writes interleave, so a case's line routinely lands appended
# to another's; anchored `grep -c` undercounted by one on a measured run (8 cases
# executed, 7 counted) and would eventually fail a green build.
RAN="$(grep -oE "Test [A-Za-z0-9_]+\(\) passed" "$LOG" | wc -l | tr -d ' ')"
# The floor is DERIVED from the sources, not written down here: a hand-kept
# number is a number that drifts, and a gate on "more than zero" would pass with
# eight of nine cases silently not running — `.disabled()`, a rename, a `sources:`
# entry that stops matching. `-lt` rather than `-ne` so a parameterized case,
# which runs more times than it is declared, does not read as a failure.
# `@Test.*func` rather than `@Test func`, so a case wearing a trait — including
# `.disabled(…)`, the exact thing this gate is here to notice — still counts as
# declared. Matching the bare form let a disabled case shrink BOTH sides at once.
DECLARED="$(grep -rhoE "@Test.*func " App/Tests | wc -l | tr -d ' ')"
if [ -z "$RAN" ]; then
  echo "✗ App tests: no executed cases found in the log."
  echo "  Either nothing ran, or swift-testing changed the per-case line this"
  echo "  gate counts (\"✔ Test x() passed\"). Log: $LOG"
  exit 1
fi
if [ "$RAN" -lt "$DECLARED" ]; then
  echo "✗ App tests ran $RAN of the $DECLARED cases declared in App/Tests."
  echo "  A case that stops running is a case that stops guarding. Log: $LOG"
  exit 1
fi
echo "✓ App tests — $RAN executed"
