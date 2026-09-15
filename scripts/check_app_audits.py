#!/usr/bin/env python3
"""`docs/app-audits/` is the single maintained reference for how each app
publishes updates. This keeps it honest about three things that have each gone
wrong at least once.

1. **The index drifts.** `README.md` is hand-written; five audits had been
   sitting in the directory unlinked from it (found 2026-08-30). A doc nobody
   can navigate to is a doc that gets re-researched from scratch.

2. **Machine state leaks into a public repo.** `.gitignore` keeps `STATUS.md`,
   `plans/` and the rest of `docs/` local precisely because they are an
   inventory of whichever machine ran the scan — which apps are installed, at
   what version, on which channel. `docs/app-audits/` is the one carve-out, and
   it only stays safe while it carries facts about the *app* rather than about
   the *machine*. `issue-111-…md` had named seven installed apps in a public
   file for two days before this check existed.

   The same rule decides the wording: an audit says 「观测版本」, not
   「已安装版本」. The distinction is not cosmetic — "installed" invites the
   path, the channel and the "not installed here", which is exactly the
   inventory this check exists to keep out. Unified across the 14 audits that
   still said 「已安装版本」 on 2026-08-30, three of which had in fact carried
   a path or an installed/not-installed disclosure along with it.

3. **Evidence pointers go stale.** Audits used to end with
   "证据：`application-test/records/X.md`" — a path that stopped being tracked
   on 2026-08-14 and so resolved for exactly one person. The evidence now lives
   in the audit's own 「如何复验」 section; nothing should point back out.

4. **History moved out of recipe comments loses its way back.** Step 2 of the
   recipe refactor moves dated verification logs out of
   `Recipes/<family>.swift` into that family's audit under `## 历史与实测`,
   leaving `// History: docs/app-audits/<family>.md#历史与实测` in the code
   (convention: README.md, 「从 recipe 注释迁出的历史」). That pointer can go
   stale the same ways `check_engine_notes.py` lists for its own — the file is
   renamed, the file exists on the author's disk but was never tracked
   (`/docs/*` is gitignored outside the carve-outs, so `git ls-files`, not
   `os.path.exists`), the heading is reworded — plus two that belong to this
   convention: a pointer copied into the WRONG family's file (it resolves, to
   someone else's history), and a `## 历史与实测` nobody points at any more
   (history whose recipe comment was deleted or re-pointed: it reads as
   current to whoever opens the audit and is reachable from no code).

Deliberately NOT checked: that every registry bundle id has an audit. 149 of
them do not, and turning a documentation backlog into a red build would only
teach people to skip the check.
"""
import os
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recipe_families  # noqa: E402

AUD = "docs/app-audits"
INDEX = os.path.join(AUD, "README.md")

# Docs in this directory that are not per-app audits. Keep this short: anything
# added here is a doc the bundle-id check can no longer protect.
NON_APP = {"README.md", "issue-111-appcast-channel-population.md"}

# Phrases that describe the machine rather than the app. Each is a shape that
# actually appeared here, not a guess at what might.
MACHINE_STATE = [
    (r"/Users/", "an absolute home path"),
    (r"~/Applications/[A-Za-z]", "an install path on someone's machine"),
    (r"installed on this machine", "an installed-app inventory"),
    (r"本机(?:仅装|同时装|已装)", "an installed-app inventory"),
    (r"本机\s*`?/Applications/", "an install path on someone's machine"),
    # "not installed here" is machine state too — it says what someone's Mac
    # does NOT have, and the audit means "we took no evidence from an installed
    # copy", which is a fact about the audit.
    (r"(?:未在本机|本机未|本机没)(?:安装|装)", "whether an app is installed on someone's machine"),
    # The wording decision behind 观测版本 (see below) — an audit records what
    # was OBSERVED, and where the copy came from is beside the point.
    (r"已安装版本", "「已安装版本」 — audits say 「观测版本」; see check_version_wording"),
]


def audit_files():
    return sorted(
        f for f in os.listdir(AUD) if f.endswith(".md") and f != "README.md"
    )


# A markdown link target. `/` is allowed so that `./name.md` — which GitHub
# renders identically to `name.md` — is read as the link it is rather than
# reported as a missing one.
LINK = re.compile(r"\]\(([A-Za-z0-9._/-]+\.md)\)")


def links_in(path):
    """(line number, target) for every markdown link to a .md file."""
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        for target in LINK.findall(line):
            yield n, target


def check_index(problems):
    linked = {t.lstrip("./") for _, t in links_in(INDEX)}
    for f in sorted(set(audit_files()) - linked):
        problems.append(f"{AUD}/{f}: not linked from README.md")


