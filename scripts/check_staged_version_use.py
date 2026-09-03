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
# Core included: the defect is not an App-layer speciality — `UpdatePolicy`'s
# staged-relaunch gate had it, five lines from a sibling that had it right.
SCANNED = [
    ROOT / "App" / "Sources",
    ROOT / "CLI" / "Sources",
    ROOT / "DuoUpdaterCore" / "Sources",
]

# Rule 1: a *displayed* staged version must be formatted. Interpolation is what
# marks a display site — logic passes the value as an argument or compares it,
# and those uses are correct and must not be touched (`actionableStaged`'s
# exact-string gate, the skip-version comparison, the relaunch handoff all
# compare against strings recorded elsewhere).
DISPLAY = re.compile(r"\\\(\s*staged\.version\s*\)")

# Rule 2: the announce-once ledger identifies a build, not a marketing version.
LEDGER = re.compile(r"ledger\.(?:isNew|record)\s*\([^)]*version:\s*([A-Za-z0-9_.]+)")
LEDGER_OK = "buildIdentity"

# Rule 3: the general shape. A marketing-first fallback is fine for display and
# wrong for a decision — `shortVersion ?? buildVersion` answers "1.0" for every
# build of an app that freezes its marketing string, so any comparison fed by it
# cannot discriminate. Thirteen sites got this wrong; `VersionSide` plus
# `VersionComparator.isNewer(_:than:)`/`isSame(_:as:)` is what replaced them.
MARKETING_FIRST = re.compile(
    r"(?:shortVersion|displayVersion)\s*\?\?\s*[\w.]*[Bb]uildVersion")
# `RemoteVersion.displayVersion` already hides that fallback one level down, so
# passing it into `VersionSide(marketing:)` is the same bug without a literal
# `??` for the rule above to see.
# `[\w.?]*` (not `[\w.]*`) because `result.remote?.displayVersion` is the
# standard way this file reaches a `RemoteVersion?` — the `?` of optional
# chaining is the natural spelling of the very site this rule exists to catch,
# and a class that excludes it lets that spelling straight through (#286).
# Known blind spot, not fixable with more character-class: `marketing:
# version` where `version` was assigned from `displayVersion` on an earlier
# line (the #235 bug's exact shape on main before it was fixed) is invisible
# to a single-line/single-statement regex — it needs cross-statement data
# flow, which is a job for a real dataflow check, not this lint.
DISPLAY_VERSION_AS_MARKETING = re.compile(
    r"VersionSide\s*\([^)]*marketing:\s*[\w.?]*displayVersion", re.DOTALL)
# A site where marketing-first IS correct because BOTH sides are marketing by
# construction opts out by name, on the line or anywhere in the comment block
# directly above it. A marker beats
# an allowlist of line numbers: it travels with the code when the line moves, and
# it makes the reason visible where the next reader is already looking.
ALLOW = "version-lint:allow-marketing-first"
# Enough lines to cover the reason written above the site — the marker is only
# useful if it can sit at the top of the paragraph that explains it.
ALLOW_LOOKBACK = 6
# What makes a marketing-first pick dangerous is a comparison in the same
# STATEMENT — which in Swift is routinely two or three lines away, because
# `if let a = ..., \n   cond` is the idiom these sites are written in. Looking at
# one line missed every real instance; the window is what makes the rule bite.
# `VersionComparator.` is unambiguous. A bare `==` is not: `route == .installer`
# sits three lines from a version pick in `InstallCoordinator.backUp` and has
# nothing to do with versions. Requiring a version-ish operand on the SAME line
# as the `==` keeps the rule pointed at version equality — a lint that cries wolf
# is a lint the next person switches off, which is the failure this whole file
# exists to prevent.
COMPARATOR_CALL = re.compile(r"VersionComparator\.")
EQUALITY = re.compile(r"[!=]=")
VERSION_TOKEN = re.compile(r"[Vv]ersion|[Bb]uild|versionSide")
COMPARISON_WINDOW = 3


