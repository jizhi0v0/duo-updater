#!/usr/bin/env python3
"""Refuse a pull request that changes product code without a real-machine record.

Run by `.github/workflows/real-machine.yml` on every pull request event,
including an edit to the description. Also runs by hand against any PR:

    python3 scripts/check_real_machine_record.py --pr 1564

## What this is for

Behaviour changes, one-click onboarding above all, are verified on a real Mac
before they merge, and the result goes into the PR description (and the app's
audit). Releases 0.5.2, 0.5.3 and 0.5.8 had to re-run real-machine tests while
writing their notes, because PRs had merged on a reading of the code, or with a
run nobody wrote down (#1340: Thunderbird's one-click was only read, never run).
This check moves that catch from release time to before the merge.

## The rule

A pull request is covered when it changes a file under one of `COVERED`: the
Swift that ships in the app, its privileged helper and `duo` (recipes live
under `DuoUpdaterCore/Sources/`, so they are covered too). Docs, tests,
goldens, scripts and workflows are not, so a PR that only touches those passes
without a word. Branches in `EXEMPT_BRANCHES` pass too: machine-written
(verify baselines, recipe autofix, bench runs) or publishing what was already
verified (release, appcast).

A covered PR's description must have one of:

  (a) a real-machine section: a Markdown heading that says `Real-machine` (or
      `Real machine`, or 真机) and is not a pending placeholder, whose heading
      or body has a date (YYYY-MM-DD) and whose body has at least one result
      line: a list item, a table row or a line of a fenced code block. The
      onboarding PRs write `## Real-machine result (2026-10-22)`. A heading
      with pending wording (`PENDING`: "pending", "not done", "for the main
      session", 待, 未跑 …) is a placeholder, whatever else it has. An
      unticked `- [ ]` item is a plan, not a result, and neither is a line with
      pending wording unless it also marks an outcome (✓ ✔ ✗ ✘): "✓ round 1;
      round 2 未跑" is a result, "round 2 not done yet" is not;

  (b) an opt-out line, for a refactor, test-only change or internal plumbing
      that has no behaviour to see on a machine:

          Real-machine: not needed — <reason>

      The reason must not be empty.

## What it cannot see

Whether the record is true, or covers what the PR changed. It checks that one
was written; REVIEW.md asks the review bot to judge it. A section runs to the
next heading of the same or a higher level, so its sub-headings' lines count
for it. A heading or opt-out inside a fenced code block is not read at all.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys

# Directories whose changes are user-visible behaviour.
COVERED = (
    "DuoUpdaterCore/Sources/",
    "App/Sources/",
    "App/Helper/",
    "App/Shared/",
    "CLI/Sources/",
)

# The prefixes claude-review.yml skips, plus `release/` (version bump and
# changelog, already verified in the PRs it releases).
EXEMPT_BRANCHES = (
    "release/",
    "appcast/",
    "verify/baseline-",
    "verify/install-",
    "recipe-autofix/",
    "bench/",
)

HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
RECORD_HEADING = re.compile(r"real[- ]machine|真机", re.IGNORECASE)
# The wording this repository's descriptions use for a run nobody did yet:
# "Real machine: pending (main session)", 真机：待主会话, #1588's "Not done here
# (real-machine checks for the main session)".
PENDING = re.compile(
    r"pending|待|\btodo\b|\bto do\b|not run|not done|not yet|planned|"
    r"for the main session|未跑|未验|未做|没跑|没做",
    re.IGNORECASE,
)
UNTICKED = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[ \]")
OUTCOME = re.compile(r"[✓✔✗✘]")
DATE = re.compile(r"\b(20\d\d)-(\d\d)-(\d\d)\b")
RESULT_LINE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\S|^\s*\|")
TABLE_RULE = re.compile(r"^\s*\|[\s:|-]*\|?\s*$")
FENCE = re.compile(r"^\s*(```|~~~)")
OPT_OUT = re.compile(
    r"^[\s>*_+-]*real[- ]machine\W*not needed\W*?[—–:-]+(.*)$", re.IGNORECASE
)


def covered_files(files):
    return [f for f in files if f.startswith(COVERED)]


def _lines_outside_fences(body):
    """(line, in_fence) for every line; fence markers themselves are in_fence."""
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


def opt_out_reason(body):
    for line, in_fence in _lines_outside_fences(body):
        if in_fence:
            continue
        m = OPT_OUT.match(line)
        if m:
            reason = m.group(1).strip(" *_")
            if re.search(r"\w", reason):
                return reason
    return None


def record_sections(body):
    """Each real-machine heading: (heading, has_date, result_line_count)."""
    lines = _lines_outside_fences(body)
    sections = []
    for i, (line, in_fence) in enumerate(lines):
        m = None if in_fence else HEADING.match(line)
        if not m or not RECORD_HEADING.search(m.group(2)):
            continue
        level, title = len(m.group(1)), m.group(2)
        if PENDING.search(title):
            sections.append((title, False, 0))
            continue
        dated = _has_date(title)
        results = 0
        for text, fenced in lines[i + 1:]:
            if not fenced:
                h = HEADING.match(text)
                if h and len(h.group(1)) <= level:
                    break
                if h:
                    continue
            if FENCE.match(text):
                continue
            dated = dated or _has_date(text)
            if fenced and text.strip():
                results += 1
            elif (not fenced and RESULT_LINE.match(text)
                  and not TABLE_RULE.match(text) and not UNTICKED.match(text)
                  and (OUTCOME.search(text) or not PENDING.search(text))):
                results += 1
        sections.append((title, dated, results))
    return sections


def evaluate(body, files, head_ref, files_complete=True):
    """(passed, message)."""
    for prefix in EXEMPT_BRANCHES:
        if head_ref.startswith(prefix):
            return True, "exempt: branch %s starts with %s" % (head_ref, prefix)
    hit = covered_files(files)
    if not hit and files_complete:
        return True, "exempt: no file under %s changed" % ", ".join(COVERED)
    if not hit:
        reason = "the file list is incomplete, so it may change product code"
    else:
        shown = ", ".join(hit[:3]) + (" …" if len(hit) > 3 else "")
        reason = "%d product file(s) changed (%s)" % (len(hit), shown)

    body = body or ""
    reason_text = opt_out_reason(body)
    if reason_text:
        return True, "opt-out: Real-machine: not needed — %s" % reason_text
    sections = record_sections(body)
    for title, dated, results in sections:
        if dated and results:
            return True, "record: \"%s\" (dated, %d result line(s))" % (title, results)

    problems = []
    for title, dated, results in sections:
        if PENDING.search(title):
            problems.append("  \"%s\" is a pending placeholder" % title)
            continue
        missing = []
        if not dated:
            missing.append("date (YYYY-MM-DD)")
        if not results:
            missing.append("result line (list item, table row or code block)")
        problems.append("  \"%s\" has no %s" % (title, " and no ".join(missing)))
    msg = [
        "%s, but the description has no real-machine record." % reason,
    ]
    if problems:
        msg.append("Real-machine headings found:")
        msg.extend(problems)
    msg += [
        "Add one of:",
        "  ## Real-machine result (YYYY-MM-DD)",
        "  - <what was run and what happened>",
        "or, when there is nothing to see on a machine, a line:",
        "  Real-machine: not needed — <reason>",
    ]
    return False, "\n".join(msg)


def _gh(args):
    return subprocess.run(
        ["gh"] + args, check=True, capture_output=True, text=True
    ).stdout


def fetch(repo, pr):
    """Body, head ref, changed files and whether the list is complete, read now
    (not from the event payload, so a re-run sees the current description)."""
    data = json.loads(_gh(["api", "repos/%s/pulls/%s" % (repo, pr)]))
    files = _gh([
        "api", "--paginate", "repos/%s/pulls/%s/files" % (repo, pr),
        "--jq", ".[].filename",
    ]).split()
    # The files endpoint lists at most 3000.
    complete = len(files) == data["changed_files"]
    return data.get("body") or "", data["head"]["ref"], files, complete


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pr", required=True)
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "jizhi0v0/duo-updater"))
    args = ap.parse_args(argv)
    body, head_ref, files, complete = fetch(args.repo, args.pr)
    passed, message = evaluate(body, files, head_ref, complete)
    print("#%s: %s" % (args.pr, "PASS" if passed else "FAIL"))
    print(message)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
