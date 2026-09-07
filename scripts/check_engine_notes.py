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

# A pointer like `` `docs/engine-notes/app-store-page-cache.md` §4.2 ``, or a
# run of them (`§1, §2, and §3`). Sections are optional — pointing at a whole
# doc is legitimate — but EVERY section in the run is checked, not just the
# first: a regex that stopped at one would have gone on reporting success for
# a pointer whose second and third sections had been renumbered away, which is
# the failure this script exists to make loud. A pointer that puts prose
# between the path and its sections is a shape nobody has written yet; widen
# `SECTION_RUN` if one shows up.
SECTION_RUN = r"((?:[\s,]*(?:and\s+)?§\d+(?:\.\d+)*)*)"
SECTION = re.compile(r"§(\d+(?:\.\d+)*)")

POINTER = re.compile(
    r"`(" + re.escape(NOTES_DIR) + r"/([\w./-]+\.md))`" + SECTION_RUN
)

# The same pointer as written INSIDE the notes directory, where a sibling is
# named relative to it: `` `app-store-page-cache.md` §4.2 ``. README.md's own
# "see the … note in X §N for the format" is one of these, and before this it
# was the one pointer in the convention with nothing behind it — the guard
# `check_app_audits.py` has for audit-to-audit links, which this file's
# earlier version replicated for code-to-doc only.
#
# ⚠️ Only counted as a pointer when a `§N` run follows it. A backticked
# filename on its own is prose — a note that says "the rule this came from
# lives in `CLAUDE.md`" names a file that is not, and never will be, a
# sibling note, and resolving it here would fail the build on a sentence
# nobody meant as a pointer. `§N` is this convention's own notation, so it is
# what separates the two. Plain markdown links are checked separately, by
# `check_doc_links`, where the syntax is unambiguous.
DOC_POINTER = re.compile(r"`([\w.-]+\.md)`" + SECTION_RUN)

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

    Yields `(joined, spans)`, where `spans` maps each line's offset in
    `joined` back to its line number. A blank `///` separator does NOT break
    a block (it still starts with `//`), so one block is routinely a whole
    multi-paragraph doc comment: reporting the block's first line instead of
    the pointer's own sent the reader 17-22 lines up the comment in the three
    real pointers this repo has today.
    """
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    buf, spans, width = [], [], 0
    for i, raw in enumerate(lines):
        stripped = raw.strip()
        if stripped.startswith("//"):
            text = re.sub(r"^/{2,3}\s?", "", stripped)
            spans.append((width, i + 1))
            width += len(text) + 1  # +1 for the joining space
            buf.append(text)
        else:
            if buf:
                yield " ".join(buf), spans
            buf, spans, width = [], [], 0
    if buf:
        yield " ".join(buf), spans


def line_for(spans, offset):
    """The source line a character offset in a joined block came from."""
    line = spans[0][1] if spans else 0
    for start, number in spans:
        if start > offset:
            break
        line = number
    return line


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
                for joined, spans in comment_blocks(path):
                    for m in POINTER.finditer(joined):
                        full_rel, _, run = m.groups()
                        where = f"{rel}:{line_for(spans, m.start())}"
                        resolve(problems, where, full_rel, run, tracked, section_cache)
    return scanned


def resolve(problems, where, full_rel, run, tracked, section_cache):
    """One pointer: the target has to be tracked, and every `§N` in the run
    has to name a heading it really has."""
    target = os.path.join(ROOT, full_rel)
    if full_rel not in tracked:
        reason = ("does not exist" if not os.path.exists(target)
                  else "exists on disk but is not tracked by git "
                       "(docs/* is gitignored by default — check "
                       "the carve-out in .gitignore)")
        problems.append(f"{where}: points at `{full_rel}`, which {reason}")
        return
    sections = SECTION.findall(run or "")
    if not sections:
        return
    if full_rel not in section_cache:
        section_cache[full_rel] = heading_sections(target)
    for section in sections:
        if section not in section_cache[full_rel]:
            problems.append(
                f"{where}: points at `{full_rel}` §{section}, "
                f"but that file has no `§{section}` heading"
            )


def check_doc_pointers(problems, tracked):
    """The same guard for pointers written INSIDE the notes directory.

    `check_app_audits.py` grew `check_links_resolve` because two audits point
    at each other and renaming one broke the other silently. This directory
    has one such pointer already — README.md cites `app-store-page-cache.md`
    §4.2 as the format to copy — and it was the one pointer in the convention
    with nothing behind it.
    """
    section_cache = {}
    for doc in sorted(tracked):
        if not doc.endswith(".md"):
            continue
        text = open(os.path.join(ROOT, doc), encoding="utf-8").read()
        for m in DOC_POINTER.finditer(text):
            name, run = m.groups()
            if not SECTION.search(run or ""):
                continue  # prose naming a file, not a pointer — see DOC_POINTER
            where = f"{doc}:{text.count(chr(10), 0, m.start()) + 1}"
            resolve(problems, where, os.path.join(NOTES_DIR, name), run,
                    tracked, section_cache)


def check_doc_links(problems, tracked):
    """Markdown links between notes resolve — the half of
    `check_app_audits.py`'s `check_links_resolve` that applies here.

    Unambiguous syntax, so unlike `DOC_POINTER` this needs no `§N` to tell a
    link from a mention. Targets are read relative to the linking file, the
    way a reader's editor follows them.
    """
    for doc in sorted(tracked):
        if not doc.endswith(".md"):
            continue
        text = open(os.path.join(ROOT, doc), encoding="utf-8").read()
        for target in LINK.findall(text):
            resolved = os.path.normpath(
                os.path.join(os.path.dirname(doc), target))
            if resolved not in tracked:
                problems.append(
                    f"{doc}: links to `{target}`, which is not a tracked file"
                )


def check_index(problems, tracked):
    docs = sorted(
        f for f in tracked
        if f.startswith(NOTES_DIR + "/") and f.endswith(".md")
        and f != README
    )
    readme_path = os.path.join(ROOT, README)
    # Compared as full repo-relative paths, NOT basenames: a link into some
    # other directory that happens to share a filename
    # (`../app-audits/app-store-page-cache.md`) would otherwise be accepted as
    # this file's Index entry. `check_app_audits.py` compares paths for the
    # same reason.
    linked = {
        os.path.normpath(os.path.join(NOTES_DIR, t.lstrip("./")))
        if not t.startswith(NOTES_DIR) else os.path.normpath(t)
        for t in LINK.findall(open(readme_path, encoding="utf-8").read())
    }
    for doc in docs:
        if doc not in linked:
            problems.append(f"{README}: Index does not list {doc}")
    return len(docs)


def main():
    if not os.path.isfile(os.path.join(ROOT, README)):
        print(f"✗ {README} does not exist — nothing to check", file=sys.stderr)
        return 1

    tracked = tracked_files()
    problems = []
    scanned = check_pointers(problems, tracked)
    check_doc_pointers(problems, tracked)
    check_doc_links(problems, tracked)
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
