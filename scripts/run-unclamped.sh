#!/usr/bin/env bash
#
# Run a command as a launchd job with ProcessType Interactive, in this user's
# GUI domain, and pass its output and exit status through. For GitHub-hosted
# macOS runners, where everything a step starts is clamped to utility QoS.
#
# What the clamp does to Core's suite, measured on hosted xcode-27 (macOS 27.0.1,
# 3 cores), diag runs 39191854468, 39193168380, 39194150567 and 39195326565,
# 2026-10-19:
#
#   * `sudo taskinfo` on the step's shell, Runner.Worker, Runner.Listener and
#     hosted-compute-agent, and on swiftpm-testing-helper and every child sampled:
#     `req qos clamp: THREAD_QOS_UTILITY`, effective iotier THROTTLE_LEVEL_TIER1,
#     latency QoS tier 3, throughput tier 2. The runner's own launchd job sets it
#     and every process below inherits it.
#   * With it, the children that do disk I/O sit in the kernel for minutes:
#     `spindump` of a stuck `ditto`, `aa`, `diskutil` or brew's `ruby` (9 of 9
#     readable dumps) showed `read` → `throttle_lowpri_io`, base priority 20, ~0
#     CPU, while the CPU was mostly idle. That is the 120–165 s tail: 137–148
#     tests over 60 s per run, p99 123–166 s, the suite 144–308 s.
#   * Run as an Interactive job: clamp THREAD_QOS_UNSPECIFIED, iotier TIER0, the
#     suite 50 and 78 s, 0 and 14 tests over 60 s, p99 28 and 47 s. A Standard
#     job kept the clamp and the tail (308 and 223 s), as launchd.plist(5) says
#     an unset ProcessType does ("light resource limits ... throttling its CPU
#     usage and I/O bandwidth").
#   * `taskpolicy -d important` around `swift test` changed nothing (223 and
#     147 s): setiopolicy_np(3) takes "the lowest priority policy of the current
#     thread and the current process", and the clamp keeps the threads at utility.
#
# The job gets this step's environment and working directory. Cancelling the
# step boots the job out, which takes its process group with it.
#
# Usage: scripts/run-unclamped.sh <command> [args...]
set -uo pipefail

[ $# -gt 0 ] || { echo "usage: run-unclamped.sh <command> [args...]" >&2; exit 2; }

dir="$(mktemp -d -t duo-unclamped)"
label="duo.ci.unclamped.$$"
domain="gui/$(id -u)"

# The step's environment, re-exported in the job: launchd starts it with almost
# none of its own.
export -p > "$dir/env"
{
    echo '#!/bin/bash'
    echo "source $(printf '%q' "$dir/env")"
    echo "cd $(printf '%q' "$PWD") || exit 97"
    echo "$(printf '%q ' "$@") > $(printf '%q' "$dir/out") 2>&1 < /dev/null"
    echo "echo \$? > $(printf '%q' "$dir/rc.tmp") && mv $(printf '%q' "$dir/rc.tmp") $(printf '%q' "$dir/rc")"
} > "$dir/run.sh"
chmod +x "$dir/run.sh"
: > "$dir/out"

/usr/bin/python3 - "$dir" "$label" <<'PY'
import plistlib, sys
d, label = sys.argv[1:]
with open(f"{d}/job.plist", "wb") as f:
    plistlib.dump({"Label": label, "ProgramArguments": [f"{d}/run.sh"],
                   "ProcessType": "Interactive", "RunAtLoad": True}, f)
PY

tailer=""
cleanup() {
    launchctl bootout "$domain/$label" 2>/dev/null
    [ -n "$tailer" ] && kill "$tailer" 2>/dev/null
    rm -rf "$dir"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

launchctl bootstrap "$domain" "$dir/job.plist" || { echo "run-unclamped: launchctl bootstrap $domain failed" >&2; exit 125; }

tail -n +1 -f "$dir/out" &
tailer=$!

# Done when the job has written its status. If launchd no longer has a running
# process for the job and there is still no status, the job died without
# finishing its script (killed, or never started): fail rather than wait forever.
gone=0
while [ ! -e "$dir/rc" ]; do
    sleep 2
    if launchctl print "$domain/$label" 2>/dev/null | grep -q 'state = running'; then
        gone=0
    else
        gone=$((gone + 1))
        if [ "$gone" -ge 5 ] && [ ! -e "$dir/rc" ]; then
            echo "run-unclamped: the job stopped without an exit status" >&2
            launchctl print "$domain/$label" 2>&1 | grep -E 'state|last exit' >&2
            exit 125
        fi
    fi
done

# Let tail print the last of the output before it goes.
sleep 1
exit "$(cat "$dir/rc")"
