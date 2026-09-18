#!/bin/bash
# Removes the throwaway preferences suites the Swift test targets create
# (`com.duoupdater.tests.<UUID>` / `com.duoupdater.harness.<UUID>`).
#
# Why this is a build step and not just cleanup inside the tests: cfprefsd keeps
# its own cached copy of every preferences domain a process touched and writes it
# back on its own schedule. Measured 2026-09-18 on macOS 27.0, that write-back
# lands after the test process has exited — one run's leftovers were seen
# appearing only during the *next* run. So an unlink from inside the test process
# cannot be the last word on the file, however carefully it is written; a sweep
# from outside can. With test-side cleanup alone, repeated runs of the two
# producing suites still left 0, 7, 14, 0 and 14 files behind.
#
# Runs at both ends of `make test`: the leading sweep is what collects the
# previous run's late write-backs, the trailing one this run's.
#
# Only exact `<prefix>.<UUID>.plist` names are removed, so nothing that isn't a
# generated scratch domain can match.
set -euo pipefail

prefs="$HOME/Library/Preferences"
[ -d "$prefs" ] || exit 0

removed=$(find "$prefs" -maxdepth 1 -type f \
    \( -name 'com.duoupdater.tests.*.plist' -o -name 'com.duoupdater.harness.*.plist' \) \
    -print -delete 2>/dev/null | wc -l | tr -d ' ')

[ "$removed" = "0" ] || echo "swept $removed scratch preference domain(s)"
