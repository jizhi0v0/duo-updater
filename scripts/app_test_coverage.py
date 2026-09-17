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
RAN = re.compile(r"Test ([A-Za-z0-9_]+)\([^)]*\)(?: with \d+ test cases?)? passed")

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
# the text with log lines cut out, and takes the union. The union adds no new way
# to invent a pass. Everything in it is a `Test name(…) passed` occurrence from
# one of the two texts. The stripped text was already trusted. The raw text adds only
# occurrences inside a timestamped log line, and a log line says that only if the
# test process itself logs a pass record naming a declared case. That exposure
# already existed for anything the tests print() to stdout, which carries no
# timestamp and was never stripped. None of the target's own NSLog calls writes
# such a string. A case that failed, or only started, still matches neither text.
#
# Not handled: both directions in one place — a record split by a log line that
# itself began inside another log line. Neither text rejoins that record; the
# case is reported as never run and a rerun clears it.
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
