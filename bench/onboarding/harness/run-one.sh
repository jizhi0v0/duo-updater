#!/bin/bash
# run-one.sh <case> <model> <effort> <tag>  — one onboarding run, then grade.
set -uo pipefail
. "$(dirname "$0")/env.sh"
case=$1; model=$2; effort=$3; tag=$4
C=$BENCH_HOME/cases/$case.json
j(){ python3 -c "import json,sys;print(json.load(open('$C'))['$1'])"; }
owner=$(j owner); repo=$(j repo); parent=$(j parent)
R=$B/runs/$case-$tag; mkdir -p $R
CLONE=$R/repo; SCR=$R/scr; mkdir -p $SCR
$H/mkclone.sh $CLONE $parent > $R/clone.log 2>&1 || { echo "clone failed" > $R/status; exit 1; }
sed -e "s#__CLONE__#$CLONE#g; s#__OWNER__#$owner#g; s#__REPO__#$repo#g; s#__SCR__#$SCR#g" $H/brief.md > $R/brief.md
date +%s > $R/t0
( cd $CLONE && env -u CLAUDE_EFFORT claude -p --model $model --effort $effort \
    --permission-mode auto --strict-mcp-config --no-session-persistence \
    --output-format stream-json --verbose \
    --disallowedTools 'Bash(make install:*)' 'Bash(make cli:*)' 'Bash(duo:*)' 'Bash(pkill:*)' 'Bash(killall:*)' \
      'Bash(git stash:*)' 'Bash(git push:*)' 'Bash(gh pr create:*)' 'Bash(gh issue create:*)' 'Bash(open:*)' \
      'Bash(sudo:*)' 'Bash(ditto:*)' \
    < $R/brief.md > $R/transcript.jsonl 2> $R/claude.stderr )
echo $? > $R/claude.rc
date +%s > $R/t1
# --- grading (the harness's own runs; the agent's claims are not used) ---
cd $CLONE
git log --oneline HEAD -3 > $R/gitlog.txt   # HEAD: an agent may commit on its own branch
git status --porcelain > $R/uncommitted.txt
git diff --stat $parent HEAD > $R/diffstat.txt 2>/dev/null
git diff $parent HEAD > $R/diff.patch 2>/dev/null
PATH=$PYSHIM:$PATH make test > $R/make-test.log 2>&1; echo $? > $R/make-test.rc
cp $H/ZZBenchGrade.swift DuoUpdaterCore/Tests/DuoUpdaterCoreTests/
( cd DuoUpdaterCore && BENCH_GRADE_CASE=$C BENCH_GRADE_OUT=$R/grade.json swift test --filter ZZBenchGrade > $R/grade.log 2>&1; echo $? > $R/grade.rc )
if [ "$(cat $R/grade.rc)" != 0 ]; then  # base predates APIs the grader uses
  cp $H/ZZBenchGradeLegacy.swift DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
  ( cd DuoUpdaterCore && BENCH_GRADE_CASE=$C BENCH_GRADE_OUT=$R/grade.json swift test --filter ZZBenchGrade > $R/grade-legacy.log 2>&1; echo $? > $R/grade.rc )
fi
rm -f DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
# reclaim disk: build products only; keep the repo, diff and logs
rm -rf DuoUpdaterCore/.build CLI/.build application-test/.build
echo done > $R/status
