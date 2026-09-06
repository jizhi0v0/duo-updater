#!/usr/bin/env python3
"""Refuse a code comment whose evidence lives only on the author's disk.

Run by `make test`.

    python3 scripts/check_prose_claims.py

## What this is for

This repository writes its comments as "measured, on <date>, <number>". That is
a good habit and it is not the target. The target is the subset where the
measurement is a count of THIS MACHINE's app population — because a claim like

    1 of the 22 store apps on this machine

cannot be reproduced, re-derived or falsified by CI, by a subagent, or by anyone
reading it later. The only person who can check it is the person who wrote it,
and they already did. So it reads as measured, is treated as measured, and stays
standing after it stops being true.

That is not hypothetical. The sentence above was written on 2026-08-29, was
false on the day it was written (Keka is Developer ID-signed with no
`_MASReceipt`), and was the sole recorded justification for a real hole in the
update path. It survived a week and was repeated into three more files, once by
someone who was being careful and citing a dated measurement.

## What it does NOT do

It cannot tell whether a claim is true. It governs where a claim may LIVE. A
population count that has to leave a code comment becomes a claim about an app
or an endpoint — and that kind of claim has a home, `docs/app-audits/`, whose
format asks how to re-verify it. Reaching for that section is where an author
discovers they cannot.

Rewriting to dodge the pattern also dodges the check. That is fine and expected:
the point is to make the shape unwelcome, not to be unfoolable.
"""

import pathlib
import re
import sys

ROOTS = [
    "DuoUpdaterCore/Sources", "DuoUpdaterCore/Tests",
    "App/Sources", "App/Tests",
    "CLI/Sources", "CLI/Tests",
]

MACHINE = r"(?:this|one|another|a real|the development) machine"

# Deliberately narrow, and arrived at by measuring rather than by taste.
#
# A bare "this machine" ban is unworkable: 71 occurrences in Sources alone, and
# most are runtime semantics ("the machine running this"), not claims. A first
# attempt that also matched "<verified> on this machine <date>" produced 20 hits,
# nearly all of them legitimate dated verifications of a real artifact — which
# anyone holding that artifact can redo, so they are not the problem.
#
# What is left is the one shape nobody can redo: a count whose denominator is
# THIS machine's population. The marker may sit on either side of the count
# ("55 of 145 … on a real machine" and "on a real machine … 55 of 145" both
# occur), hence the two mirrored alternatives.
#
# A standalone `installed here` alternative was tried and removed: on its own it
# only matched code semantics ("`versions` only ever holds what is installed
# here"). The phrase is still caught inside a count — "of the 22 store apps
# installed here" hits the last alternative — which is the only form that was
# ever the point.
#
# Measured on the tree the check landed on: 5 hits, all genuine, no false
# positives — and three real comments that must NOT hit are fixtures in the test
# file (a dated artifact verification, a runtime "installed here", and a count of
# a FEED's items rather than a machine's).
PATTERN = re.compile(
    rf"\b[0-9]+ of (?:the )?[0-9]+[^.]{{0,90}}?{MACHINE}\b"
    rf"|{MACHINE}\b[^.]{{0,120}}?\b[0-9]+ of (?:the )?[0-9]+\b"
    r"|\b(?:feeds|apps|casks|bundles|copies|rows)\s+"
    r"(?:readable|reachable|installed|present|scanned)\s+on\s+this\s+machine\b"
    r"|\bof the [0-9]+ [a-z ]{0,30}\b(?:on this machine|here)\b",
    re.I)

MARKER = "claim-lint:allow-machine-state"
# The reason is not optional. `check_staged_version_use.py`'s
# `version-lint:allow-marketing-first` works the same way: an escape hatch that
# takes no argument is just a way to turn the check off.
REASON = re.compile(re.escape(MARKER) + r"\s*[—-]\s*(\S.*)")


