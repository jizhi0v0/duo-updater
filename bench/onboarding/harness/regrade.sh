#!/bin/bash
# regrade.sh <run-name> — grade a finished run with the legacy grader (old base).
. "$(dirname "$0")/env.sh"; R=$B/runs/$1; case=${1%%-*}
cd $R/repo
cp $H/ZZBenchGradeLegacy.swift DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
( cd DuoUpdaterCore && BENCH_GRADE_CASE=$BENCH_HOME/cases/$case.json BENCH_GRADE_OUT=$R/grade.json swift test --filter ZZBenchGrade > $R/grade-legacy.log 2>&1; echo $? > $R/grade.rc )
rm -f DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
rm -rf DuoUpdaterCore/.build
echo "$1 grade_rc=$(cat $R/grade.rc)"
