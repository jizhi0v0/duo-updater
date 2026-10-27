#!/usr/bin/env python3
"""Refuse a pull request that changes high-risk code without an adversarial review on record.

Run by `.github/workflows/adversarial-review.yml` on every pull request event,
including an edit to the description. Also runs by hand against any PR:

    python3 scripts/check_adversarial_review.py --pr 1722

## What this is for

The review bot (`claude-review.yml`) reads the diff with no network and no Mac
to run anything on. It finds logic slips; it did not find the security holes
fixed in #1659–#1683 (tokens handed to tool children, root running a file the
user could change, unpinned `curl | sh`), and it found the D15 stop's races
only one per round, two of them made by the previous round's fix (#1722). Those
need a review aimed at one risk, by someone who can read vendor source and run
a probe: a local adversarial review. This check makes sure one was done, and
that no high-risk change landed after it.

## The rule

A change is high-risk when, in the Swift that ships (`COVERED`, as the
real-machine check), it touches a file in `RISK_FILES`, or adds a line matching
one of `RISK_LINES`. Each match names a risk: process-control, data-loss,
privilege, trust, secrets, untrusted-input. A diff GitHub does not show (too
large) counts as high-risk under `unread-diff`. Branches in `EXEMPT_BRANCHES`
pass, as in the real-machine check.

A high-risk PR's description must have one of:

  (a) a section whose heading says `Adversarial review` (or 对抗审查), with a
      date (YYYY-MM-DD) and the commit it reviewed (7–40 hex digits) in the
      heading or body, at least one result line (list item, table row or code
      block line), and each risk the PR raises named in it;

  (b) a line, for a match that is not a risk (a pattern hit in a comment, a
      renamed constant):

          Adversarial review: not needed (<sha>) — <reason>

Either way the commit named must be in the PR's history, and nothing after it
may be high-risk: a fix pushed after the review needs a review of its own
(#1722's rounds 4 and 5 were bugs made by fixes).

## What it cannot see

Whether the review was any good, or the opt-out's reason true; REVIEW.md asks
the review bot to judge both. The patterns are a net, not a proof: a risky
change that matches none passes, and a harmless one that matches some needs
the opt-out line.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys

# As check_real_machine_record.py: what ships.
COVERED = (
    "DuoUpdaterCore/Sources/",
    "App/Sources/",
    "App/Helper/",
    "App/Shared/",
    "CLI/Sources/",
)

EXEMPT_BRANCHES = (
    "release/",
    "appcast/",
    "verify/baseline-",
    "verify/install-",
    "recipe-autofix/",
    "bench/",
)

# Files any change to is high-risk, by what they decide.
RISK_FILES = (
    ("App/Helper/", "privilege"),
    ("App/Shared/", "privilege"),
    ("App/Sources/PrivilegedHelperClient.swift", "privilege"),
    ("App/Sources/HelperInstallGate.swift", "privilege"),
    ("App/Sources/HelperStagedVersionReader.swift", "privilege"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/Install/BrewAskPass.swift", "privilege"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/CLIToolAdministratorRun.swift", "privilege"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/Install/InPlaceSwap.swift", "data-loss"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/Install/BackupStore.swift", "data-loss"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/Managed/ManagedSnapshot.swift", "data-loss"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/Managed/ManagedStop.swift", "process-control"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/Support/ChildProcess.swift", "process-control"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/Install/SignatureVerifier.swift", "trust"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/CLIToolTrust.swift", "trust"),
    ("DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/GitHubTokenStorage.swift", "secrets"),
)

# Added lines that bring a risk into any shipped file.
RISK_LINES = (
    ("process-control", re.compile(
        r"\bkillpg\(|\bkill\(|\bSIG(?:INT|TERM|KILL|STOP|CONT)\b|\bsetsid\b|"
        r"\bwaitpid\(|\bposix_spawn|\bcreateSession\b|\bprocessGroupID\b")),
    ("data-loss", re.compile(
        r"\.removeItem\(|\.replaceItemAt\(|\.replaceItem\(|\.moveItem\(|\brenamex_np\b|"
        r"\brename\(|\bunlink\(|\brm -[a-zA-Z]*[rf]|\bfunc interruption\(|NewEntries\(")),
    ("privilege", re.compile(
        r"\bsudo\b|with administrator privileges|\bAuthorization(?:Create|Execute|Copy)|"
        r"\bSMAppService\b|\bsetuid\(|\bchown\b|\bchmod\b|\bneedsAdministrator\b|\basRoot\b")),
    ("trust", re.compile(
        r"\bSecStaticCode|\bSecCode|\bSecRequirement|\bcodesign\b|\bteamIdentifier\b|"
        r"\bcdhash\b|\bspctl\b|\bquarantine\b|\bEdDSA\b|\bsha256\b|\bvendorSigned\b")),
    ("secrets", re.compile(
        r"GITHUB_TOKEN|GH_TOKEN|HOMEBREW_GITHUB_API_TOKEN|\bSecItem|\bkSecClass|"
        r"Authorization:|\bpassword\b|\bapiKey\b", re.IGNORECASE)),
    ("untrusted-input", re.compile(
        r"\|\s*(?:ba|z)?sh\b|curl[^\n]*\|\s|\bNSTemporaryDirectory\(|\"/tmp/|"
        r"\bloadHTMLString\b|\bevaluateJavaScript\b|\bNSAppleScript\b|\bosascript\b")),
)

HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
RECORD_HEADING = re.compile(r"adversarial review|对抗(?:式)?审查", re.IGNORECASE)
DATE = re.compile(r"\b(20\d\d)-(\d\d)-(\d\d)\b")
SHA = re.compile(r"\b[0-9a-f]{7,40}\b")
RESULT_LINE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\S|^\s*\|")
TABLE_RULE = re.compile(r"^\s*\|[\s:|-]*\|?\s*$")
FENCE = re.compile(r"^\s*(```|~~~)")
OPT_OUT = re.compile(
    r"^[\s>*_+-]*adversarial review\W*not needed\s*\(\s*`?([0-9a-f]{7,40})`?\s*\)\W*?[—–:-]+(.*)$",
    re.IGNORECASE,
)


def _risky(path):
    return path.startswith(COVERED)


def risks(files):
    """{risk: [reason, …]} for `files`: [(path, patch or None)]."""
    found = {}
    for path, patch in files:
        if not _risky(path):
            continue
        for prefix, risk in RISK_FILES:
            if path.startswith(prefix):
                found.setdefault(risk, []).append(path)
        if patch is None:
            found.setdefault("unread-diff", []).append(path)
            continue
        for line in patch.splitlines():
            if not line.startswith("+") or line.startswith("+++"):
                continue
            for risk, pattern in RISK_LINES:
                m = pattern.search(line)
                if m:
                    found.setdefault(risk, []).append("%s: %s" % (path, m.group(0)))
    return found


def _lines_outside_fences(body):
    out = []
    fence = None
    for line in body.splitlines():
        m = FENCE.match(line)
        if m:
            if fence is None:
                fence = m.group(1)
                out.append((line, True))
                continue
            if m.group(1) == fence:
                fence = None
                out.append((line, True))
                continue
        out.append((line, fence is not None))
    return out


def _has_date(text):
    for m in DATE.finditer(text):
        try:
            datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            return True
        except ValueError:
            pass
    return False


def opt_out(body):
    """(sha, reason) of the opt-out line, or None."""
    for line, in_fence in _lines_outside_fences(body):
        if in_fence:
            continue
        m = OPT_OUT.match(line)
        if m and re.search(r"\w", m.group(2).strip(" *_")):
            return m.group(1), m.group(2).strip(" *_")
    return None


def record_sections(body):
    """Each adversarial-review heading: (title, dated, shas, result_lines, text)."""
    lines = _lines_outside_fences(body)
    sections = []
    for i, (line, in_fence) in enumerate(lines):
        m = None if in_fence else HEADING.match(line)
        if not m or not RECORD_HEADING.search(m.group(2)):
            continue
        level, title = len(m.group(1)), m.group(2)
        text = [title]
        results = 0
        for body_line, fenced in lines[i + 1:]:
            if not fenced:
                h = HEADING.match(body_line)
                if h and len(h.group(1)) <= level:
                    break
            if FENCE.match(body_line):
                continue
            text.append(body_line)
            if fenced and body_line.strip():
                results += 1
            elif not fenced and RESULT_LINE.match(body_line) and not TABLE_RULE.match(body_line):
                results += 1
        joined = "\n".join(text)
        sections.append((title, _has_date(joined), SHA.findall(joined), results, joined))
    return sections


def _show(found):
    out = []
    for risk in sorted(found):
        hits = found[risk]
        out.append("  %s: %s%s" % (risk, "; ".join(hits[:3]), " …" if len(hits) > 3 else ""))
    return out


def evaluate(body, head_ref, files, compare):
    """(passed, message). `files`: the PR's [(path, patch)]. `compare(sha)`:
    None when `sha` is not in the PR's history, else the [(path, patch)] from
    it to the head."""
    for prefix in EXEMPT_BRANCHES:
        if head_ref.startswith(prefix):
            return True, "exempt: branch %s starts with %s" % (head_ref, prefix)
    found = risks(files)
    if not found:
        return True, "exempt: no high-risk change"
    head = ["High-risk changes in this PR:"] + _show(found)
    body = body or ""

    def after(sha):
        later = compare(sha)
        if later is None:
            return None, ["%s is not in this PR's history (rebased or a typo?)" % sha]
        late = risks(later)
        if late:
            return False, ["high-risk changes after %s, not reviewed:" % sha] + _show(late)
        return True, []

    problems = []
    skipped = opt_out(body)
    if skipped:
        sha, reason = skipped
        ok, why = after(sha)
        if ok:
            return True, "opt-out at %s: %s" % (sha, reason)
        problems += why
    for title, dated, shas, results, text in record_sections(body):
        missing = []
        if not dated:
            missing.append("a date (YYYY-MM-DD)")
        if not shas:
            missing.append("the commit it reviewed")
        if not results:
            missing.append("a result line")
        unnamed = [r for r in sorted(found) if r != "unread-diff" and r not in text.lower()]
        if unnamed:
            missing.append("the risk(s) %s named" % ", ".join(unnamed))
        if missing:
            problems.append("\"%s\" has no %s" % (title, ", no ".join(missing)))
            continue
        why = None
        for sha in shas:
            ok, why = after(sha)
            if ok:
                return True, "record: \"%s\" at %s" % (title, sha)
        problems += why
    msg = head + ["but the description has no adversarial review that covers them."]
    if problems:
        msg += ["Found:"] + ["  " + p for p in problems]
    msg += [
        "Add, after a local adversarial review of each risk named above:",
        "  ## Adversarial review (YYYY-MM-DD, <reviewed sha>)",
        "  - <risk>: <what was attacked, how, what was found>",
        "or, when a match is not a risk:",
        "  Adversarial review: not needed (<sha>) — <reason>",
    ]
    return False, "\n".join(msg)


def _gh(args):
    return subprocess.run(["gh"] + args, check=True, capture_output=True, text=True).stdout


def _pairs(entries):
    return [(f["filename"], f.get("patch")) for f in entries]


def fetch(repo, pr):
    data = json.loads(_gh(["api", "repos/%s/pulls/%s" % (repo, pr)]))
    pages = json.loads("[" + _gh([
        "api", "--paginate", "repos/%s/pulls/%s/files" % (repo, pr), "--jq", ".[] | tojson",
    ]).strip().replace("\n", ",") + "]")
    files = _pairs(pages)
    if len(files) != data["changed_files"]:
        # The files endpoint lists at most 3000: the rest is unread.
        files.append(("DuoUpdaterCore/Sources/(files beyond the API's list)", None))
    head_sha = data["head"]["sha"]

    def compare(sha):
        try:
            c = json.loads(_gh(["api", "repos/%s/compare/%s...%s" % (repo, sha, head_sha)]))
        except subprocess.CalledProcessError:
            return None
        if c.get("status") not in ("ahead", "identical"):
            return None
        later = _pairs(c.get("files") or [])
        if c.get("ahead_by", 0) and len(later) >= 300:
            later.append(("DuoUpdaterCore/Sources/(files beyond the compare list)", None))
        return later

    return data.get("body") or "", data["head"]["ref"], files, compare


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pr", required=True)
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "jizhi0v0/duo-updater"))
    args = ap.parse_args(argv)
    body, head_ref, files, compare = fetch(args.repo, args.pr)
    passed, message = evaluate(body, head_ref, files, compare)
    print("#%s: %s" % (args.pr, "PASS" if passed else "FAIL"))
    print(message)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
