#!/usr/bin/env python3
"""Report which declared App test cases did not run.

Compares the NAMES of the cases that executed against the names declared in the
sources — not two totals. Totals were wrong three times:

  * Reading xcodebuild's run summary passed with a case `.disabled()`, because
    swift-testing's summary counts the cases it knows about, not the ones it ran.
  * Counting per-case log lines against a count of declarations broke when
    `@Test(.disabled("…"))` sat on its own line — the repo's prevailing style,
    and long reasons wrap — because that shrank BOTH sides and the gate
    cancelled itself out.
  * The same count would fail a fully green run on the first parameterized case,
    whose per-case line reads `Test foo(_:) passed`, with no empty parens, while
    its declaration still counted.

Names are immune to all three: a case that stops running stops appearing,
however it is declared and however many times it runs.

TWO SOURCES FOR "WHICH NAMES RAN", IN ORDER OF PREFERENCE
=========================================================
1. The .xcresult bundle xcodebuild writes (`--result-bundle`). Structured, one
   node per case, and NOT subject to the console interleaving described at
   length below. This is the source whenever the bundle is readable.
2. The console log. Kept because the bundle depends on `xcrun xcresulttool`
   and on a schema Apple versions independently of this repo; if that breaks,
   a working gate on torn text beats no gate.

Why 1 was added on 2026-09-20: CI run 35492361595 failed this gate with
`theClientRequirementIsPinnedForATeam` reported as never run, on a commit
touching nothing under App/. xcodebuild exited 0; only this gate objected, and
the next run on the same branch passed. That case is a pure string comparison —
it cannot "not run" for a real reason. It was the console interleaving.
`scripts/sweep_app_test_coverage.py` enumerates the tear shapes: the console
parser recovers 85.8% of 895200 torn texts, with every miss in the two
interleaving orderings named under SPLICED_LOG_LINE. It cannot be pushed much
higher — measured 2026-09-20, three candidate repairs (stop the log-line cut at
a marker; cut only the timestamp header; both) moved recall from 86.2% to 86.3%
on 179040 torn texts built from one pass record against all ten log fixtures.
Closing the rest means allowing text between `)` and `passed` that a log line
could have written, which is how a torn non-passing record borrows a verdict it
never earned, so it was not done. The bundle sidesteps the whole question.

Prints three lines:
    "<declared> <ran>"
    "<space-separated names never seen>"
    "<source>"   — `result-bundle` or `console-log`
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys

# Two shapes, both measured from real logs rather than assumed:
#
#   Test foo() passed after 0.001 seconds.
#   Test foo(_:) with 2 test cases passed after 0.002 seconds.
#
# So the parens are not always empty (a parameterized case bakes its labels into
# the name) AND the word `passed` is not always adjacent to them. A pattern that
# required either one failed a fully green run.
#
# Occurrences rather than whole lines, and no `^` anchor: xcodebuild prefixes
# some lines with an `XCTestOutputBarrier` token — sometimes torn mid-token —
# and swift-testing emits a U+200B, so an anchored match dropped one real case
# out of eight on a measured run.
#
# The pass marker must sit right before `Test`, because the log-line repair below
# matches on text that interleaved writers glued together, and without it the
# name and the `passed` could come from different writers (see "What this does
# and doesn't guarantee").
#
# The symbols, from Sources/Testing/Events/Recorder/Event.Symbol.swift on
# swiftlang/swift-testing release/6.4.0 (Xcode 27 ships Swift 6.4.0):
#
#                              unicodeCharacter   SF Symbols (private use)
#   pass                       ✔ U+2714           U+10105B
#   pass with known issues     ━ U+2501           U+100882
#   default (started)          ◇ U+25C7           U+1007C8
#   fail                       ✘ U+2718           U+100884
#   skip (skipped, cancelled)  ➜ U+279C           U+10065F
#
# The SF Symbols column is used when SWT_SF_SYMBOLS_ENABLED is set true, or
# when it's unset and /Library/Fonts/SF-Pro.ttf exists (ABI/EntryPoints/
# EntryPoint.swift, same branch). ANSI mode is on for a TTY and also for a pipe
# (`swift test` reads the test process through one), and in SF Symbols mode it
# adds a second space after the glyph. Hence one or two spaces.
#
# What was measured on 2026-09-17 (Xcode 27.0, 27A266a), running `make test`
# with SWT_SF_SYMBOLS_ENABLED=1:
#
#   * The SwiftPM half printed `U+10105B  Test …` with two spaces, for all 3483
#     pass records. A `✔`-only marker would have matched none of them.
#   * xcodebuild does not pass a plain exported variable to xctest; it was
#     absent from xctest's environment. TEST_RUNNER_SWT_SF_SYMBOLS_ENABLED=1
#     does get SWT_SF_SYMBOLS_ENABLED=1 there (`man xcodebuild`, TEST_RUNNER_<VAR>),
#     yet the App-test log still printed `✔ Test` with one space for all 51
#     cases. So the output this gate reads was not seen to change. Whether an
#     installed SF-Pro.ttf changes it isn't tested (none here), but per
#     EntryPoint.swift the font only matters when the variable is unset. The
#     SF markers are defence, not a measured need.
#
# Not matched, each a false red:
#
#   * With color on (TERM set, as in a terminal), swift-testing wraps the
#     marker in ANSI color codes. No App-test log has had one.
#   * Before swiftlang/swift-testing#1585 (merged 2026-02-24, e.g. release/6.2),
#     a pass with known issues printed `✘` (SF Symbols U+100883), the failure
#     glyph, so it can't be added without letting failures through. On such a
#     toolchain a case that passes with a known issue is reported as never
#     run. No App test uses withKnownIssue. Whether an older toolchain ever
#     runs this gate is UNVERIFIED.
#
# Measured 2026-09-17 on the 70 logs then under /tmp/duo-app-tests-*: every
# pass occurrence read `✔ Test`, and the U+200B or torn barrier sat before the
# marker, never between it and `Test`. Those logs are transient (the directory
# is reclaimed), so this can't be re-run.
RAN = re.compile(r"[✔━\U0010105B\U00100882] {1,2}Test ([A-Za-z0-9_]+)\([^)]*\)(?: with \d+ test cases?)? passed")

# A log line the test process wrote to stderr (NSLog, or os_log echoed because
# xcodebuild runs tests with OS_ACTIVITY_DT_MODE) interleaves with swift-testing's
# records mid-line, in either direction. Both are measured, not assumed:
#
# 1. The log line lands INSIDE a record and splits it across two lines
#    (app-tests-16030.log, 2026-09-13):
#
#      ✔ Test aCopyTha2026-09-13 19:21:20.342690+0800 xctest[16059:13752262] [logging-persist] cannot open file …
#      tBecameABetaReadsTheStore() passed after 0.007 seconds.
#
#    The split name matches nothing. Cutting the log line out, newline included,
#    rejoins the record.
#
# 2. The record lands INSIDE a log line, and the rest of the log message follows
#    on the next line (app-tests-781.log, 2026-09-17):
#
#      2026-09-17 17:08:17.095680+0800 xctest[1112:8721793] duo-helper: reje✔ Test aFailedCheckKeepsItsChannelAcrossARescan() passed after 0.004 seconds.
#      cted connection — no client requirement is installed on this listener …
#
#    Here the record is intact, but cutting the log line out cuts it out too.
#
# Either way a case that passed was reported as never run. HelperPeerGateTests'
# code-signing checks make Security and libxpc log, and the gate NSLogs its
# rejections; with that suite disabled the same run printed no such lines at all.
#
# No single text serves both, so `ran_cases` matches RAN on the raw text AND on
# the text with log lines cut out, and takes the union.
#
# What this does and doesn't guarantee.
#
# Both texts are glued together from several writers, so a match is not
# automatically one record. Before the marker was required, both texts invented
# passes (found in adversarial review of #716):
#
#   raw:      `◇ Test foo(`, then a log line ending in `probe (ok) passed⏎`, then
#             `) started.⏎`. `[^)]*` runs through the log line and counts foo.
#   stripped: record head `◇ Test foo(`, log head, record tail `) started.⏎`, log
#             tail `) passed⏎`. Cutting the log line out, through the record's
#             newline, leaves `◇ Test foo() passed`.
#
# What holds now: a name is counted only where one of the four pass markers
# and `Test ` sit directly before it. swift-testing prints that prefix in two
# places. One is the pass record itself. The other is a known issue being
# recorded (`━ Test foo() recorded a known issue at …`), which happens even if
# the case fails later. Whole, that record doesn't match: its verb isn't
# `passed`. Torn, with a log line supplying `) passed`, it can count a case that
# then fails. That's harmless to the gate, because a failing case already fails
# xcodebuild and app-tests.sh stops there, before the gate reads the log.
#
# A timestamped log line can't start inside `✔ Test name(`: its first `-` fits
# nowhere in it. Cutting whole log lines out can only rejoin pieces around that
# prefix. So a case that failed, started, was skipped or was cancelled is counted
# only if (a) it recorded a known issue, as above, or (b) text the test process
# wrote itself (a log message, or print() to stdout, which is never stripped)
# supplies part of a pass prefix at the exact point where a record was torn.
# Once the prefix is real, what follows it can't change whose name it is, so
# the parens stay `[^)]*`. A single-line grep of App/ and DuoUpdaterCore/Sources
# finds no log or print call that writes `✔` or `━`.
#
# Swept by brute force. The original sweep (2026-09-17) was not committed, "so
# the numbers can't be re-run from this repo" — and that is exactly what made
# the 2026-09-20 false red expensive to classify. It is now
# `scripts/sweep_app_test_coverage.py`, run in quick mode by
# `scripts/test_app_test_coverage.py` on every `make test`.
#
# Re-run 2026-09-20 on the committed sweep, which tears each writer at every
# point into at most two pieces and interleaves every way:
#
#   * SAFETY, the property that matters: 1286322 torn texts over 5 non-pass
#     records x 10 log lines (including messages ending `) passed`, `_:) passed`,
#     `a() passed`, and whole `✔ Test ` / `━ Test foo(` fragments), plus 500000
#     three-writer texts that put a REAL `✔` from another case's pass record on
#     hand. Zero false passes in every configuration.
#   * RECALL: 85.8% of 895200 torn texts recovered, and every miss falls in one
#     of two interleaving orderings — `log|record|log|record` and
#     `record|log|record|log`, i.e. the ones where the log line's own newline
#     arrives after a piece of the record. The other four orderings are 100%.
#
# The 2026-09-17 sweep's own findings, on its own corpus:
#
#   * one non-pass record (started / failed / cancelled / parameterized) and
#     one log line whose message is `probe (ok) passed`, `check(x) passed`,
#     `) passed`, `_:) passed`, `) with 2 test cases passed`, `a() passed`,
#     `cted connection`, `✔ `, `✔ Test ` or `━ Test foo(`: no false pass. The
#     marker-less pattern gave false passes for every message ending in
#     `passed`;
#   * a started or failed record, a log line ending in `probe (ok) passed` or
#     `) passed`, and a real pass record for another case (so a `✔` from a
#     different record is on hand), all three torn: no false pass, against
#     457618 interleavings with the marker-less pattern;
#   * the one message that does get a non-passing case counted is a log line
#     that is itself a whole `✔ Test foo() passed`. That's the exposure
#     described above, not a splice;
#   * bounding the parens to argument labels closed no false pass and missed
#     168 more interleavings of a real pass record.
#
# More pieces per writer, or two records tearing each other in more than two
# pieces, were not swept.
#
# What stays unhandled is a false red: a case that passed but is reported as never run.
# That's the safe direction, and the interleaving is timing-dependent (the
# 2026-09-17 false red passed on an immediate rerun). The repair covers a record
# that is whole in the raw text (shape 2), and one whose pieces are separated
# only by whole log lines, each cut from its timestamp to its first newline
# (shape 1). One log line and one record, each written in two pieces, are
# already enough to beat it, and both have been seen writing that way (shape 1
# splits a record, shape 2 splits an NSLog line). With one record and one log
# line, each in two pieces, these are missed unless the tear happens to leave
# the whole occurrence in one piece:
#
#   * log head, record head, log tail, record tail: the record's head lands
#     inside a log line whose tail comes before the record's. That includes a
#     record whose head lands inside a log line and whose tail is on the next
#     line, when the tear is in the prefix. Torn inside the parens, `[^)]*`
#     crosses the newline and it counts;
#   * record head, log head, record tail, log tail: the record's name or tail
#     is split by a log line that has not ended yet, so cutting that line out,
#     up to the record's newline, cuts the tail out with it;
#   * a record split by a log message that itself spans lines, so its second
#     line is left between the pieces.
#
# Requiring the marker adds tears between it and `Test` to the first two. The
# same uncommitted sweep counted 2181 missed interleavings in each of those
# orderings, against 2013 without the marker.
#
# Whether any of these occur in practice is UNVERIFIED. Of the 70 logs under
# /tmp/duo-app-tests-* on 2026-09-17 (transient, as above), five held a torn
# pass record, each shape 1 or shape 2, and all five are recovered.
#
# The log-line shape is strict — a timestamp with microseconds and zone, then
# `name[pid:tid] ` — so a test's own output can't be mistaken for it.
SPLICED_LOG_LINE = re.compile(
    r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+[+-]\d{4} [^\s\[]+\[\d+:[0-9a-fA-F]+\] [^\n]*\n"
)
# swift-testing writes one node per case into xcodebuild's .xcresult, which is a
# database rather than a byte stream, so no amount of concurrent logging can tear
# a record in it. `xcrun xcresulttool get test-results tests` renders it as JSON.
#
# Measured 2026-09-20, Xcode 27.0 (27A266a), xcresulttool 25115 / schema 0.4.0,
# on this repo's DuoUpdaterAppTests: 51 `Test Case` nodes for 51 declared cases,
# all `"result": "Passed"`. A parameterized case is ONE node carrying the same
# `foo(_:)` spelling the console prints, with its inputs as child `Arguments`
# nodes — so the same "strip the parens" rule recovers the declared name.
#
# `Skipped` MUST be excluded, and this is the whole trap. Measured the same day
# by putting `.disabled("mutation probe")` on `theClientRequirementIsPinnedForATeam`
# and rerunning: the bundle still held 51 `Test Case` nodes — 50 `Passed`, 1
# `Skipped`, the disabled one present by name. Counting nodes, or counting any
# node regardless of result, would pass a run in which that case did not execute.
# That is verbatim the first of the three ways a count already got this wrong
# (see the module docstring), reintroduced through a new door.
#
# Everything else — `Passed`, `Failed`, `Expected Failure` — did execute, so it
# counts. A `Failed` case fails xcodebuild and `app-tests.sh` exits before it
# ever reaches this gate, so admitting it here changes nothing in practice.
DID_NOT_RUN = {"Skipped"}


def ran_cases_from_result_bundle(bundle: pathlib.Path) -> set[str] | None:
    """Names that executed, per the .xcresult, or None if it can't be read.

    None means "ask the console log instead" — never "nothing ran". A missing
    xcresulttool, an unreadable bundle, a schema this doesn't understand and a
    bundle holding zero cases all return None, because none of them is evidence
    about the tests: they are evidence about the tooling. A genuinely empty run
    still fails the gate, because the console fallback also finds nothing.
    """
    if not bundle.is_dir() or shutil.which("xcrun") is None:
        return None
    try:
        proc = subprocess.run(
            # No --compact: this output is parsed, never read, so the flag
            # buys nothing and is one more thing a future toolchain could
            # reject — and a rejection here demotes the run to the console
            # parser this gate exists to stop depending on. `.github/workflows/
            # ci.yml` invokes the same subcommand without it.
            ["xcrun", "xcresulttool", "get", "test-results", "tests",
             "--path", str(bundle)],
            capture_output=True, text=True, encoding="utf-8", timeout=300)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        report = json.loads(proc.stdout)
    except (json.JSONDecodeError, ValueError):
        return None

    return names_from_test_report(report) or None


def names_from_test_report(report: object) -> set[str]:
    """Case names that executed, from a parsed `get test-results tests` report.

    Split out from the subprocess call so the Skipped rule — the one that keeps
    this from reintroducing the `.disabled()` blind spot — can be tested without
    an Xcode toolchain.
    """
    names: set[str] = set()

    def walk(node: object) -> None:
        if not isinstance(node, dict):
            return
        if node.get("nodeType") == "Test Case":
            # `aCase()` / `aCase(_:)` -> `aCase`. Same shape as the console.
            match = re.match(r"([A-Za-z0-9_]+)\(", str(node.get("name", "")))
            if match and node.get("result") not in DID_NOT_RUN:
                names.add(match.group(1))
        for child in node.get("children", []) or []:
            walk(child)

    if isinstance(report, dict):
        for node in report.get("testNodes", []) or []:
            walk(node)
    return names


FUNC = re.compile(r"\bfunc\s+([A-Za-z0-9_]+)\s*\(")


def ran_cases(text: str) -> set[str]:
    # Union of both texts: see the comment above SPLICED_LOG_LINE.
    return set(RAN.findall(text)) | set(RAN.findall(SPLICED_LOG_LINE.sub("", text)))


def declared_cases(root: pathlib.Path) -> set[str]:
    names: set[str] = set()
    for path in sorted(root.rglob("*.swift")):
        pending = False
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            # Skip comments. This suite documents its own mutations in prose
            # that names `@Test`, which a text scan would otherwise read as a
            # declaration.
            if stripped.startswith("//"):
                continue
            if "@Test" in stripped:
                pending = True
            funcs = FUNC.findall(stripped)
            if funcs:
                if pending:
                    names.update(funcs)
                pending = False
    return names


def main() -> int:
    args = sys.argv[1:]
    bundle: pathlib.Path | None = None
    if "--result-bundle" in args:
        i = args.index("--result-bundle")
        bundle = pathlib.Path(args[i + 1])
        del args[i:i + 2]
    log, tests = pathlib.Path(args[0]), pathlib.Path(args[1])
    if not log.is_file() or not tests.is_dir():
        print("0 0")
        print("")
        print("none")
        return 1

    source = "result-bundle"
    ran = ran_cases_from_result_bundle(bundle) if bundle is not None else None
    if ran is None:
        source = "console-log"
        # UTF-8 explicitly: every marker is non-ASCII, and the locale's encoding
        # (ISO8859-1, or US-ASCII under LC_ALL=C with PYTHONUTF8=0) either stops
        # them matching or fails on the Swift sources.
        ran = ran_cases(log.read_text(encoding="utf-8", errors="replace"))

    declared = declared_cases(tests)
    print(f"{len(declared)} {len(ran & declared)}")
    print(" ".join(sorted(declared - ran)))
    print(source)
    return 0


if __name__ == "__main__":
    sys.exit(main())
