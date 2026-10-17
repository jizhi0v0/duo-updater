#!/bin/bash
# run.sh — one entry point for the onboarding benchmark. See README.md.
#
#   run.sh single <model> <effort> <case|group>...   one agent per case     (TAG, BRIEF, SKILL optional)
#   run.sh pipe <A|B> <repetition> <case|group>...    the multi-agent pipelines
#   run.sh replay <run-tag> <effort> <case|group>...  replay the production Claude review on runs
#   run.sh score                                      score every finished run against main
#   run.sh probe                                      run each stable rule on synthetic next tags
#   run.sh export                                     write results/runs.yml from scores and probe
#
# Pipelines get harness/ditto-note.md unless DITTO_NOTE= (empty) is set, which reproduces
# round 5 repetition 1. BENCH_ROUND labels the runs in their config.json.
# Groups: hard7 (the seven apps Haiku onboarded short of main), simple9 (rounds 1-2),
# history21 (round 3), holdout6 (round 6: past onboardings no prompt was written from),
# trap7 (2026-10-17: apps whose answer hangs on one trap; see README "Trap set").
# SKILL=1 adds harness/skill/coverage-checklist.md to app-audit; give those runs their own TAG.
# PAR sets how many run at once (default 3; GitHub's per-token limits made 5 too many).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); H=$here/harness
case ${1:-} in single|pipe|replay|score|probe|export) . "$H/env.sh" ;; *) sed -n '2,17p' "$0"; exit 64 ;; esac

expand() {
  for c in "$@"; do
    case $c in
      hard7) echo secretive obelisk openinterminal lokii disktree spotifast cindy ;;
      simple9) echo rustgis plexo pulse search herdr reviu aircard astrlink yomado ;;
      history21) awk '{print $2}' "$here/rounds/round3-haiku-xhigh-history.txt" ;;
      holdout6) echo swiftvm pdfcraft tinycast cuadriver whatcable t3code ;;
      trap7) echo loop cork switchhosts picard zettlr krita snipaste ;;
      *) echo "$c" ;;
    esac
  done
}

cmd=${1:-}; shift || true
case $cmd in
  single)
    model=$1 effort=$2; shift 2
    tag=${TAG:-${model#claude-}-$effort}; tag=${tag//-5-5/}
    jobs=$B/jobs-$tag.txt; : > "$jobs"
    for c in $(expand "$@"); do echo "single $c $model $effort $tag ${BRIEF:-brief.md}" >> "$jobs"; done
    "$H/run-mixed.sh" "$jobs" ;;
  pipe)
    group=$1 rep=$2; shift 2
    jobs=$B/jobs-pipe$group-$rep.txt; : > "$jobs"
    for c in $(expand "$@"); do echo "pipe $c $group pipe$group-$rep" >> "$jobs"; done
    DITTO_NOTE=${DITTO_NOTE-1} "$H/run-mixed.sh" "$jobs" ;;
  replay)
    tag=$1 effort=$2; shift 2
    for c in $(expand "$@"); do echo "$c"; done |
      xargs -P "${PAR:-2}" -I{} "$H/replay-review.sh" {} "$tag" "$effort" ;;
  score) BENCH_ROOT=$B python3 "$H/score.py" -v ;;
  probe) BENCH_ROOT=$B python3 "$H/probe.py" | tee "$B/probe.txt" ;;
  export) BENCH_ROOT=$B python3 "$H/export_results.py" ;;
  *) sed -n '2,17p' "$0"; exit 64 ;;
esac
