#!/usr/bin/env python3
"""Refuse a change to one side of a declared link that leaves the other side alone.

Run by `make test` (markers only) and by ci.yml's `ifchange` job (markers plus
the pull request's diff).

    python3 scripts/check_ifchange.py                    # markers only
    python3 scripts/check_ifchange.py --base origin/main # and this branch's diff

## What this is for

Some code has to change together and nothing can tell. The compiler sees a
renamed function; it does not see that a Python script re-implements a Swift
rule as a second witness, or that a Core type and an App type carry the same
identity fields. What held those pairs together was a comment ("kept in step
by a comment saying so" — `StagedPackagePrune`'s own history), and a comment
is only read by whoever already knows to look. A text search does not find the
other side either: it finds the spelling, not the obligation.

So the obligation is written down where both sides can be read by a script:

    // LINT.IfChange(classify)
    static func classify(_ value: String) -> Declaration { … }
    // LINT.ThenChange(scripts/pkg_host_architectures.py:classify)

and in the other file, the same pair pointing back. Any comment syntax works
(`//`, `#`, `<!--`, `--`, `*`), but the marker must be the whole comment, so
prose that mentions one is not read as one. The syntax is Chromium's and
TensorFlow's, so it reads the same to anyone who has met it there.

## What it checks

Always (no git history needed):

  * every `IfChange` is closed by a `ThenChange` in the same file, no nesting;
  * labels are unique within a file;
  * every target names a tracked file, and a `path:label` target names a label
    that file declares. A link whose other end was renamed or deleted is the
    standing pass this check exists to remove, so it fails rather than warns.

With `--base REF`, against the merge base of REF and HEAD (the working tree is
the new side, so it works before a commit as well as in CI):

  * a block whose content changed must see each of its targets change too —
    anywhere in the file for a bare path, inside the labelled block for
    `path:label`. Edits to the two marker lines themselves do not count as a
    change to the block, and neither does a block whose `IfChange` line is new:
    introducing a link is not changing what it guards.

## When the other side really needs nothing

Write `NO_IFTTT=<reason>` in a commit message on the branch or in the pull
request's description. The violations are then printed as warnings and the
check passes. CI only sees the latest commit's message (the checkout is two
deep) and the description as it was when the run started, so after editing the
description, re-run the job.

## What it cannot do

It knows only the links someone wrote down. It is meant for couplings the
compiler cannot see — across languages, across packages, code against prose.
A link between two Swift functions that could call one shared helper is better
replaced by the helper.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# This file and its tests explain the markers in prose and fixtures; scanning
# them would read the examples as links.
EXCLUDED = {"scripts/check_ifchange.py", "scripts/test_check_ifchange.py"}

LABEL = r"[A-Za-z0-9_.-]+"
# The marker is the whole comment: a line that goes on in prose after it
# ("# LINT.IfChange / LINT.ThenChange links …") is talking about markers.
MARKER = re.compile(
    r"^\s*(?://+|#+|<!--|/?\*+|--)\s*LINT\.(IfChange|ThenChange)"
    r"(?:\(([^)]*)\))?\s*(?:-->|\*/)?\s*$")
LABEL_RE = re.compile(rf"^{LABEL}$")
OVERRIDE = re.compile(r"\bNO_IFTTT=\s*\S")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


class Block:
    """One `IfChange` … `ThenChange` pair. Lines are 1-based, both markers included."""

    def __init__(self, path, label, start):
        self.path = path
        self.label = label
        self.start = start
        self.end = None
        self.targets = []  # (path, label or None)

    def name(self):
        return f"{self.path}:{self.label}" if self.label else self.path


def parse(path, text):
    """The blocks in one file, and the marker errors found while reading it."""
    blocks, errors, open_block = [], [], None
    for n, line in enumerate(text.splitlines(), 1):
        m = MARKER.match(line)
        if not m:
            continue
        kind, arg = m.group(1), m.group(2)
        where = f"{path}:{n}"
        if kind == "IfChange":
            if open_block:
                errors.append(f"{where}: LINT.IfChange inside the block opened on "
                              f"line {open_block.start}; blocks do not nest")
                continue
            label = (arg or "").strip() or None
            if label and not LABEL_RE.match(label):
                errors.append(f"{where}: label {label!r} is not [A-Za-z0-9_.-]+")
                label = None
            open_block = Block(path, label, n)
        else:
            if not open_block:
                errors.append(f"{where}: LINT.ThenChange with no LINT.IfChange open")
                continue
            targets = [t.strip() for t in (arg or "").split(",") if t.strip()]
            if not targets:
                errors.append(f"{where}: LINT.ThenChange names no target")
            for t in targets:
                tpath, _, tlabel = t.removeprefix("//").partition(":")
                if tlabel and not LABEL_RE.match(tlabel):
                    errors.append(f"{where}: target {t!r} has a malformed label")
                open_block.targets.append((tpath, tlabel or None))
            open_block.end = n
            blocks.append(open_block)
            open_block = None
    if open_block:
        errors.append(f"{path}:{open_block.start}: LINT.IfChange never closed "
                      f"by a LINT.ThenChange")
    seen = {}
    for b in blocks:
        if b.label and b.label in seen:
            errors.append(f"{path}:{b.start}: label {b.label!r} already used on "
                          f"line {seen[b.label]}")
        elif b.label:
            seen[b.label] = b.start
    return blocks, errors


def git(*args, root=ROOT):
    return subprocess.run(["git", *args], cwd=root, check=True,
                          capture_output=True, text=True).stdout


def tracked_files(root=ROOT):
    return [p for p in git("ls-files", "-z", root=root).split("\0") if p]


def scan(root=ROOT):
    """All blocks by path, and every marker and target error in the tree."""
    files = tracked_files(root)
    present = set(files)
    by_path, errors = {}, []
    for rel in files:
        if rel in EXCLUDED:
            continue
        try:
            data = (root / rel).read_bytes()
        except (FileNotFoundError, IsADirectoryError):
            continue  # deleted in the working tree, or a submodule
        if b"LINT." not in data:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        blocks, errs = parse(rel, text)
        errors += errs
        if blocks:
            by_path[rel] = blocks
    for blocks in by_path.values():
        for b in blocks:
            for tpath, tlabel in b.targets:
                if tpath not in present or not (root / tpath).is_file():
                    errors.append(f"{b.path}:{b.end}: target {tpath} is not a "
                                  f"tracked file")
                elif tlabel and not any(t.label == tlabel
                                        for t in by_path.get(tpath, [])):
                    errors.append(f"{b.path}:{b.end}: {tpath} declares no "
                                  f"LINT.IfChange({tlabel})")
    return by_path, errors


class Changes:
    """New-side line numbers a diff touched in one file.

    `lines` holds added or rewritten lines. `cuts` holds the positions of pure
    deletions: a cut at c means lines were removed between new lines c and c+1.
    """

    def __init__(self):
        self.lines = set()
        self.cuts = set()

    def body(self, b):
        """Whether anything between the block's two marker lines changed."""
        return (any(b.start < n < b.end for n in self.lines)
                or any(b.start <= c < b.end for c in self.cuts))


