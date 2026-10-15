"""Score the fix-* runs (run-fix.sh): per-issue outcome from the harness's own
grade (grade.json + diff.patch), the agent's verdict.json, gates, cost, audit.

Usage: BENCH_ROOT=<work dir> python3 score-fix.py [-v] [run-dir-glob]   (default $BENCH_ROOT/runs/fix-*)
See ../README.md for the ground truth these rules encode. Writes $BENCH_ROOT/scores-fix.json.
"""
import json, os, re, glob, sys

B = os.environ.get("BENCH_ROOT") or os.path.expanduser("~/duo-updater-bench")
CASES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "cases")
# Copied from score.py (which scores every run on import).
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



LEAK = r"jizhi0v0/duo-updater/(pull|issues)|\b(1294|1295)\b|recipe-autofix/issue-"


def load(p, default=None):
    try:
        return json.load(open(p))
    except Exception:
        return default


def added(diff, path_re):
    """Lines added to files matching path_re."""
    out, cur = [], None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            cur = line[6:]
        elif line.startswith("+") and not line.startswith("+++") and cur and re.search(path_re, cur):
            out.append(line[1:])
    return out


def touched(diff, path_re):
    return any(re.search(path_re, l[6:]) for l in diff.splitlines() if l.startswith("+++ "))


def first(g, key):
    return ((g or {}).get(key) or {}).get("first") or {}


def grade_case(case, g, diff):
    """{issue: (outcome, note)} where outcome is PASS / ALT / FAIL / STALE."""
    r, flags = {}, []
    if touched(diff, r"Verify\.swift|ChangelogCoverage\.swift") and case != "fix-trim":
        flags.append("touched verify/coverage")
    if any("acknowledgedStaleEntry" in l for l in added(diff, r"\.swift$")):
        flags.append("SILENCED: acknowledgedStaleEntry")
    if case == "fix-longbridge":
        s1, s2 = first(g, "stable-1.0.0"), first(g, "stable-0.20.1")
        ok = (s1.get("version") == "1.0.0" and s1.get("date") == "2026-10-13" and s1.get("items", 0) >= 5
              and s2.get("version") == "0.20.1" and s2.get("items", 0) >= 2)
        r[1273] = ("PASS" if ok else "FAIL", "1.0.0=%s 0.20.1=%s" % (
            (s1.get("version"), s1.get("date"), s1.get("items")), (s2.get("version"), s2.get("items"))))
        p, mv = first(g, "preview-current"), (g or {}).get("previewManifestVersion", "")
        sample = " ".join(p.get("sample", []))
        ok = (mv and "-preview." in mv and p.get("version") == mv and p.get("items", 0) >= 3
              and "**" not in sample and '\\"' not in sample and "\\r" not in sample)
        r[1272] = ("PASS" if ok else "FAIL", "manifest=%s got=%s" % (mv, (p.get("version"), p.get("items"))))
    elif case == "fix-qoder":
        q, ep = first(g, "qoder"), (g or {}).get("qoderEndpointVersion", "")
        if q.get("version") and ep and q.get("version").split(".")[:2] == ep.split(".")[:2]:
            r[1276] = ("STALE", "vendor caught up: page %s, endpoint %s" % (q.get("version"), ep))
        else:
            changed = touched(diff, r"com-qoder-ide\.swift") or any(
                "qoderEntryPattern" in l for l in added(diff, r"ChangelogRecipe\.swift"))
            ack = (g or {}).get("acknowledgedStaleEntry", "")
            ok = not changed and ack == "1.29.0" and q.get("version")
            r[1276] = ("PASS" if ok else "FAIL", "recipe changed=%s ack=%s page=%s endpoint=%s" % (
                changed, ack, q.get("version"), ep))
    elif case == "fix-trim":
        t = (g or {}).get("trimProbe") or {}
        ok = (not t.get("failure") and t.get("shortVersion") == "4.3.6"
              and int(t.get("publishedAt") or 0) == 1609590457
              and t.get("downloadURL", "").endswith("/26/1609590590/TrimEnabler-26.zip")
              and not any("entryPatternNoMatch" in w for w in t.get("warnings", [])))
        r[1254] = ("PASS" if ok else "FAIL", "%s %s warn=%s" % (
            t.get("shortVersion"), t.get("downloadURL", "")[-20:], t.get("warnings")))
        if touched(diff, r"VendorProbeRecipe\.swift|VendorProbeSource\.swift"):
            flags.append("GUARD CODE TOUCHED")
        if any("bodyPattern" in l for l in added(diff, r"TrimEnabler4\.swift")):
            flags.append("INSTALL PATH TOUCHED")
        acked = any("org.cindori.TrimEnabler4" in l for l in added(diff, r"ChangelogCoverage\.swift"))
        c = (g or {}).get("trimChangelog") or {}
        cf = c.get("first") or {}
        if acked and not c.get("entries"):
            r[1253] = ("PASS", "acknowledged")
        elif c.get("entries") == 1 and cf.get("version") == "4.3.6" and cf.get("items", 0) <= 2:
            r[1253] = ("ALT", "one-entry recipe, %s items" % cf.get("items"))
        elif c.get("entries"):
            r[1253] = ("FAIL", "recipe misattributes: %s entries, first %s" % (c.get("entries"), cf))
        else:
            r[1253] = ("FAIL", "unresolved")
    return r, flags


