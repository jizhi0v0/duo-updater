#!/bin/bash
# Run `make test`'s parts at once, each into its own log.
#
# Usage:  MAKE=make scripts/test-parts.sh test-scripts test-swift test-app
#
# Why at once: the parts share nothing (see the Makefile above `test:`), and run
# one after another they add up. Measured 2026-10-16 on a 14-core Mac, two rounds
# each, every part running to the end (`-k`): unchanged tree, serial 115 / 89 s
# versus parallel 52 / 48 s; one Core file edited, 119 / 146 s versus 72 / 56 s.
# No case failed in parallel that did not also fail serially.
#
# Why logs rather than the terminal: macOS ships GNU Make 3.81, which has no
# `--output-sync`, so three parts writing to one terminal interleave line by line
# and a failure is unreadable. Each part writes its own log; a part that fails
# gets its failure lines and its tail printed here, and the log path.
#
# Exit status: 0 only when every part exited 0. Every part runs to the end even
# after another fails, so one run reports every broken part.
set -u

MAKE="${MAKE:-make}"
[ $# -gt 0 ] || { echo "usage: $0 <make target>..." >&2; exit 2; }

TMPROOT="${TMPDIR:-/tmp}"
LOGDIR="$(mktemp -d "${TMPROOT%/}/duo-make-test.XXXXXX")"
now() { python3 -c 'import time; print(time.time())'; }

# Ctrl-C or a TERM from above must not leave a swift test or an xcodebuild
# running behind the shell: take the whole process group down with us.
trap 'trap - INT TERM; kill 0 2>/dev/null; exit 130' INT TERM

START="$(now)"
PIDS=()
for part in "$@"; do
  "$MAKE" "$part" > "$LOGDIR/$part.log" 2>&1 &
  PIDS+=("$!")
  printf '→ %s started (log: %s)\n' "$part" "$LOGDIR/$part.log"
done

# Report each part as it finishes, not in argument order: Bash 3.2 (macOS's
# /bin/bash) has no `wait -n`, so poll.
FAILED=()
left=$#
done_flags=()
for _ in "$@"; do done_flags+=(0); done
while [ "$left" -gt 0 ]; do
  i=0
  for part in "$@"; do
    if [ "${done_flags[$i]}" = 0 ] && ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
      wait "${PIDS[$i]}"; rc=$?
      done_flags[$i]=1; left=$((left - 1))
      secs="$(python3 -c "print(round($(now) - $START))")"
      if [ "$rc" -eq 0 ]; then
        printf '\033[1;32m✓ %s\033[0m (%ss)\n' "$part" "$secs"
      else
        printf '\033[1;31m✗ %s exited %s\033[0m (%ss)\n' "$part" "$rc" "$secs"
        FAILED+=("$part")
      fi
    fi
    i=$((i + 1))
  done
  [ "$left" -gt 0 ] && sleep 1
done

for part in ${FAILED[@]+"${FAILED[@]}"}; do
  log="$LOGDIR/$part.log"
  printf '\n\033[1;31m── %s failed ──\033[0m\n' "$part"
  # A failing Swift test or compile error can sit far above the end of the log,
  # so those are picked out: Swift Testing's `✘` and `error:`. Not `✗`: the
  # Python gates' own tests print `✗ …` lines for the failure paths they exercise
  # on purpose (16 of them in a run with one real failure, 2026-10-16). A check
  # script's real `✗` is the last thing before make's `***`, so the tail has it.
  grep -E '^✘|error:' "$log" | head -40 || true
  echo "  … last 30 lines:"
  tail -n 30 "$log"
  echo "  full log: $log"
done

total="$(python3 -c "print(round($(now) - $START))")"
if [ ${#FAILED[@]} -gt 0 ]; then
  printf '\n\033[1;31m✗ make test: %s failed\033[0m (%ss). Logs: %s\n' "${FAILED[*]}" "$total" "$LOGDIR"
  exit 1
fi
printf '\n\033[1;32m✓ make test: all %s parts passed\033[0m (%ss). Logs: %s\n' "$#" "$total" "$LOGDIR"
