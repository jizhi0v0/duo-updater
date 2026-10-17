#!/bin/bash
# grade-oldid.sh: grade one extra grade case (CASE, default fastpotify: the old Spotifast id) in
# several trees, sequentially. Other cases write $B/oldid/<case>-<tree>.json.
. "$(dirname "$0")/env.sh"; O=$B/oldid; mkdir -p $O
case=${CASE:-fastpotify}; pre=; [ $case = fastpotify ] || pre=$case-
for t in ${TREES:-ref/main}; do
  n=$(echo $t | tr '/' '_'); R=$B/$t/DuoUpdaterCore
  for g in ZZBenchGrade ZZBenchGradeLegacy; do
    cp $H/$g.swift $R/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
    ( cd $R && BENCH_GRADE_CASE=$BENCH_HOME/cases/$case.json BENCH_GRADE_OUT=$O/$pre$n.json swift test --filter ZZBenchGrade > $O/$pre$n.log 2>&1 ); rc=$?
    rm -f $R/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
    [ $rc = 0 ] && break
  done
  [ "$t" != ref/main ] && rm -rf $R/.build
  echo "$(date +%T) $t rc=$rc"
done
