#!/bin/bash
# replay-review.sh <case> [src-tag] [effort] — replay the production Claude review (main's REVIEW.md +
# .github/claude-review/full.md, Opus 5.5, same tool allowlist; effort as the workflow sets it, xhigh since #1301) on a finished run's commits.
set -uo pipefail
. "$(dirname "$0")/env.sh"
MAIN=$DUO_REPO
c=$1; tag=${2:-opus-medium}; effort=${3:-xhigh}
SRC=$B/runs/$c-$tag/repo; D=$B/replay/$c-$tag-$effort; R=$D/repo; W=$R/.claude-review
parent=$(python3 -c "import json;print(json.load(open('$BENCH_HOME/cases/$c.json'))['parent'])")
# A SKILL=1 run starts at the harness's own commit (diff_base), not at the case's parent:
# reviewing from parent would count the injected checklist as the agent's work.
parent=$(python3 -c "import json,os;p='$B/runs/$c-$tag/config.json';print((json.load(open(p)).get('diff_base') if os.path.exists(p) else None) or '$parent')")
head=$(git -C $SRC rev-parse HEAD)
rm -rf $D; mkdir -p $D
git clone -q $SRC $R && git -C $R checkout -q --detach $head || { echo "clone failed" > $D/status; exit 1; }
# Production files from main, working tree only (not committed, so not in the reviewed diff)
git -C $MAIN show origin/main:REVIEW.md > $R/REVIEW.md
mkdir -p $R/.github/claude-review $W
for f in full.md gh-get; do git -C $MAIN show origin/main:.github/claude-review/$f > $R/.github/claude-review/$f; done
chmod +x $R/.github/claude-review/gh-get
git -C $R log -1 --format='# %s%n%n%b' $head > $W/pr.md
python3 - "$R/.github/claude-review/full.md" "$W/prompt.md" <<PY
import sys
t=open(sys.argv[1]).read()
for k,v in {"@PR@":"1","@HEAD_SHA@":"$head","@MERGE_BASE@":"$parent","@OUT@":"$W/review.md",
            "@PRINFO@":"$W/pr.md","@GHGET@":"$R/.github/claude-review/gh-get"}.items():
    t=t.replace(k,v)
open(sys.argv[2],"w").write(t)
PY
python3 $H/record_config.py $D mode=replay case=$c source_run=$c-$tag model=claude-opus-5-5 effort=$effort \
  review_md_commit=$(git -C $MAIN rev-parse origin/main) head=$head parent=$parent permission_mode=default \
  setting_sources=project 'allowed_tools=["Edit(//<repo>/.claude-review/review.md)","Bash(<repo>/.github/claude-review/gh-get *)"]'
date +%s > $D/t0
( cd $R && env -u CLAUDE_EFFORT -u CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 \
    claude -p --model claude-opus-5-5 --effort $effort --setting-sources project --permission-mode default \
    --strict-mcp-config --output-format stream-json --verbose \
    --allowedTools "Edit(/$R/.claude-review/review.md)" "Bash($R/.github/claude-review/gh-get *)" \
    < $W/prompt.md > $D/transcript.jsonl 2> $D/stderr ); echo $? > $D/rc
date +%s > $D/t1
cp $W/review.md $D/review.md 2>/dev/null || echo "(no review.md)" > $D/review.md
python3 -c "
import json
for l in open('$D/transcript.jsonl'):
    try: e=json.loads(l)
    except: continue
    if e.get('type')=='result': print('cost',round(e['total_cost_usd'],2),'turns',e['num_turns'],'min',e['duration_ms']//60000,'denials',len(e.get('permission_denials') or []))
" > $D/summary.txt
echo done > $D/status
