#!/bin/bash
# pipe-one.sh <case> <A|B> <tag> — multi-agent onboarding pipeline, then the usual grading.
#   A: Sonnet main (+Haiku "executor" subagent) -> Opus review of the diff -> main fixes one round
#   B: Opus plan -> same as A, with the review checking the plan item by item
set -uo pipefail
. "$(dirname "$0")/env.sh"
case=$1; group=$2; tag=$3
C=$BENCH_HOME/cases/$case.json
j(){ python3 -c "import json,sys;print(json.load(open('$C'))['$1'])"; }
owner=$(j owner); repo=$(j repo); parent=$(j parent)
R=$B/runs/$case-$tag; mkdir -p $R
CLONE=$R/repo; SCR=$R/scr; mkdir -p $SCR/review
$H/mkclone.sh $CLONE $parent > $R/clone.log 2>&1 || { echo "clone failed" > $R/status; exit 1; }
subst(){ sed -e "s#__CLONE__#$CLONE#g; s#__OWNER__#$owner#g; s#__REPO__#$repo#g; s#__SCR__#$SCR#g; s#__PARENT__#$parent#g"; }
DENY=('Bash(make install:*)' 'Bash(make cli:*)' 'Bash(duo:*)' 'Bash(pkill:*)' 'Bash(killall:*)'
      'Bash(git stash:*)' 'Bash(git push:*)' 'Bash(gh pr create:*)' 'Bash(gh issue create:*)' 'Bash(open:*)'
      'Bash(sudo:*)' 'Bash(ditto:*)')
run(){ # run <stage> <model> <effort> <prompt-file> [extra args...]
  local stage=$1 model=$2 effort=$3 pf=$4; shift 4
  date +%s > $R/$stage.t0
  ( cd $CLONE && env -u CLAUDE_EFFORT -u CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 \
      claude -p --model $model --effort $effort --permission-mode auto --strict-mcp-config \
      --output-format stream-json --verbose "$@" --disallowedTools "${DENY[@]}" ${XD:-} \
      < $pf > $R/$stage.jsonl 2> $R/$stage.stderr ); echo $? > $R/$stage.rc
  date +%s > $R/$stage.t1
}
DNOTE=""; [ -n "${DITTO_NOTE:-}" ] && DNOTE=" ditto is blocked by this benchmark harness (a harness limitation, not a policy decision); unpack zips with unzip -q <zip> -d <dir under $SCR>."
cat > $R/agents.json <<JSON
{"executor": {"description": "Runs one bounded, well-specified task (downloads, package inspection with codesign/spctl/Info.plist/lipo, running make test, re-recording goldens) and reports exactly what was asked.",
  "prompt": "You carry out exactly the task you are given and report the results precisely: commands run, exit codes, raw output that matters. Follow the same forbidden-actions rules as your caller: no make install/make cli/duo CLI, nothing into /Applications, nothing launched, no quarantine changes, no system UI, no git stash or push.${DNOTE}",
  "model": "claude-haiku-5-5", "effort": "xhigh"}}
JSON
date +%s > $R/t0
# 1. plan (B only)
if [ $group = B ]; then
  subst < $H/planner.md > $R/planner.prompt
  XD="Edit NotebookEdit" run plan claude-opus-5-5 high $R/planner.prompt --no-session-persistence
fi
# 2. execute
{ subst < $H/brief.md; cat $H/exec-delegate.md; [ $group = B ] && subst < $H/exec-plan.md; [ -n "${DITTO_NOTE:-}" ] && subst < $H/ditto-note.md; } > $R/brief.md
SID=$(uuidgen | tr A-Z a-z); echo $SID > $R/exec.sid
run exec claude-sonnet-5-5 high $R/brief.md --session-id $SID --agents $R/agents.json
git -C $CLONE rev-parse HEAD > $R/exec.head
git -C $CLONE diff $parent HEAD > $R/exec.diff 2>/dev/null
# 3. review
if [ $group = B ]; then pc=$(subst < $H/reviewer-plan.md); else pc=""; fi
python3 - "$pc" <<PY > $R/reviewer.prompt
import sys; s=open("$H/reviewer.md").read(); print(s.replace("__PLANCHECK__", sys.argv[1]), end="")
PY
subst < $R/reviewer.prompt > $R/reviewer.prompt2 && mv $R/reviewer.prompt2 $R/reviewer.prompt
XD="Edit Write NotebookEdit" run review claude-opus-5-5 high $R/reviewer.prompt --no-session-persistence
python3 -c "
import json
r=[json.loads(l) for l in open('$R/review.jsonl') if l.startswith('{')]
res=[e for e in r if e.get('type')=='result']
print((res[-1].get('result') if res else '') or '(reviewer produced no result)')" > $R/review.md
# 4. fix round (resume the executor's session)
{ cat $H/fix.md; [ -n "${DITTO_NOTE:-}" ] && subst < $H/ditto-note.md; cat $R/review.md; } > $R/fix.prompt
run fix claude-sonnet-5-5 high $R/fix.prompt --resume $SID --agents $R/agents.json
date +%s > $R/t1
# merge stage transcripts for score.py: one synthetic result with summed cost/turns
python3 $H/pipe-merge.py $R
# --- grading (same as run-one.sh) ---
cd $CLONE
git log --oneline HEAD -5 > $R/gitlog.txt
git status --porcelain > $R/uncommitted.txt
git diff --stat $parent HEAD > $R/diffstat.txt 2>/dev/null
git diff $parent HEAD > $R/diff.patch 2>/dev/null
PATH=$PYSHIM:$PATH make test > $R/make-test.log 2>&1; echo $? > $R/make-test.rc
cp $H/ZZBenchGrade.swift DuoUpdaterCore/Tests/DuoUpdaterCoreTests/
( cd DuoUpdaterCore && BENCH_GRADE_CASE=$C BENCH_GRADE_OUT=$R/grade.json swift test --filter ZZBenchGrade > $R/grade.log 2>&1; echo $? > $R/grade.rc )
if [ "$(cat $R/grade.rc)" != 0 ]; then
  cp $H/ZZBenchGradeLegacy.swift DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
  ( cd DuoUpdaterCore && BENCH_GRADE_CASE=$C BENCH_GRADE_OUT=$R/grade.json swift test --filter ZZBenchGrade > $R/grade-legacy.log 2>&1; echo $? > $R/grade.rc )
fi
rm -f DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ZZBenchGrade.swift
rm -rf DuoUpdaterCore/.build CLI/.build application-test/.build
echo done > $R/status