def parse_diff(text):
    changes, current = {}, None
    for line in text.splitlines():
        if line.startswith("+++ "):
            target = line[4:]
            current = None if target == "/dev/null" else \
                changes.setdefault(target.removeprefix("b/"), Changes())
        elif line.startswith("@@") and current is not None:
            m = HUNK.match(line)
            start, count = int(m.group(1)), int(m.group(2) or "1")
            if count == 0:
                current.cuts.add(start)
            else:
                current.lines.update(range(start, start + count))
    return changes


def violations(by_path, changes):
    """`(block, [missing targets])` for each changed block whose targets did not change."""
    found = []
    for path, blocks in sorted(by_path.items()):
        ch = changes.get(path)
        if not ch:
            continue
        for b in blocks:
            if b.start in ch.lines or not ch.body(b):
                continue
            missing = []
            for tpath, tlabel in b.targets:
                tch = changes.get(tpath)
                if tch and tlabel is None:
                    continue
                if tch and any(t.label == tlabel and tch.body(t)
                               for t in by_path.get(tpath, [])):
                    continue
                missing.append(f"{tpath}:{tlabel}" if tlabel else tpath)
            if missing:
                found.append((b, missing))
    return found


def override_text(merge_base, root=ROOT):
    """Commit messages on the branch, plus the pull request description in CI."""
    text = git("log", "--format=%B", f"{merge_base}..HEAD", root=root)
    event = os.environ.get("GITHUB_EVENT_PATH")
    if event and os.path.isfile(event):
        with open(event, encoding="utf-8") as f:
            pr = json.load(f).get("pull_request") or {}
        text += "\n" + (pr.get("body") or "")
    return text


def main(argv=None, root=ROOT):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", help="also check the diff from merge-base(BASE, HEAD) "
                                   "to the working tree")
    args = ap.parse_args(argv)

    by_path, errors = scan(root)
    for e in errors:
        print(f"✗ {e}", file=sys.stderr)
    links = sum(len(bs) for bs in by_path.values())

    found = []
    if args.base:
        merge_base = git("merge-base", args.base, "HEAD", root=root).strip()
        diff = git("diff", "--unified=0", "--no-color", "--no-renames",
                   "--no-ext-diff", merge_base, "--", root=root)
        found = violations(by_path, parse_diff(diff))
        overridden = bool(found) and OVERRIDE.search(override_text(merge_base, root))
        mark = "⚠" if overridden else "✗"
        for b, missing in found:
            print(f"{mark} {b.path}:{b.start}: {b.name()} changed, but not "
                  f"{', '.join(missing)}", file=sys.stderr)
        if found and overridden:
            print("  NO_IFTTT= given on this branch; passing.", file=sys.stderr)
            found = []
        elif found:
            print("  Change the other side too, or say why it needs nothing with "
                  "NO_IFTTT=<reason> in a commit message or the PR description.",
                  file=sys.stderr)

    if errors or found:
        return 1
    print(f"✓ {links} LINT.IfChange block(s) checked"
          + (f" against {args.base}" if args.base else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
