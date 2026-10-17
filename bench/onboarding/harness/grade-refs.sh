#!/bin/bash
# grade-refs.sh [case...] — grade the reference (main, cloned at $B/ref/main) for each case,
# one at a time. Default: every case in cases/ except the extra grade cases (`"extra": true`,
# see README); name those explicitly to grade them too. Writes $B/ref/out/<case>.json.
. "$(dirname "$0")/env.sh"
mkdir -p $B/ref/out
cases=${*:-$(for f in $BENCH_HOME/cases/*.json; do python3 -c "import json,sys;d=json.load(open(sys.argv[1]));sys.exit(1 if d.get('extra') else 0)" $f && basename $f .json; done)}
for c in $cases; do
  R=$B/ref/main
  cp $H/ZZBenchGrade.swift $R/DuoUpdaterCore/Tests/DuoUpdaterCoreTests/
  ( cd $R/DuoUpdaterCore && BENCH_GRADE_CASE=$BENCH_HOME/cases/$c.json BENCH_GRADE_OUT=$B/ref/out/$c.json \
      swift test --filter ZZBenchGrade > $B/ref/out/$c.log 2>&1; echo "$(date +%H:%M:%S) ref $c rc=$?" )
  rm -f $R/DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
done
