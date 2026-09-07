#!/usr/bin/env python3
"""The fragile-recipe skill ships twice and quotes the code. Both drift silently.

Two failures, both already observed in this repo:

1. **The two copies diverge.** `.claude/skills/fragile-recipe/` and
   `.agents/skills/fragile-recipe/` are the same skill served to two agent
   runtimes. They were committed together on 2026-06-02 and were *already*
   different that day — the `.agents` copy of `changelog-recipe.md` never had
   the `indexLinkPattern` section, so an agent reading it would conclude the
   registry cannot follow a per-version-page index. It can. Nobody noticed for
   three months, because a stale copy and a current one look identical from
   outside.

   A single copy was considered and rejected: `.agents/` is the cross-tool
   convention and some runtime may only be pointed at that subtree. So both
   copies stay, and this check is what keeps them honest.

   Both trees are **enumerated**, not listed here. The first version of this
   check carried the three filenames inline and so was blind to the likeliest
   next drift — a reference page added on one side only, which it reported as
   "3 files mirrored ✓". A hardcoded roster inside a drift check is the same
   hand-written list the check exists to outlaw.

2. **The documented parameter count rots.** Each reference page tells the reader
   "the initializer is the reference; this page is a tour of the common half"
   and states how many parameters that initializer has. That number is the
   reader's only signal that the page is partial — if it silently falls behind,
   the page reads as complete again, which is the exact failure the sentence was
   written to prevent. On 2026-09-07 the pages listed 9 and 12 of 24.

Deliberately NOT checked: that the pages describe every parameter. They are
tours by design, and a check demanding completeness would either be trivially
satisfied by a name dump or force the tour to become the source file.
"""

import os
import re
import sys

CLAUDE = ".claude/skills/fragile-recipe"
AGENTS = ".agents/skills/fragile-recipe"

# (reference page, source file, the initializer's opening line). The opening
# line is matched literally rather than by regex: these types have several
# `init`s (nested `VendorInstallSpec`, `RequestBody`, `VendorHostRequirement`)
# and a loose pattern silently counts the wrong one — which would make the check
# pass while comparing against a two-parameter initializer.
COUNTED = [
    (f"{CLAUDE}/references/vendor-probe-recipe.md",
     "DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/VendorProbeRecipe.swift",
     "public init(\n        bundleID: String,\n        url: URL,"),
    (f"{CLAUDE}/references/changelog-recipe.md",
     "DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/ChangelogRecipe.swift",
     "public init(\n        bundleID: String,\n        source: URL,"),
]

CLAIM = re.compile(r"takes \*\*(\d+)\*\* parameters")
# Parameters are one indent inside `public init(`, i.e. eight spaces. Anything
# deeper belongs to a default value spanning lines and is not a parameter.
PARAM = re.compile(r"^ {8}(\w+):", re.M)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def tree(root):
    """Every file under `root`, as paths relative to it.

    Enumerated rather than listed in this file. A hardcoded roster would be the
    same hand-written list this check exists to outlaw, and it would go blind in
    the most likely direction: a reference page added on one side only. That
    version of the check passed green on exactly that mutation.
    """
    found = set()
    for base, _, names in os.walk(root):
        for name in names:
            found.add(os.path.relpath(os.path.join(base, name), root))
    return found


def declared_parameters(source_path, opening):
    body = read(source_path)
    start = body.find(opening)
    if start < 0:
        return None, f"{source_path}: cannot find the initializer this check counts"
    end = body.find(") {", start)
    if end < 0:
        return None, f"{source_path}: initializer at offset {start} is unterminated"
    return PARAM.findall(body[start:end]), None


def main():
    problems = []

    claude_files, agents_files = tree(CLAUDE), tree(AGENTS)

    for name in sorted(claude_files - agents_files):
        problems.append(f"{AGENTS}/{name}: missing — {CLAUDE}/{name} has no "
                        f"counterpart; both runtimes get the same skill")
    for name in sorted(agents_files - claude_files):
        problems.append(f"{CLAUDE}/{name}: missing — {AGENTS}/{name} has no "
                        f"counterpart; both runtimes get the same skill")

    mirrored = sorted(claude_files & agents_files)
    for name in mirrored:
        if read(f"{CLAUDE}/{name}") != read(f"{AGENTS}/{name}"):
            problems.append(
                f"{AGENTS}/{name}: has drifted from {CLAUDE}/{name} — they are "
                f"the same skill served to two runtimes; copy one over the other")

    if not mirrored:
        problems.append(
            f"{CLAUDE} and {AGENTS} share no files — one of them moved or was "
            f"renamed, and this check would otherwise pass by having nothing "
            f"left to compare")

    for page, source, opening in COUNTED:
        params, failure = declared_parameters(source, opening)
        if failure:
            problems.append(failure)
            continue
        claim = CLAIM.search(read(page))
        if not claim:
            problems.append(
                f"{page}: no 'takes **N** parameters' line. That sentence is what "
                f"tells the reader the page is partial; without it the tour reads "
                f"as the whole API")
        elif int(claim.group(1)) != len(params):
            problems.append(
                f"{page}: says the initializer takes {claim.group(1)} parameters; "
                f"{source} declares {len(params)}")

    if problems:
        print("✗ skill docs disagree with the code they describe:")
        for problem in problems:
            print(f"    {problem}")
        return 1

    counts = " / ".join(
        str(len(declared_parameters(s, o)[0])) for _, s, o in COUNTED)
    print(f"✓ skill docs consistent — {len(mirrored)} files mirrored, "
          f"documented parameter counts ({counts}) match the initializers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