def check_links_resolve(problems):
    """Every link in every audit, not just the index.

    The index check above only proves a file is REACHED. Audits also link to
    each other — org-mozilla-firefox.md and org-mozilla-thunderbird.md point at
    each other today — and renaming one used to break the other silently.
    """
    for f in audit_files() + ["README.md"]:
        path = os.path.join(AUD, f)
        for n, target in links_in(path):
            if not os.path.exists(os.path.join(AUD, target)):
                problems.append(f"{path}:{n}: links {target}, which does not exist")


def check_no_machine_state(problems):
    for f in audit_files() + ["README.md"]:
        path = os.path.join(AUD, f)
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            for pattern, what in MACHINE_STATE:
                if re.search(pattern, line):
                    problems.append(f"{path}:{n}: {what} — this repo is public")
                    break


def check_no_local_evidence_pointers(problems):
    # A path INTO the untracked records dir. The directory itself may be named
    # (the README explains where the raw sweeps live); a file inside it may not.
    for f in audit_files() + ["README.md"]:
        path = os.path.join(AUD, f)
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            if re.search(r"application-test/records/\S+\.md", line):
                problems.append(
                    f"{path}:{n}: points at a file in the untracked records dir; "
                    "fold the evidence into 「如何复验」 instead"
                )


def registry_bundle_ids():
    """Every bundle id the recipe registries name.

    Derived rather than listed, because a hand-kept list is the thing this
    script exists to stop. It is what lets the filename check accept Msty's
    dotless `MstyStudio` without also accepting every backticked word: a
    reverse-DNS shape is a good heuristic, registry membership is a fact.
    """
    ids = set()
    # The registry entries live in `Recipes/` and `Resources/Recipes/`, one file
    # per app family. `Sources/` is still read so a `bundleID:` written next to a
    # registry is not missed.
    for src, extension, pattern in (
            ("DuoUpdaterCore/Sources/DuoUpdaterCore/Sources", ".swift", r'bundleID:\s*"([^"]+)"'),
            ("DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes", ".swift", r'bundleID:\s*"([^"]+)"'),
            (RECIPE_DATA, ".json5", r'"bundleID":\s*"([^"]+)"')):
        for name in os.listdir(src):
            if not name.endswith(extension):
                continue
            if extension == ".json5" and not recipe_families.DATA_FILE.fullmatch(name):
                continue  # not a family; check_recipe_json5.py refuses it
            text = open(os.path.join(src, name), encoding="utf-8").read()
            ids.update(re.findall(pattern, text))
    return {i.replace(".", "-").lower() for i in ids}


def check_filename_matches_bundle_id(problems, registry):
    for f in audit_files():
        if f in NON_APP:
            continue
        stem = f[:-3].lower()
        text = open(os.path.join(AUD, f), encoding="utf-8").read()
        quoted = {
            m.replace(".", "-").lower()
            for m in re.findall(r"`([A-Za-z][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-_]+)*)`", text)
        }
        if stem not in quoted:
            problems.append(
                f"{AUD}/{f}: filename names no bundle id the document mentions"
            )
        elif "-" not in stem and stem not in registry:
            # Dotless stem that no registry entry backs. `MstyStudio` is real;
            # `changelog.md` mentioning `changelog` is a stray doc sneaking in
            # through a check meant to keep it out.
            problems.append(
                f"{AUD}/{f}: dotless filename matches no registry bundle id — "
                "if this is not an app audit, add it to NON_APP"
            )


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The fixed heading moved recipe history lives under. Compared as a whole line:
# the pointer's `#历史与实测` anchor is what GitHub derives from exactly this
# heading, so a reworded one ("## 历史与实测（旧）") breaks the link.
HISTORY_HEADING = "## 历史与实测"

SWIFT_ROOTS = [
    "DuoUpdaterCore/Sources", "DuoUpdaterCore/Tests",
    "App/Sources", "App/Tests",
    "CLI/Sources", "CLI/Tests",
]
RECIPES = "DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes"
# The two files in `Recipes/` that are not a family, the same set
# `AppRecipeIndexTests.infrastructure` names. A pointer in one of them has no
# family to be wrong about, and counting them would overstate the family total.
RECIPES_INFRASTRUCTURE = {"AppRecipeSet.swift", "AppRecipeIndex.swift"}
# Families written as data, one `<family>.json5` each (`RecipeFamilyFile`). Their
# comments are whole `//` lines, read exactly like a Swift family's. What counts as
# one is `recipe_families.py`'s answer.
RECIPE_DATA = recipe_families.RECIPE_DATA

# One line by convention (README.md). Anything after the anchor is prose, so a
# trailing period or backtick does not change what is being pointed at.
HISTORY_POINTER = re.compile(
    re.escape(AUD) + r"/([A-Za-z0-9._-]+\.md)#" + re.escape(HISTORY_HEADING[3:]))


