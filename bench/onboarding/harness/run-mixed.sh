#!/bin/bash
# run-mixed.sh <jobsfile>: lines "pipe <case> <A|B> <tag>" or "single <case> <model> <effort> <tag> <brief>"; PAR parallel (default 3)
. "$(dirname "$0")/env.sh"
cat "$1" | xargs -P ${PAR:-3} -L 1 bash -c '
k=$0; c=$1
if [ "$k" = pipe ]; then t=$3; echo "$(date +%T) start $c-$t"; '$H'/pipe-one.sh "$c" "$2" "$t"
else t=$4; echo "$(date +%T) start $c-$t"; BRIEF="$5" '$H'/run-one-b.sh "$c" "$2" "$3" "$t"; fi
echo "$(date +%T) end $c-$t"'