def comment_blocks(path):
    """Consecutive comment lines, joined, with the line the block starts on.

    Joining is the whole reason this is a script and not a `grep`. The sentence
    that motivated it wraps:

        /// ... measured 2026-08-29, Keka
        /// is a store copy carrying `SUFeedURL = ...`, 1 of the 22 store
        /// apps on this machine).

    A line-based scanner finds nothing there — it would have shipped as a check
    that had never once gone red, which this repository has deleted before
    (`make width-check`).
    """
    lines = path.read_text(errors="replace").splitlines()
    buf, start = [], 0
    for i, raw in enumerate(lines):
        stripped = raw.strip()
        if stripped.startswith("//"):
            if not buf:
                start = i + 1
            buf.append(re.sub(r"^/{2,3}\s?", "", stripped))
        elif buf:
            yield start, buf
            buf = []
    if buf:
        yield start, buf


def review(root, roots=ROOTS):
    """Everything the check knows, as data, so the tests can drive it.

    `main` owns only the printing and the two emptiness gates — which is what
    lets a test point this at a three-file fixture without tripping the floor.
    """
    missing = [r for r in roots if not (root / r).is_dir()]
    scanned, offences, dead = 0, [], []
    for r in roots:
        base = root / r
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            if ".build" in path.parts:
                continue
            rel = path.relative_to(root)
            scanned += 1
            for start, block in comment_blocks(path):
                joined = " ".join(block)
                match = PATTERN.search(joined)
                # The marker has to START a line of the comment. Anywhere-in-the
                # -block would mean a comment that merely DESCRIBES the
                # convention reads as invoking it — and, with no claim beside it,
                # gets reported as a stale exemption, which is neither true nor
                # actionable.
                marker_line = next(
                    (line for line in block if line.startswith(MARKER)), None)
                exempt = marker_line is not None
                reason = REASON.search(marker_line) if marker_line else None
                if match and not exempt:
                    offences.append((rel, start, match.group(0)))
                elif match and exempt and not reason:
                    offences.append((rel, start,
                                     f"{MARKER} with no reason after it"))
                elif exempt and not match:
                    # An exemption that no longer matches anything is a standing
                    # pass for whatever is written there next. `make gallery`
                    # fails on a stale `mayLookAlike` for the same reason, and
                    # CLAUDE.md records (#271) what happens to the one gate that
                    # skipped it: the exempted case is never inspected again.
                    dead.append((rel, start))
    return {"missing": missing, "scanned": scanned,
            "offences": offences, "dead": dead}


def main(root=None, roots=ROOTS, minimum=200):
    root = root or pathlib.Path(__file__).resolve().parent.parent
    found = review(root, roots=roots)

    # Fail on a root that is not there, rather than scanning fewer.
    #
    # Written after the first run of this file printed "✓ … 0 roots scanned" and
    # exited 0, from a scratch directory. A rename, a move, or being invoked from
    # somewhere unexpected would have turned this into a check that passes
    # because it looked at nothing — the failure mode CLAUDE.md keeps warning
    # about, produced by the tool built to warn about it.
    if found["missing"]:
        print(f"✗ these source roots are not under {root}: "
              f"{', '.join(found['missing'])}\n"
              "  Fix the paths rather than dropping them.", file=sys.stderr)
        return 1

    # The other half of that gate: `rglob` finding nothing inside a directory
    # that exists is just as silent as the directory being gone.
    if found["scanned"] < minimum:
        print(f"✗ only {found['scanned']} Swift files scanned across "
              f"{len(roots)} roots — too few to be a real run.", file=sys.stderr)
        return 1

    offences, dead = found["offences"], found["dead"]
    if not offences and not dead:
        print(f"✓ no machine-population claims in code comments — "
              f"{found['scanned']} files")
        return 0

    for rel, line, text in offences:
        print(f"✗ {rel}:{line}: this counts THIS MACHINE's apps, so nobody else "
              f"can check it\n    …{text}…", file=sys.stderr)
    for rel, line in dead:
        print(f"✗ {rel}:{line}: `{MARKER}` here no longer exempts anything — "
              "delete it, or it silently exempts whatever is written next",
              file=sys.stderr)
    print(f"\n{len(offences)} claim(s), {len(dead)} stale exemption(s).\n"
          "Rewrite it as a claim about the app or the endpoint — one anyone can "
          "re-derive — or, if the count really is the point, add\n"
          f"    {MARKER} — <why nobody needs to re-derive this>\n"
          "on a line inside the same comment block.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