def is_version_comparison(line):
    if COMPARATOR_CALL.search(line):
        return True
    return bool(EQUALITY.search(line) and VERSION_TOKEN.search(line))


def compares_near(lines, index):
    """Whether a version comparison appears within this statement's few lines.

    A window, because Swift's `if let a = ...,\n   cond` idiom puts the
    comparison two or three lines below the pick — looking at one line missed
    every real instance.
    """
    return any(is_version_comparison(lines[i])
               for i in range(index, min(index + COMPARISON_WINDOW, len(lines))))

# Rule 4: reading only the marketing half off disk to detect a change. The pair
# comes from one read (`readBundleVersions`); throwing the build away is what made
# four landing checks answer "nothing moved".
SHORT_READ = re.compile(r"readShortVersion(?:OffMain)?\s*\(")

# App/Sources has no test target, so pin the one wiring site that must tell Core
# when the scanner's build does not share the package source's namespace.
PACKAGE_RESTART_RESOLVE = re.compile(r"PackageRestartState\.resolve\s*\(")
DERIVED_BUILD_ARGUMENT = "buildIsDerived:"
PACKAGE_RESTART_WINDOW = 10

# The second such site (#285). It used to be `pruneStagedPackages` comparing
# `app.versionSide` against a staged package's with its own copy of the
# expression; both copies now go through `PackageRestartState.hasLanded`, so the
# anchor follows them there. `hasLanded` has no default for the flag, so a
# missing argument is a compile error rather than something a regex must catch —
# what is left for this rule is the argument being present and WRONG.
PRUNE_STAGED_ISSAME = re.compile(r"PackageRestartState\.hasLanded\s*\(")
PRUNE_STAGED_WINDOW = 6

