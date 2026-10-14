"""record_config.py <run-dir> key=value ... — merge facts about a run into <run-dir>/config.json.

Every input that decides a run's result belongs here, so results/runs.yml is exported
from what was run rather than inferred from the run's tag. A value that starts with
{ or [ is parsed as JSON. On first write it also records the date, the Claude Code
version, this harness's commit, the reference (ref/main) commit and BENCH_ROUND.
"""
import datetime, json, os, subprocess, sys


def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout.strip() or None
    except Exception:
        return None


run_dir = sys.argv[1]
path = os.path.join(run_dir, "config.json")
cfg = json.load(open(path)) if os.path.exists(path) else {}
if not cfg:
    here = os.path.dirname(os.path.abspath(__file__))
    bench_root = os.environ.get("BENCH_ROOT") or os.path.expanduser("~/duo-updater-bench")
    cfg.update({
        "date": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "claude_code": sh("claude", "--version"),
        "harness_commit": sh("git", "-C", here, "rev-parse", "HEAD"),
        "harness_dirty": bool(sh("git", "-C", here, "status", "--porcelain", "--", ".")),
        "reference_commit": sh("git", "-C", os.path.join(bench_root, "ref", "main"), "rev-parse", "HEAD"),
        "round": os.environ.get("BENCH_ROUND") or None,
    })
for arg in sys.argv[2:]:
    k, _, v = arg.partition("=")
    cfg[k] = json.loads(v) if v[:1] in "{[" else v
json.dump(cfg, open(path, "w"), indent=1)