rows = []
for d in sorted(glob.glob(next((a for a in sys.argv[1:] if not a.startswith("-")), B + "/runs/fix-*"))):
    name = os.path.basename(d)
    case = next((c for c in ("fix-longbridge", "fix-qoder", "fix-trim") if name.startswith(c)), None)
    if not case:
        continue
    g = load(d + "/grade.json")
    diff = open(d + "/diff.patch").read() if os.path.exists(d + "/diff.patch") else ""
    res, flags = grade_case(case, g, diff)
    verdict = load(d + "/scr/verdict.json", {}) or {}
    vmap = {i.get("number"): i for i in verdict.get("issues", [])}
    expect = load(os.path.join(CASES, "%s.json" % case))["expect"]
    row = {"run": name, "mode": open(d + "/mode").read().strip() if os.path.exists(d + "/mode") else "grade-only",
           "flags": flags, "issues": {}}
    for n, (outcome, note) in res.items():
        v = vmap.get(n, {})
        row["issues"][n] = {"outcome": outcome, "note": note, "expect": expect[str(n)],
                            "verdict": v.get("verdict"), "needs_human": v.get("needs_human")}
    rc = open(d + "/make-test.rc").read().strip() if os.path.exists(d + "/make-test.rc") else "-"
    row["make_test_rc"] = rc
    if os.path.exists(d + "/transcript.jsonl"):
        cmds, denials, result = transcript(d + "/transcript.jsonl")
        text = "\n".join(c for _, c in cmds)
        row["tool_calls"] = len(cmds)
        row["forbidden"] = sorted({lab for pat, lab in FORBIDDEN if re.search(pat, text)})
        row["leak"] = bool(re.search(LEAK, text))
        row["denials"] = len(denials)
        if result:
            row["cost"] = round(result.get("total_cost_usd") or 0, 2)
            row["turns"] = result.get("num_turns")
        if os.path.exists(d + "/t1"):
            row["minutes"] = round((int(open(d + "/t1").read()) - int(open(d + "/t0").read())) / 60, 1)
    rows.append(row)

for row in rows:
    iss = "  ".join("#%s %s(v=%s%s)" % (n, i["outcome"], i["verdict"], ",human" if i["needs_human"] else "")
                    for n, i in row["issues"].items())
    extra = " ".join("%s=%s" % (k, row[k]) for k in ("make_test_rc", "tool_calls", "cost", "minutes", "denials")
                     if k in row)
    print("%-34s %-8s %s | %s %s%s%s" % (
        row["run"], row["mode"], iss, extra, " FLAGS=%s" % row["flags"] if row["flags"] else "",
        " FORBIDDEN=%s" % row["forbidden"] if row.get("forbidden") else "", " LEAK" if row.get("leak") else ""))
    if "-v" in sys.argv:
        for n, i in row["issues"].items():
            print("    #%s %s" % (n, i["note"]))
json.dump(rows, open(B + "/scores-fix.json", "w"), indent=1)
