"""Merge the finished runs in the work directory into results/runs.yml.

Reads $BENCH_ROOT/scores.json (run.sh score), $BENCH_ROOT/probe.txt (run.sh probe) and
each run's config.json, t0, costs.json and transcript. A run's configuration comes from
its config.json (written by record_config.py). Runs from before config.json existed
(rounds 1-5 of 2026-10-13/14) are described from their tag and the round job lists,
which is exact for them and only for them.

Records already in runs.yml whose run is not in the work directory are kept, so an
export from a machine that only has new runs adds them instead of replacing the file.
"""
import datetime, json, os, re

B = os.environ.get("BENCH_ROOT") or os.path.expanduser("~/duo-updater-bench")
H = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(H), "results", "runs.yml")
SIMPLE9 = {"rustgis", "plexo", "pulse", "search", "herdr", "reviu", "aircard", "astrlink", "yomado"}
M = {"haiku": "claude-haiku-5-5", "sonnet": "claude-sonnet-5-5", "opus": "claude-opus-5-5"}
# The 2026-10-13/14 references for the two cases that were not on main yet: graded in a
# checkout of PR #1264's branch at ff7f3690 (squash-merged as 864d00f2), not in ref/main.
LEGACY_REFS = {"astrlink": "ff7f3690ea3b5cf9c2e21f9b84f8e791944bb3b0",
               "yomado": "ff7f3690ea3b5cf9c2e21f9b84f8e791944bb3b0"}
HEADER = """\
# Every onboarding run, one record each. Written by harness/export_results.py (run.sh
# export) from harness/score.py and harness/probe.py output; see README.md.
#
#   config    what was run. From the run's config.json when it has one; the 2026-10-13/14
#             runs predate it and are described from their tag and rounds/*.txt.
#   vs_main   the graded behaviour against main's (reference_commit, graded on
#             reference_graded). MATCH, DIFF(n) with n differing fields and releases,
#             or LIVE when the case has no graded reference. An older run can show a
#             DIFF only because the vendor released since.
#   probe     the stable rule's version pattern on synthetic next tags (harness/probe.py):
#             ok, NEXT-MISS (next tag unreadable) or SUFFIX-AS-STABLE (rc/beta read as
#             stable). null: the grade recorded no stable GitHub rule (nothing onboarded,
#             another source, or the legacy grader, which records no rules).
#   grader    current (ZZBenchGrade.swift) or legacy (ZZBenchGradeLegacy.swift, for bases
#             that lack the current grader's APIs)."""


def legacy_config(tag, case):
    """The 2026-10-13/14 runs, from their tag. Exact for those runs only."""
    if tag.startswith("pipe"):
        group, rep = tag[4], int(tag.split("-")[1])
        stages = [{"stage": "plan", "model": M["opus"], "effort": "high"}] if group == "B" else []
        stages += [
            {"stage": "exec", "model": M["sonnet"], "effort": "high",
             "subagent": {"name": "executor", "model": M["haiku"], "effort": "xhigh"}},
            {"stage": "review", "model": M["opus"], "effort": "high"},
            {"stage": "fix", "model": M["sonnet"], "effort": "high", "resumes": "exec"},
        ]
        return {"mode": "pipeline-" + group, "stages": stages, "brief": "brief.md",
                "ditto_note": "on" if rep >= 2 else "off"}
    p = tag.split("-")
    effort = p[1] if len(p) > 1 and p[1] in ("low", "medium", "high", "xhigh", "max") else "high"
    return {"mode": "single", "model": M[p[0]], "effort": effort,
            "brief": "brief2.md" if tag.endswith("-b2") else "brief.md"}


def legacy_round(tag, case):
    if tag in ("haiku", "sonnet", "opus"):
        return "1"
    if tag == "haiku-max" or (tag == "haiku-xhigh" and case in SIMPLE9):
        return "2"
    if tag == "haiku-xhigh":
        return "3"
    if tag in ("haiku-xhigh-b2", "opus-xhigh", "sonnet-xhigh"):
        return "4"
    return "5"


def claude_version(d):
    for name in ("transcript.jsonl", "exec.jsonl"):
        p = os.path.join(d, name)
        if os.path.exists(p):
            m = re.search(r'"claude_code_version":"([^"]+)"', open(p).read(200000))
            if m:
                return m.group(1)
    return None


def ref_graded(case):
    p = os.path.join(B, "ref", "out", case + ".json")
    return datetime.datetime.fromtimestamp(os.path.getmtime(p)).strftime("%Y-%m-%d") if os.path.exists(p) else None


