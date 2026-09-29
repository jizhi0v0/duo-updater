#!/usr/bin/env python3
"""Rank Homebrew casks hosted on GitHub Releases that duo-updater does not
cover yet. Run from the repository root:

    python3 .claude/skills/coverage-discovery/scripts/candidates.py --limit 40

"Covered" is decided against BOTH the code and the audit docs, three ways:
the cask's GitHub repo (after resolving renames through the API), any bundle
id the cask names in its uninstall/zap stanzas, and the app's name in the
audit index. Anything that survives is a CANDIDATE, not a gap: a bundle that
declares its own Sparkle feed is already covered with no recipe, and only
`feed-discover` on the real package can tell (SKILL.md Phase 2).

`auto_updates` is printed for information only. It is NOT evidence that the
app lacks an updater: casks leave it unset for apps that ship Sparkle.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

CASKS = "https://formulae.brew.sh/api/cask.json"
INSTALLS = "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/365d.json"
GH_ASSET = re.compile(r"https://github\.com/([^/]+)/([^/]+)/releases/download/")
BUNDLE_ID = re.compile(r"\b[a-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}\b")


def fetch(url, path):
    if not os.path.exists(path):
        req = urllib.request.Request(url, headers={"User-Agent": "duo-updater coverage-discovery"})
        with urllib.request.urlopen(req) as r, open(path, "wb") as f:
            f.write(r.read())
    with open(path) as f:
        return json.load(f)


def corpus(root):
    """Lower-cased text of every recipe/source file and every audit doc."""
    parts = []
    for base in ("DuoUpdaterCore/Sources", "docs/app-audits"):
        for d, _, files in os.walk(os.path.join(root, base)):
            for name in files:
                if name.endswith((".swift", ".md")):
                    with open(os.path.join(d, name), errors="replace") as f:
                        parts.append(f.read())
    return "\n".join(parts).lower()


def covered_repos(text):
    pairs = set(re.findall(r'owner:\s*"([^"]+)",\s*repo:\s*"([^"]+)"', text))
    pairs |= set(re.findall(r"github\.com/([\w.-]+)/([\w.-]+)", text))
    return {(o, r.removesuffix(".git")) for o, r in pairs}


def indexed_names(root):
    with open(os.path.join(root, "docs/app-audits/README.md")) as f:
        return {m.lower() for m in re.findall(r"\[\*\*(.+?)\*\*\]", f.read())}


def canonical(owner, repo):
    """owner/repo after GitHub's rename redirect, or None if gh can't say."""
    try:
        out = subprocess.run(["gh", "api", f"repos/{owner}/{repo}", "-q", ".full_name"],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    name = out.stdout.strip().lower()
    return tuple(name.split("/", 1)) if out.returncode == 0 and "/" in name else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=40)
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "duo-coverage-discovery"))
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    if not os.path.isdir(os.path.join(a.root, "docs/app-audits")):
        sys.exit("run from the repository root (or pass --root)")
    os.makedirs(a.cache, exist_ok=True)

    casks = fetch(CASKS, os.path.join(a.cache, "cask.json"))
    installs = {k: int(v[0]["count"].replace(",", ""))
                for k, v in fetch(INSTALLS, os.path.join(a.cache, "installs.json"))["formulae"].items()}
    text = corpus(a.root)
    repos = covered_repos(text)
    names = indexed_names(a.root)

    rows = []
    for c in casks:
        if c.get("deprecated") or c.get("disabled"):
            continue
        m = GH_ASSET.match(c.get("url") or "")
        if not m:
            continue
        repo = (m.group(1).lower(), m.group(2).lower())
        apps = [x["app"][0] for x in c.get("artifacts", []) if isinstance(x, dict) and "app" in x]
        if not apps or not isinstance(apps[0], str):
            continue
        app = os.path.basename(apps[0]).removesuffix(".app")
        stanzas = json.dumps([x for x in c.get("artifacts", [])
                              if isinstance(x, dict) and ("uninstall" in x or "zap" in x)])
        ids = {i.lower() for i in BUNDLE_ID.findall(stanzas) if not i.startswith("com.apple.")}
        why = ("repo" if repo in repos else
               "bundle id" if any(i in text for i in ids) else
               "audit index" if app.lower() in names else None)
        rows.append((installs.get(c["token"], 0), c["token"], repo, app, c.get("auto_updates"), why))

    rows.sort(key=lambda r: -r[0])
    shown = 0
    print(f"{'installs':>8}  {'cask':<24} {'repo':<40} {'app':<24} auto_updates")
    for n, token, repo, app, auto, why in rows:
        if shown >= a.limit:
            break
        if why:
            continue
        # A renamed repo slips past the literal match; ask GitHub for the current
        # name, but only for rows about to be shown.
        now = canonical(*repo)
        if now and now != repo and now in repos:
            continue
        label = "/".join(now or repo) + ("" if not now or now == repo else " (renamed)")
        print(f"{n:>8}  {token:<24} {label:<40} {app:<24} {auto}")
        shown += 1


if __name__ == "__main__":
    main()
