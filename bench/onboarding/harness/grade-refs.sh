#!/bin/bash
# grade-refs.sh [case...] — re-grade references sequentially: historical cases in ref/main,
# live cases (astrlink, yomado) in ref/pr. Writes ref/out/<case>.json.
. "$(dirname "$0")/env.sh"
cases=${*:-"rustgis plexo pulse search herdr reviu aircard astrlink yomado"}
for c in $cases; do
  case $c in astrlink|yomado) R=$B/ref/pr ;; *) R=$B/ref/main ;; esac
  cp $H/ZZBenchGrade.swift $R/DuoUpdaterCore/Tests/DuoUpdaterCoreTests/
  ( cd $R/DuoUpdaterCore && BENCH_GRADE_CASE=$BENCH_HOME/cases/$c.json BENCH_GRADE_OUT=$B/ref/out/$c.json \
      swift test --filter ZZBenchGrade > $B/ref/out/$c.log 2>&1; echo "$(date +%H:%M:%S) ref $c rc=$?" )
  rm -f $R/DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
done
