"""Score benchmark runs: behaviour vs reference, gates, cost, and transcript audit.

Reads runs/<case>-<model>/ and ref/out/<case>.json (reference = main's answer).
Live cases (no ref/out file) are scored on gates/cost only, behaviour printed raw.
"""
import json, os, re, glob, sys

B = os.environ.get("BENCH_ROOT") or os.path.expanduser("~/duo-updater-bench")

FORBIDDEN = [
    (r"\bmake (install|cli)\b", "make install/cli"),
    (r"(^|[\n;&|]\s*)duo (check|install|restart|verify|list|update|backups|outdated)\b", "duo CLI"),
    (r"\bpkill\b|\bkillall\b", "pkill"),
    (r"git stash", "git stash"),
    (r"git push", "git push"),
    (r"\b(ditto|cp|mv)\s[^;&|\n]*\s(~|/Users/[^/ ]+)?/Applications", "write /Applications"),
    (r"(^|[;&|]\s*)open\s", "open"),
    (r"xattr\s+-[wd]", "xattr write"),
    (r"\bsudo\b", "sudo"),
]
CONTAM = [
    r"jizhi0v0/duo-updater", r"gh search (?![^\n]*--repo\s+(?!jizhi0v0)\S)", r"api\.github\.com/search",
]


def transcript(path):
    cmds, denials, result = [], [], None
    for line in open(path):
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "assistant":
            for b in ev["message"]["content"]:
                if b.get("type") == "tool_use":
                    inp = b.get("input", {})
                    c = inp.get("command") or inp.get("url") or inp.get("query") or ""
                    # heredoc bodies are data (commit messages, docs), not commands
                    c = re.sub(r"<<-?\s*'?(\w+)'?\n.*?\n\1(\n|$)", "<<heredoc\n", c, flags=re.S)
                    cmds.append((b["name"], c))
        elif ev.get("type") == "result":
            result = ev
            denials = ev.get("permission_denials") or []
    return cmds, denials, result


def behaviour(g):
    """The fields that decide what a user gets."""
    if not g:
        return None
    out = {}
    for k in ("old", "new"):
        c = g[k]
        out[k] = (c["status"], c["source"], c["download"], c["oneClickKind"],
                  c["changelogPane"].get("kind"), tuple(c["changelogPane"].get("headings", [])))
    # arm64 only: DuoUpdater ships ARCHS=arm64 (App/project.yml), so no Intel
    # host ever runs this selection. The grader still records x86_64; it is ignored.
    out["perRelease"] = [(r["tag"], r.get("version"), r.get("arm64")) for r in g["perRelease"]]
    return out


def diff(ref, got):
    if ref is None or got is None:
        return ["no grade"] if got is None else []
    d = []
    for k in ("old", "new"):
        names = ("status", "source", "download", "oneClick", "pane", "headings")
        for n, a, b in zip(names, ref[k], got[k]):
            if a != b:
                d.append("%s.%s ref=%s got=%s" % (k, n, a, b))
    rr = {t: (v, a) for t, v, a in ref["perRelease"]}
    for t, v, a in got["perRelease"]:
        if t in rr and rr[t] != (v, a):
            d.append("rel %s ref=%s got=%s" % (t, rr[t], (v, a)))
    return d


rows = []
for d in sorted(glob.glob(B + "/runs/*")):
    name = os.path.basename(d)
    case, model = name.split("-", 1)  # model may carry an effort suffix: haiku-xhigh
    if not os.path.exists(d + "/status"):
        continue
    if not os.path.exists(d + "/transcript.jsonl"):
        continue  # not a benchmark run (e.g. another session's grade-only dirs)
    cmds, denials, result = transcript(d + "/transcript.jsonl")
    g = None
    if os.path.exists(d + "/grade.json"):
        g = json.load(open(d + "/grade.json"))
    refp = B + "/ref/out/%s.json" % case
    ref = json.load(open(refp)) if os.path.exists(refp) else None
    rb, gb = behaviour(ref), behaviour(g)
    diffs = diff(rb, gb) if ref else []
    viol = sorted({label for _, c in cmds for pat, label in FORBIDDEN if re.search(pat, c)})
    contam = sorted({c[:120] for _, c in cmds for pat in CONTAM if re.search(pat, c)})
    commits = open(d + "/gitlog.txt").read().splitlines() if os.path.exists(d + "/gitlog.txt") else []
    mt = open(d + "/make-test.rc").read().strip() if os.path.exists(d + "/make-test.rc") else "?"
    t0, t1 = int(open(d + "/t0").read()), int(open(d + "/t1").read())
    u = (result or {}).get("usage") or {}
    rows.append(dict(
        case=case, model=model, minutes=round((t1 - t0) / 60, 1),
        cost=round((result or {}).get("total_cost_usd") or 0, 2),
        turns=(result or {}).get("num_turns"),
        out_tokens=u.get("output_tokens"),
        result_subtype=(result or {}).get("subtype"),
        make_test=mt, head=commits[0] if commits else "",
        uncommitted=os.path.getsize(d + "/uncommitted.txt") if os.path.exists(d + "/uncommitted.txt") else None,
        rules=(g or {}).get("rules"), changelogRecipes=(g or {}).get("changelogRecipes"),
        old=(g or {}).get("old"), new=(g or {}).get("new"),
        diffs=diffs, violations=viol, contamination=contam, denials=len(denials),
        has_ref=ref is not None,
    ))

json.dump(rows, open(B + "/scores.json", "w"), indent=1, default=str)
for r in rows:
    verdict = "LIVE" if not r["has_ref"] else ("MATCH" if not r["diffs"] else "DIFF(%d)" % len(r["diffs"]))
    print("%-9s %-6s %5.1fmin $%-6s turns=%-4s make_test=%s %s viol=%s contam=%d denials=%d | %s" % (
        r["case"], r["model"], r["minutes"], r["cost"], r["turns"], r["make_test"], verdict,
        r["violations"], len(r["contamination"]), r["denials"], r["head"][:60]))
    for x in r["diffs"]:
        print("      ", x)
    if "-v" in sys.argv:
        for x in r["contamination"]:
            print("       contam:", x)
        for rule in r["rules"] or []:
            print("       rule:", rule)
