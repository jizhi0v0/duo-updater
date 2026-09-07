#!/usr/bin/env python3
"""A `docs/engine-notes/…md §N` pointer in a source comment is only as good
as its target. Nothing checked that before this script.

Issue #409's whole premise is "trim the comment, but keep the fact
findable" — `docs/engine-notes/README.md`'s checklist calls this
"信息可找回" (information is recoverable). A pointer with no guard behind it
can go stale three ways, and none of them produce an error anywhere else:

1. **The file moves or gets renamed.** The pointer keeps reading fine; the
   next person to follow it gets a 404.
2. **The file exists on disk but was never tracked.** `/docs/*` is
   gitignored by default (see `.gitignore`); `docs/engine-notes/` is one of
   three carve-outs (`docs/app-audits/`, `docs/update-manifest-families.md`
   are the other two). A future note dropped one directory over — or added
   before the carve-out line — exists and reads correctly for whoever wrote
   it, and is invisible to everyone else. `os.path.exists` cannot tell these
   two cases apart; `git ls-files` can.
3. **The section gets renumbered or reworded**, and the pointer's `§N` now
   names a heading that isn't there.

This is the same shape `check_app_audits.py` already guards
(`check_no_local_evidence_pointers`, `check_links_resolve`) for
`docs/app-audits/`, applied to the newer `docs/engine-notes/` convention —
and, on top of it, the README's Index (the directory's own navigation) is
checked against the directory's actual contents, the same way
`check_app_audits.py`'s `check_index` does.

Deliberately NOT checked: whether the prose AROUND a pointer is accurate.
That is what `/code-review` and the human "re-check every historical claim"
step in `docs/engine-notes/README.md` are for. This script only answers
"does the thing being pointed at exist, and is it reachable by everyone who
clones this repo" — the same narrow, mechanical question
`check_prose_claims.py` answers about a different shape of drift.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOTES_DIR = "docs/engine-notes"
README = os.path.join(NOTES_DIR, "README.md")

SOURCE_ROOTS = [
    "DuoUpdaterCore/Sources", "DuoUpdaterCore/Tests",
    "App/Sources", "App/Tests",
    "CLI/Sources", "CLI/Tests",
]

# A pointer like `` `docs/engine-notes/app-store-page-cache.md` §4.2 ``. The
# section is optional — a pointer to a whole doc with no specific section is
# legitimate — but when it IS there it has to sit right after the backtick
# (with at most whitespace or a comma between), the way every instance in
# this repo is written today. A pointer that puts prose between the path and
# the section number is a shape nobody has written yet; widen this if one
# shows up.
POINTER = re.compile(
    r"`(" + re.escape(NOTES_DIR) + r"/([\w.-]+\.md))`"
    r"(?:[\s,]*§(\d+(?:\.\d+)*))?"
)

# A markdown link target inside the Index, e.g. `[`x.md`](x.md)`.
LINK = re.compile(r"\]\(([A-Za-z0-9._/-]+\.md)\)")


def tracked_files():
    """Every path `git` actually tracks under docs/engine-notes/.

    Not `os.path.exists`: a file can exist on the machine that wrote it and
    still be invisible to `git clone` if it landed outside the `.gitignore`
    carve-out. `git ls-files` is what everyone else's checkout will see.
    """
    out = subprocess.run(
        ["git", "ls-files", NOTES_DIR + "/"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    return set(out.splitlines())


def comment_blocks(path):
    """Consecutive `//`/`///` lines, joined — a pointer's path and its `§N`
    are usually split across two source lines by the 80-ish column wrap
    (see every instance in AppStorePageCache.swift). A line-based scanner
    would see the path on one line and the section marker on the next and
    match neither.
    """
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    buf, start = [], 0
    for i, raw in enumerate(lines):
        stripped = raw.strip()
        if stripped.startswith("//"):
            if not buf:
                start = i + 1
            buf.append(re.sub(r"^/{2,3}\s?", "", stripped))
        else:
            if buf:
                yield start, " ".join(buf)
            buf = []
    if buf:
        yield start, " ".join(buf)


def heading_sections(path):
    """Every `§N` (or `§N.M`) that appears in a markdown heading line."""
    sections = set()
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\s{0,3}#{1,6}\s+§(\d+(?:\.\d+)*)\b", line)
        if m:
            sections.add(m.group(1))
    return sections


def check_pointers(problems, tracked):
    section_cache = {}
    scanned = 0
    for root in SOURCE_ROOTS:
        base = os.path.join(ROOT, root)
        if not os.path.isdir(base):
            continue
        for dirpath, _, filenames in os.walk(base):
            if ".build" in dirpath.split(os.sep):
                continue
            for name in filenames:
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT)
                scanned += 1
                for start, joined in comment_blocks(path):
                    for m in POINTER.finditer(joined):
                        full_rel, filename, section = m.groups()
                        target = os.path.join(ROOT, full_rel)
                        if full_rel not in tracked:
                            reason = ("does not exist" if not os.path.exists(target)
                                      else "exists on disk but is not tracked by git "
                                           "(docs/* is gitignored by default — check "
                                           "the carve-out in .gitignore)")
                            problems.append(
                                f"{rel}:{start}: points at `{full_rel}`, which {reason}"
                            )
                            continue
                        if section is None:
                            continue
                        if full_rel not in section_cache:
                            section_cache[full_rel] = heading_sections(target)
                        if section not in section_cache[full_rel]:
                            problems.append(
                                f"{rel}:{start}: points at `{full_rel}` §{section}, "
                                f"but that file has no `§{section}` heading"
                            )
    return scanned


def check_index(problems, tracked):
    docs = sorted(
        os.path.basename(f) for f in tracked
        if f.startswith(NOTES_DIR + "/") and f.endswith(".md")
        and os.path.basename(f) != "README.md"
    )
    readme_path = os.path.join(ROOT, README)
    linked = {os.path.basename(t) for t in LINK.findall(
        open(readme_path, encoding="utf-8").read()
    )}
    for name in docs:
        if name not in linked:
            problems.append(
                f"{README}: Index does not list {NOTES_DIR}/{name}"
            )
    return len(docs)


def main():
    if not os.path.isfile(os.path.join(ROOT, README)):
        print(f"✗ {README} does not exist — nothing to check", file=sys.stderr)
        return 1

    tracked = tracked_files()
    problems = []
    scanned = check_pointers(problems, tracked)
    n_docs = check_index(problems, tracked)

    if scanned < 100:
        print(f"✗ only {scanned} Swift files scanned across {len(SOURCE_ROOTS)} "
              "roots — too few to be a real run.", file=sys.stderr)
        return 1

    if problems:
        print("✗ engine-notes pointers disagree with what they point at:")
        for p in problems:
            print(f"    {p}")
        return 1

    print(f"✓ engine-notes pointers resolve — {scanned} Swift files scanned, "
          f"{n_docs} doc(s) indexed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
