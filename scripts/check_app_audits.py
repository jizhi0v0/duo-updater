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

3. **Evidence pointers go stale.** Audits used to end with
   "证据：`application-test/records/X.md`" — a path that stopped being tracked
   on 2026-08-14 and so resolved for exactly one person. The evidence now lives
   in the audit's own 「如何复验」 section; nothing should point back out.

Deliberately NOT checked: that every registry bundle id has an audit. 149 of
them do not, and turning a documentation backlog into a red build would only
teach people to skip the check.
"""
import os
import re
import sys

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
    src = "DuoUpdaterCore/Sources/DuoUpdaterCore/Sources"
    for name in os.listdir(src):
        if not name.endswith(".swift"):
            continue
        text = open(os.path.join(src, name), encoding="utf-8").read()
        ids.update(re.findall(r'bundleID:\s*"([^"]+)"', text))
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


def main():
    problems = []
    check_index(problems)
    check_links_resolve(problems)
    check_no_machine_state(problems)
    check_no_local_evidence_pointers(problems)
    check_filename_matches_bundle_id(problems, registry_bundle_ids())

    if problems:
        print("✗ app audits disagree with the rules that keep them publishable:")
        for p in problems:
            print(f"    {p}")
        return 1

    n = len(audit_files())
    print(
        f"✓ app audits consistent — {n} docs, all indexed, "
        "no machine inventory, no pointers into untracked evidence"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
