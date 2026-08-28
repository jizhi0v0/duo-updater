#!/usr/bin/env python3
"""Guard the seam where `StagedSelfUpdate` is consumed.

Core holds the rules and is heavily tested; `App/Sources` is 13k lines with no
test target at all, so nothing executes it and the only failures that reach a
user are of one shape: **Core has the right rule and the caller does not use
it.** Two shipped bugs had exactly that shape, both found on 2026-08-28 after
Amp — which shipped ten builds as `1.0` in a day — made them visible:

  * every display site interpolated the bare marketing version, so a row, two
    tooltips, a notification and `duo install`'s refusal all read "1.0" when
    "1.0" was also what was running (`1.0 → 1.0` names no change);
  * `StagedNudgeLedger` was keyed on that same marketing string, so build 121
    was announced and builds 122–130 were all read as already-seen — the
    announce-once ledger became announce-never.

This is a LINT, not a test: it checks that the callers ask the right function,
never that the function is right. `RelaunchLineTests` and
`StagedNudgeLedgerTests` own the second half. Deliberately narrow — two named
rules about one type — because a general "no interpolation anywhere" rule would
flag the many sites that correctly interpolate a plain string and become noise
nobody reads.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCANNED = [ROOT / "App" / "Sources", ROOT / "CLI" / "Sources"]

# Rule 1: a *displayed* staged version must be formatted. Interpolation is what
# marks a display site — logic passes the value as an argument or compares it,
# and those uses are correct and must not be touched (`actionableStaged`'s
# exact-string gate, the skip-version comparison, the relaunch handoff all
# compare against strings recorded elsewhere).
DISPLAY = re.compile(r"\\\(\s*staged\.version\s*\)")

# Rule 2: the announce-once ledger identifies a build, not a marketing version.
LEDGER = re.compile(r"ledger\.(?:isNew|record)\s*\([^)]*version:\s*([A-Za-z0-9_.]+)")
LEDGER_OK = "buildIdentity"


# A *different* type also binds the name `staged`: `stagedPackage(for:)` returns
# a `StagedPackage` — a downloaded `.pkg` installer, not a self-update staged by
# the app's own updater. Its `version` is the version on offer, which
# `stagedPackage` requires to equal `remote?.displayVersion`, so it is a version
# the installed copy does NOT have and reads correctly on its own. Out of scope
# here rather than allow-listed line by line: an allowlist goes stale silently,
# a scope test keeps working when the lines move.
PACKAGE_BINDING = re.compile(r"\bstaged\s*=\s*stagedPackage\s*\(")
FUNC_START = re.compile(r"^\s*(?:@\w+\s+)*(?:public |private |internal |fileprivate )?"
                        r"(?:static |mutating )?func\s")


def swift_files():
    for root in SCANNED:
        yield from sorted(root.rglob("*.swift"))


def in_package_scope(lines, index):
    """Whether the `staged` in scope at `index` came from `stagedPackage(`.

    Walks back to the enclosing `func` and asks what bound the name there.
    """
    for i in range(index, -1, -1):
        if PACKAGE_BINDING.search(lines[i]):
            return True
        if FUNC_START.match(lines[i]):
            return False
    return False


def main() -> int:
    display_hits, ledger_hits = [], []
    ledger_seen = 0
    files = list(swift_files())

    for path in files:
        rel = path.relative_to(ROOT)
        lines = path.read_text(encoding="utf-8").splitlines()
        for n, line in enumerate(lines, 1):
            # `Log.` lines are diagnostics read by whoever is holding the log
            # beside the code, not text shown to a user. Left alone on purpose.
            if line.lstrip().startswith("Log."):
                continue
            if DISPLAY.search(line) and not in_package_scope(lines, n - 1):
                display_hits.append(f"{rel}:{n}: {line.strip()}")
            for m in LEDGER.finditer(line):
                ledger_seen += 1
                if not m.group(1).endswith(LEDGER_OK):
                    ledger_hits.append(f"{rel}:{n}: {line.strip()}")

    # Vacuity guard. A rule that matches nothing passes forever, which is worse
    # than no rule: it reports success while the thing it was written for has
    # been renamed out from under it. Both anchors below must still exist.
    if not files:
        print("✗ staged-version guard scanned no Swift files — paths moved?")
        return 1
    if ledger_seen == 0:
        print("✗ staged-version guard found no `ledger.isNew/record(version:)` "
              "call at all. Either the nudge ledger was removed (delete rule 2) "
              "or it was renamed and this rule now guards nothing.")
        return 1

    if display_hits:
        print(f"✗ {len(display_hits)} site(s) display a bare `staged.version`.")
        print("  It is a marketing string an app may keep across many builds, so "
              "this renders \"1.0\" against an installed \"1.0\".")
        print("  Use `result.stagedRelaunchLine(staged).to` (or `.from`).")
        for hit in display_hits:
            print(f"    {hit}")
    if ledger_hits:
        print(f"✗ {len(ledger_hits)} nudge-ledger call(s) keyed on something "
              "other than `buildIdentity`.")
        print("  Keying on the marketing version announces the first build and "
              "silently swallows every later one that shares it.")
        for hit in ledger_hits:
            print(f"    {hit}")
    if display_hits or ledger_hits:
        return 1

    print(f"✓ staged-version use is sound — {len(files)} files, "
          f"{ledger_seen} ledger call(s) keyed on the build")
    return 0


if __name__ == "__main__":
    sys.exit(main())
