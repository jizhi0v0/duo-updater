#!/usr/bin/env bash
#
# Run a command under a wall-clock budget. If it overruns, capture a `sample(1)`
# of whatever it is stuck in, print that, then kill the process tree and fail.
#
# Why this is a shell wrapper and not a watchdog inside the test process:
#
#   * An in-process watchdog has to be ARMED by code that runs. The first version
#     of this armed itself inside `vendorDownloadPassesSignatureGate`, so when a
#     run wedged with that gate switched off (CI run 33955586375) the watchdog did
#     not exist and 60 minutes produced nothing. Out here there is nothing to arm.
#   * `make test` is more than the Swift suite — it also runs xcodebuild for the
#     app target and two Python gates. A watchdog living in one test bundle cannot
#     see a wedge in any of the others.
#   * An async timeout inside the process is worse still: it is a Task on the very
#     cooperative pool it would be reporting on, so a runtime that has stopped
#     scheduling never fires it. Measured — a five-minute `firstToFinish` bound sat
#     through a sixteen-minute silence without firing.
#
# macOS has no `timeout(1)`, hence the poll loop rather than coreutils.
#
# Usage: scripts/run-with-hang-report.sh <budget-seconds> <command> [args...]
set -uo pipefail

budget="${1:?usage: run-with-hang-report.sh <seconds> <command> [args...]}"
shift

"$@" &
child=$!

# Processes worth sampling, most specific first. A wedge in the Swift suite shows
# up as swiftpm-testing-helper; the app target's is xctest under xcodebuild.
sample_targets='swiftpm-testing-helper|xctest|swift-test|xcodebuild'

waited=0
while kill -0 "$child" 2>/dev/null; do
    if [ "$waited" -ge "$budget" ]; then
        echo "=== HANG: '$*' exceeded ${budget}s ==============================" >&2
        # Sample every candidate, not just one: which of them is wedged is the
        # question, and a report naming the wrong process answers nothing.
        report="$(mktemp -t duo-hang-sample)"
        for pid in $(pgrep -f "$sample_targets" 2>/dev/null); do
            [ "$pid" = "$$" ] && continue
            comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
            # Match the process NAME, not the command line. `pgrep -f` also hits
            # this script's own poll shell and any editor or grep that happens to
            # have one of these words in its arguments — sampling those produces a
            # confident-looking report about nothing.
            case "${comm##*/}" in
                swiftpm-testing-helper|xctest|swift-test|xcodebuild|swift-frontend) ;;
                *) continue ;;
            esac
            echo "--- sample of pid $pid ($comm) ---" >&2
            # To a real file, then cat it. `-file /dev/stdout` under these
            # redirections silently produced ZERO stacks while still printing the
            # headers above — a report that looks like evidence and contains none.
            if /usr/bin/sample "$pid" 5 -file "$report" >/dev/null 2>&1; then
                cat "$report" >&2
            else
                echo "    (sample failed for $pid)" >&2
            fi
        done
        rm -f "$report"
        echo "=== killing the tree =========================================" >&2
        # The whole tree. Killing only the top leaves orphans holding the SwiftPM
        # lock, which turns the next run into a different and more confusing hang.
        pkill -P "$child" 2>/dev/null
        kill -9 "$child" 2>/dev/null
        pkill -9 -f "$sample_targets" 2>/dev/null
        wait "$child" 2>/dev/null
        exit 124
    fi
    sleep 5
    waited=$((waited + 5))
done

wait "$child"
exit $?
