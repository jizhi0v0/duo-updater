#!/bin/bash
# grade-oldid.sh: grade the fastpotify (old Spotifast id) case in several trees, sequentially
. "$(dirname "$0")/env.sh"; O=$B/oldid; mkdir -p $O
for t in ${TREES:-ref/main}; do
  n=$(echo $t | tr '/' '_'); R=$B/$t/DuoUpdaterCore
  for g in ZZBenchGrade ZZBenchGradeLegacy; do
    cp $H/$g.swift $R/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
    ( cd $R && BENCH_GRADE_CASE=$BENCH_HOME/cases/fastpotify.json BENCH_GRADE_OUT=$O/$n.json swift test --filter ZZBenchGrade > $O/$n.log 2>&1 ); rc=$?
    rm -f $R/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
    [ $rc = 0 ] && break
  done
  [ "$t" != ref/main ] && rm -rf $R/.build
  echo "$(date +%T) $t rc=$rc"
done