# `buildIsDerived: false` written out in Sources. Legitimate in tests (they say
# which case they mean), never in shipping code: the flag exists precisely
# because the answer depends on the app, and hardcoding it is the same defect as
# omitting it — a landed Xcode/豆包 package that never lights the badge and never
# settles. This is what the `resolve` rule below could not see: it only checked
# that the argument was written at all.
DERIVED_BUILD_HARDCODED = re.compile(r"buildIsDerived:\s*false\b")


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
    display_hits, ledger_hits, compare_hits, read_hits = [], [], [], []
    display_marketing_hits = []
    package_restart_hits = []
    prune_staged_hits = []
    ledger_seen = 0
    marketing_seen = 0
    package_restart_seen = 0
    prune_staged_seen = 0
    files = list(swift_files())

    for path in files:
        rel = path.relative_to(ROOT)
        lines = path.read_text(encoding="utf-8").splitlines()
        source = "\n".join(lines)
        for match in DISPLAY_VERSION_AS_MARKETING.finditer(source):
            line = source.count("\n", 0, match.start()) + 1
            display_marketing_hits.append(
                f"{rel}:{line}: displayVersion passed as marketing")
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
            if MARKETING_FIRST.search(line):
                marketing_seen += 1
                allowed = ALLOW in line or any(
                    ALLOW in lines[i]
                    for i in range(max(0, n - 1 - ALLOW_LOOKBACK), n - 1))
                if compares_near(lines, n - 1) and not allowed:
                    compare_hits.append(f"{rel}:{n}: {line.strip()}")
            if SHORT_READ.search(line) and compares_near(lines, n - 1):
                read_hits.append(f"{rel}:{n}: {line.strip()}")
            if PACKAGE_RESTART_RESOLVE.search(line):
                package_restart_seen += 1
                call = "\n".join(lines[n - 1:n - 1 + PACKAGE_RESTART_WINDOW])
                if (DERIVED_BUILD_ARGUMENT not in call
                        or DERIVED_BUILD_HARDCODED.search(call)):
                    package_restart_hits.append(f"{rel}:{n}: {line.strip()}")
            if PRUNE_STAGED_ISSAME.search(line):
                prune_staged_seen += 1
                call = "\n".join(lines[n - 1:n - 1 + PRUNE_STAGED_WINDOW])
                if (DERIVED_BUILD_ARGUMENT not in call
                        or DERIVED_BUILD_HARDCODED.search(call)):
                    prune_staged_hits.append(f"{rel}:{n}: {line.strip()}")

    # Vacuity guard. A rule that matches nothing passes forever, which is worse
    # than no rule: it reports success while the thing it was written for has
    # been renamed out from under it. Both anchors below must still exist.
    if not files:
        print("✗ staged-version guard scanned no Swift files — paths moved?")
        return 1
    if marketing_seen == 0:
        print("\u2717 staged-version guard found no marketing-first version pick "
              "anywhere. Those are legitimate for DISPLAY and still exist, so zero "
              "matches means the spelling changed and rule 3 now guards nothing.")
        return 1
    if ledger_seen == 0:
        print("✗ staged-version guard found no `ledger.isNew/record(version:)` "
              "call at all. Either the nudge ledger was removed (delete rule 2) "
              "or it was renamed and this rule now guards nothing.")
        return 1
    if package_restart_seen == 0:
        print("✗ staged-version guard found no PackageRestartState.resolve call. "
              "Either the app wiring moved or this rule now guards nothing.")
        return 1
    if prune_staged_seen == 0:
        print("✗ staged-version guard found no PackageRestartState.hasLanded call. "
              "Either that wiring moved or was renamed, or this rule now guards "
              "nothing.")
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
    if compare_hits:
        print(f"\u2717 {len(compare_hits)} comparison(s) fed by a marketing-first "
              "version pick.")
        print("  `shortVersion ?? buildVersion` and `displayVersion` answer the same "
              "string for every build of an app that freezes its marketing version.")
        print("  Compare `VersionSide`s instead — VersionComparator.isNewer(_:than:) "
              "/ .isSame(_:as:).")
        for hit in compare_hits:
            print(f"    {hit}")
    if display_marketing_hits:
        print(f"✗ {len(display_marketing_hits)} `displayVersion` value(s) passed "
              "as `VersionSide.marketing`.")
        print("  `displayVersion` is marketing-first but falls back to a build; "
              "copy the source's `versionSide` instead.")
        for hit in display_marketing_hits:
            print(f"    {hit}")
    if read_hits:
        print(f"\u2717 {len(read_hits)} change-detector(s) reading only the marketing "
              "half off disk.")
        print("  `readBundleVersions` returns both from one read; use "
              "`readVersionSide` so the build can break the tie.")
        for hit in read_hits:
            print(f"    {hit}")
    if package_restart_hits:
        print(f"✗ {len(package_restart_hits)} PackageRestartState call(s) omit "
              "the derived-build namespace flag.")
        print("  Pass AppScanner.buildVersionIsOverridden(bundleID:) so a "
              "scanner-substituted build is not compared with a feed build.")
        for hit in package_restart_hits:
            print(f"    {hit}")
    if prune_staged_hits:
        print(f"✗ {len(prune_staged_hits)} PackageRestartState.hasLanded call(s) "
              "omit or hardcode the derived-build namespace flag.")
        print("  Pass buildIsDerived: AppScanner.buildVersionIsOverridden(bundleID:) "
              "so a scanner-substituted build is not compared with a staged package's.")
        for hit in prune_staged_hits:
            print(f"    {hit}")
    if (display_hits or ledger_hits or compare_hits or display_marketing_hits
            or read_hits or package_restart_hits or prune_staged_hits):
        return 1

    print(f"✓ version comparisons discriminate — {len(files)} files, "
          f"{ledger_seen} ledger call(s) keyed on the build, "
          f"{marketing_seen} marketing-first pick(s), all display-only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