def tracked_audits():
    """Audit paths as `git clone` will see them — see check_engine_notes.py's
    `tracked_files` for why existence on this disk is not the question."""
    out = subprocess.run(
        ["git", "ls-files", AUD + "/"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    return {p for p in out.splitlines() if p.endswith(".md")}


def has_history_heading(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return any(line.rstrip("\n") == HISTORY_HEADING for line in f)


def check_history_pointers(problems):
    """Every `docs/app-audits/<file>.md#历史与实测` in a Swift comment, or in a
    `.json5` recipe family's comment, resolves, sits in the family it names, and
    every history section is pointed at.

    Returns (Swift files scanned, family files scanned, of which .json5) for the
    vacuity gate: a moved or renamed source root would otherwise turn all of this
    into a silent pass.
    """
    tracked = tracked_audits()
    recipes_dir = os.path.join(ROOT, RECIPES)
    data_dir = os.path.join(ROOT, RECIPE_DATA)
    pointed = set()
    scanned = families = data_families = 0
    for root in SWIFT_ROOTS:
        base = os.path.join(ROOT, root)
        if not os.path.isdir(base):
            continue
        for dirpath, _, filenames in os.walk(base):
            if ".build" in dirpath.split(os.sep):
                continue
            for name in sorted(filenames):
                is_data = (dirpath == data_dir and recipe_families.DATA_FILE.fullmatch(name) is not None
                           and not os.path.islink(os.path.join(dirpath, name)))
                if not name.endswith(".swift") and not is_data:
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT)
                scanned += not is_data
                in_recipes = is_data or (os.path.dirname(path) == recipes_dir
                                         and name not in RECIPES_INFRASTRUCTURE)
                families += in_recipes
                data_families += is_data
                with open(path, encoding="utf-8", errors="replace") as f:
                    lines = f.read().splitlines()
                for n, line in enumerate(lines, 1):
                    if not line.lstrip().startswith("//"):
                        continue
                    for m in HISTORY_POINTER.finditer(line):
                        target = m.group(1)
                        full = f"{AUD}/{target}"
                        where = f"{rel}:{n}"
                        pointed.add(full)
                        if full not in tracked:
                            reason = (
                                "does not exist"
                                if not os.path.exists(os.path.join(ROOT, full))
                                else "exists on disk but is not tracked by git "
                                     "(docs/* is gitignored by default — check "
                                     "the carve-out in .gitignore)")
                            problems.append(
                                f"{where}: history pointer names `{full}`, which {reason}")
                        elif not has_history_heading(full):
                            problems.append(
                                f"{where}: history pointer names `{full}`, which has "
                                f"no line reading exactly `{HISTORY_HEADING}`")
                        family = os.path.splitext(name)[0]
                        if in_recipes and target != f"{family}.md":
                            problems.append(
                                f"{where}: history pointer names `{target}` inside the "
                                f"`{family}` family — a family's history goes to "
                                f"`{AUD}/{family}.md`")
    for full in sorted(tracked):
        if full not in pointed and has_history_heading(full):
            problems.append(
                f"{full}: has `{HISTORY_HEADING}` but no Swift or recipe .json5 comment points at it "
                f"(expected `// History: {full}#{HISTORY_HEADING[3:]}`)")
    return scanned, families, data_families


def main():
    problems = []
    check_index(problems)
    check_links_resolve(problems)
    check_no_machine_state(problems)
    check_no_local_evidence_pointers(problems)
    check_filename_matches_bundle_id(problems, registry_bundle_ids())
    scanned, families, data_families = check_history_pointers(problems)

    # Same floor as check_engine_notes.py for the Swift files. For the families
    # the family rule keys on, a floor says nothing about WHICH were read, so the
    # count must equal the goldens, one per family the binary loads
    # (recipe_families.py): a directory that moved, or a family the walk misses,
    # would otherwise quietly leave its pointers unchecked.
    mismatch = recipe_families.reconcile(
        pathlib.Path(ROOT), families, f"recipe family files scanned ({data_families} .json5)")
    if scanned < 100:
        print(f"✗ history pointers: only {scanned} Swift files scanned — too few to be "
              "a real run", file=sys.stderr)
        return 1
    if mismatch:
        print(f"✗ history pointers: {mismatch} (did {RECIPES} or {RECIPE_DATA} move?)",
              file=sys.stderr)
        return 1

    if problems:
        print("✗ app audits disagree with the rules that keep them publishable:")
        for p in problems:
            print(f"    {p}")
        return 1

    n = len(audit_files())
    print(
        f"✓ app audits consistent — {n} docs, all indexed, "
        "no machine inventory, no pointers into untracked evidence, "
        f"history pointers resolve ({scanned} Swift files, {families} families, "
        f"{data_families} of them .json5)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
