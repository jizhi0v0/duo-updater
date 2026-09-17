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

Prints "<declared> <ran>" then a space-separated list of names never seen.
"""
import pathlib
import re
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
# and doesn't guarantee"). swift-testing prints `✔` for a pass and `━` for a pass
# with known issues; a case that started is `◇`, a failure `✘`, a cancellation
# `➜` (Sources/Testing/Events/Recorder/Event.Symbol.swift in
# swiftlang/swift-testing). All 3563 pass occurrences in the 70 logs under
# /tmp/duo-app-tests-* on 2026-09-17 read `✔ Test`; the U+200B or torn barrier
# sits before the marker, never between it and `Test`.
RAN = re.compile(r"[✔━] Test ([A-Za-z0-9_]+)\([^)]*\)(?: with \d+ test cases?)? passed")

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
# What holds now: a name is counted only where `✔ Test ` or `━ Test ` sits
# directly before it, and swift-testing prints that prefix only for a case that
# passed. A timestamped log line can't start inside `✔ Test name(`: its first
# `-` fits nowhere in it. Cutting whole log lines out can only rejoin pieces
# around that prefix. So a case that failed, started or was cancelled is counted
# only if text the test process wrote itself (a log message, or print() to
# stdout, which is never stripped) supplies part of the `✔ Test name(` prefix at
# the exact point where a record was torn. Once the prefix is real, what follows
# it can't change whose name it is, so the parens stay `[^)]*`. Bounding them
# closed no false pass in the sweep below and added 168 missed interleavings.
# A single-line grep of App/ and DuoUpdaterCore/Sources finds no log or print
# call that writes `✔` or `━`.
#
# Checked by brute force on 2026-09-17, with each writer torn at every point
# into at most two pieces and interleaved every way:
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
#     457618 interleavings before;
#   * the one message that does get a non-passing case counted is a log line
#     that is itself a whole `✔ Test foo() passed`. That's the exposure
#     described above, not a splice.
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
# Requiring the marker adds tears between it and `Test` to the first two.
# Brute force counts 2181 missed interleavings in each of those orderings,
# against 2013 without the marker.
#
# Whether any of these occur in practice is UNVERIFIED. Of the 70 logs under
# /tmp/duo-app-tests-* on 2026-09-17, five held a torn pass record, each shape 1
# or shape 2, and all five are recovered.
#
# The log-line shape is strict — a timestamp with microseconds and zone, then
# `name[pid:tid] ` — so a test's own output can't be mistaken for it.
SPLICED_LOG_LINE = re.compile(
    r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+[+-]\d{4} [^\s\[]+\[\d+:[0-9a-fA-F]+\] [^\n]*\n"
)
FUNC = re.compile(r"\bfunc\s+([A-Za-z0-9_]+)\s*\(")


def ran_cases(text: str) -> set[str]:
    # Union of both texts: see the comment above SPLICED_LOG_LINE.
    return set(RAN.findall(text)) | set(RAN.findall(SPLICED_LOG_LINE.sub("", text)))


def declared_cases(root: pathlib.Path) -> set[str]:
    names: set[str] = set()
    for path in sorted(root.rglob("*.swift")):
        pending = False
        for line in path.read_text().splitlines():
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
    log, tests = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    if not log.is_file() or not tests.is_dir():
        print("0 0")
        print("")
        return 1
    ran = ran_cases(log.read_text(errors="replace"))
    declared = declared_cases(tests)
    print(f"{len(declared)} {len(ran & declared)}")
    print(" ".join(sorted(declared - ran)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