def q(v):
    return "null" if v is None else (str(v) if isinstance(v, (int, float)) else json.dumps(str(v), ensure_ascii=False))


def record(r, probe, ref_meta):
    tag, case = r["model"], r["case"]
    d = os.path.join(B, "runs", case + "-" + tag)
    cfg_path = os.path.join(d, "config.json")
    if os.path.exists(cfg_path):
        cfg = json.load(open(cfg_path))
        config = {k: cfg[k] for k in ("mode", "model", "effort", "stages", "brief", "ditto_note", "skill",
                                      "diff_base", "env", "permission_mode", "disallowed_tools") if k in cfg}
        rnd = cfg.get("round") or "unlabelled"
        date = (cfg.get("date") or "")[:10]
        cc = (cfg.get("claude_code") or "").split(" ")[0] or claude_version(d)
        grader = cfg.get("grader")
        ref_commit = cfg.get("reference_commit")
    else:
        config = legacy_config(tag, case)
        rnd = legacy_round(tag, case)
        date = datetime.datetime.fromtimestamp(int(open(d + "/t0").read())).strftime("%Y-%m-%d")
        cc = claude_version(d)
        grader = "legacy" if os.path.exists(d + "/grade-legacy.log") else "current"
        ref_commit = LEGACY_REFS.get(case) or ref_meta.get("commit")
    verdict = "LIVE" if not r["has_ref"] else ("MATCH" if not r["diffs"] else "DIFF(%d)" % len(r["diffs"]))
    lines = ["  - run: " + q(case + "-" + tag),
             "    round: " + q(rnd),
             "    date: " + q(date),
             "    case: " + q(case),
             "    config: " + json.dumps(config, ensure_ascii=False),
             "    claude_code: " + q(cc),
             "    cost_usd: %s" % r["cost"]]
    if os.path.exists(d + "/costs.json"):
        stages = {s: {"usd": v["total"], "minutes": v["minutes"], "by_model": v["by_model"]}
                  for s, v in json.load(open(d + "/costs.json")).items()}
        lines.append("    cost_by_stage: " + json.dumps(stages))
    lines += ["    minutes: %s" % r["minutes"],
              "    turns: " + q(r["turns"]),
              "    make_test_rc: " + q(r["make_test"]),
              "    grader: " + q(grader),
              "    vs_main: " + q(verdict),
              "    reference_commit: " + q(ref_commit),
              "    reference_graded: " + q(ref_graded(case)),
              "    probe: " + q(probe.get(case + "-" + tag)),
              "    head: " + q(r["head"])]
    return rnd, tag, case, "\n".join(lines)


def existing_records():
    if not os.path.exists(OUT):
        return {}
    text = open(OUT).read()
    body = text.split("\nruns:\n", 1)[1] if "\nruns:\n" in text else ""
    out = {}
    for block in re.split(r"(?m)^(?=  - run: )", body):
        m = re.match(r'  - run: "([^"]+)"', block)
        if m:
            rnd = re.search(r'(?m)^    round: (.+)$', block).group(1).strip('"')
            case = re.search(r'(?m)^    case: "(.+)"$', block).group(1)
            out[m.group(1)] = (rnd, m.group(1)[len(case) + 1:], case, block.rstrip("\n"))
    return out


rows = json.load(open(os.path.join(B, "scores.json")))
probe = {}
if os.path.exists(os.path.join(B, "probe.txt")):
    for line in open(os.path.join(B, "probe.txt")):
        m = re.match(r"^(\S+)\s+(.*?) \| tags", line)
        if m:
            probe[m.group(1)] = m.group(2)
ref_dir = os.path.join(B, "ref")
ref_meta = {}
if os.path.isdir(os.path.join(ref_dir, "main", ".git")):
    import subprocess
    ref_meta["commit"] = subprocess.run(["git", "-C", os.path.join(ref_dir, "main"), "rev-parse", "HEAD"],
                                        capture_output=True, text=True).stdout.strip() or None

records = existing_records()
kept = len(records)
for r in rows:
    rnd, tag, case, block = record(r, probe, ref_meta)
    records[case + "-" + tag] = (rnd, tag, case, block)
order = sorted(records.values(), key=lambda x: (x[0].zfill(4), x[1], x[2]))
open(OUT, "w").write(HEADER + "\nruns:\n" + "\n".join(x[3] for x in order) + "\n")
print("%d runs exported, %d records in %s (%d were already there)" % (len(rows), len(records), OUT, kept))
