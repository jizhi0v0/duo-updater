#!/bin/bash
# run-fix.sh <case> <model> <effort> <tag> [neutral|guided]
#   one issue-fix run on a clone at the case's base, then grade.
# run-fix.sh <case> grade-only <base|ref> <tag>
#   no agent: grade the base (expect red) or the merged reference (expect green),
#   to check the grader and whether the vendor side still reproduces the issue.
set -uo pipefail
# Paths (B = BENCH_ROOT work dir, PYSHIM, DUO_REPO) and mkclone.sh come from the onboarding harness;
# runs land in $B/runs/<case>-<tag> beside the onboarding ones.
. "$(dirname "$0")/../../onboarding/harness/env.sh"
OH=$H; H=$(cd "$(dirname "$0")" && pwd); BENCH_HOME=$(dirname "$H")
case=$1; model=$2; effort=$3; tag=$4; mode=${5:-neutral}
C=$BENCH_HOME/cases/$case.json
j(){ python3 -c "import json;print(json.load(open('$C'))['$1'])"; }
R=$B/runs/$case-$tag; mkdir -p $R
CLONE=$R/repo; SCR=$R/scr; mkdir -p $SCR
if [ "$model" = grade-only ]; then commit=$(j $effort); else commit=$(j base); fi
$OH/mkclone.sh $CLONE $commit > $R/clone.log 2>&1 || { echo "clone failed" > $R/status; exit 1; }
base=$(j base)

if [ "$model" != grade-only ]; then
  issues=$(python3 -c "import json;print(' '.join(map(str,json.load(open('$C'))['issues'])))")
  { for n in $issues; do echo "---"; echo "GitHub issue #$n"; echo; cat $BENCH_HOME/cases/issues/$n.md; echo; done; } > $R/issues.md
  python3 - "$H/brief-fix.md" "$R/issues.md" "$R/brief.md" "$CLONE" "$SCR" <<'PY'
import sys
brief, issues, out, clone, scr = sys.argv[1:]
t = open(brief).read().replace("__ISSUES__", open(issues).read())
t = t.replace("__CLONE__", clone).replace("__SCR__", scr)
open(out, "w").write(t)
PY
  if [ "$mode" = guided ]; then { echo; echo "## Hints"; cat $H/fix-hints/$case.md; } >> $R/brief.md; fi
  echo "$mode" > $R/mode
  date +%s > $R/t0
  ( cd $CLONE && env -u CLAUDE_EFFORT claude -p --model $model --effort $effort \
      --permission-mode auto --strict-mcp-config --no-session-persistence \
      --output-format stream-json --verbose \
      --disallowedTools 'Bash(make install:*)' 'Bash(make cli:*)' 'Bash(duo:*)' 'Bash(pkill:*)' 'Bash(killall:*)' \
        'Bash(git stash:*)' 'Bash(git push:*)' 'Bash(gh:*)' 'Bash(open:*)' 'Bash(sudo:*)' \
        'Bash(swift run:*)' 'Bash(*.build/*/duo *)' \
      < $R/brief.md > $R/transcript.jsonl 2> $R/claude.stderr )
  echo $? > $R/claude.rc
  date +%s > $R/t1
fi

# --- grading: the harness's own runs; the agent's claims are not used ---
cd $CLONE
git status --porcelain > $R/uncommitted.txt
git diff $base > $R/diff.patch 2>/dev/null          # committed + uncommitted, vs base
git diff --stat $base > $R/diffstat.txt 2>/dev/null
if [ "$model" != grade-only ]; then
  PATH=$PYSHIM:$PATH make test > $R/make-test.log 2>&1; echo $? > $R/make-test.rc
fi
cp $H/ZZFixGrade.swift DuoUpdaterCore/Tests/DuoUpdaterCoreTests/
( cd DuoUpdaterCore && BENCH_FIX_CASE=$case BENCH_FIX_OUT=$R/grade.json \
    swift test --filter ZZFixGrade > $R/grade.log 2>&1; echo $? > $R/grade.rc )
rm -f DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZFixGrade.swift
rm -rf DuoUpdaterCore/.build CLI/.build application-test/.build
echo done > $R/status
