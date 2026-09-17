#!/usr/bin/env python3
"""Regression tests for `app_test_coverage`. Run by `make test`.

    python3 scripts/test_app_test_coverage.py

The fixtures are lines copied from real `scripts/app-tests.sh` logs, where a
stderr log line from the test process and a swift-testing record interleaved
mid-line and the gate reported a passing case as never run: on 2026-09-13 the log
line landed inside the record, on 2026-09-17 the record landed inside the log
line. Every case names the mutation it catches.
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import app_test_coverage as atc  # noqa: E402

# os_log echo from Security, spliced mid-name (app-tests-16030.log).
SPLIT_BY_OS_LOG = (
    "✔ Test aCopyTha2026-09-13 19:21:20.342690+0800 xctest[16059:13752262] "
    "[logging-persist] cannot open file at line 53009 of [8fa8248e30]\n"
    "tBecameABetaReadsTheStore() passed after 0.007 seconds.\n"
)

# NSLog from the helper gate, spliced mid-name (app-tests-12802.log).
SPLIT_BY_NSLOG = (
    "✔ Test aWrappedBetaIsRetaggedFromTheStoreItRe2026-09-13 19:19:10.527912+0800 "
    "xctest[12903:13741876] duo-helper: rejected connection — no client requirement "
    "is installed on this listener\n"
    "ad() passed after 0.005 seconds.\n"
)

# The reverse: a whole record spliced into the tail of an NSLog line, the rest of
# the message on the next line (app-tests-781.log, 2026-09-17).
RECORD_INSIDE_NSLOG = (
    "2026-09-17 17:08:17.095680+0800 xctest[1112:8721793] duo-helper: reje"
    "✔ Test aFailedCheckKeepsItsChannelAcrossARescan() passed after 0.004 seconds.\n"
    "cted connection — no client requirement is installed on this listener\n"
)

# A log line on its own line, between intact records — must change nothing.
STANDALONE = (
    "✔ Test aThreeDayFloorReadsInDays() passed after 0.003 seconds.\n"
    "2026-09-13 19:21:38.379184+0800 xctest[16965:13755191] [logging-persist] cannot open file\n"
    "✔ Test anEmptyStoreIsNotTreatedAsFullyCovered() passed after 0.002 seconds.\n"
)


class SplicedLogLines(unittest.TestCase):
    """Mutation: make `ran_cases` match `RAN` on the raw text only (drop the
    `SPLICED_LOG_LINE.sub` half) → both split cases come back empty.
    Mutation: make it match on the stripped text only (drop the raw half) → the
    record inside the NSLog line is cut out with it and comes back empty.
    Mutation: loosen `SPLICED_LOG_LINE` to any text up to a newline (e.g.
    `r"[^\\n]*\\n"`) → the split record's first half is cut out too, and both
    split cases come back empty."""

    def test_a_record_split_by_os_log_is_rejoined(self):
        self.assertEqual(atc.ran_cases(SPLIT_BY_OS_LOG), {"aCopyThatBecameABetaReadsTheStore"})

    def test_a_record_split_by_nslog_is_rejoined(self):
        self.assertEqual(atc.ran_cases(SPLIT_BY_NSLOG), {"aWrappedBetaIsRetaggedFromTheStoreItRead"})

    def test_a_record_inside_an_nslog_line_is_kept(self):
        self.assertEqual(atc.ran_cases(RECORD_INSIDE_NSLOG),
                         {"aFailedCheckKeepsItsChannelAcrossARescan"})

    def test_a_standalone_log_line_changes_nothing(self):
        self.assertEqual(atc.ran_cases(STANDALONE),
                         {"aThreeDayFloorReadsInDays", "anEmptyStoreIsNotTreatedAsFullyCovered"})


class StillAGate(unittest.TestCase):
    """The repair must not invent passes.

    Mutation: drop BOTH the `[✔━] ` marker and the `passed` anchor from `RAN`
    → the started and failed cases are counted, including the failure spliced
    into a log line, which only the raw-text half of `ran_cases` sees whole.
    Dropping only one of them keeps this class green: either one rejects a whole
    `◇`/`✘` record. For torn records only the marker does; see
    `TornRecordsDoNotBorrowAVerdict`.
    """

    def test_a_case_that_only_started_is_not_counted(self):
        text = (
            "◇ Test aCaseThatHung() started.\n"
            "✔ Test anotherCase() passed after 0.001 seconds.\n"
        )
        self.assertEqual(atc.ran_cases(text), {"anotherCase"})

    def test_a_failed_case_is_not_counted(self):
        text = "✘ Test aFailingCase() failed after 0.001 seconds with 1 issue.\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_failure_inside_a_log_line_is_not_counted(self):
        text = (
            "2026-09-17 17:08:17.095680+0800 xctest[1112:8721793] duo-helper: reje"
            "✘ Test aFailingCase() failed after 0.001 seconds with 1 issue.\n"
            "cted connection — no client requirement is installed on this listener\n"
        )
        self.assertEqual(atc.ran_cases(text), set())


# Prefix of a timestamped log line, as the test process writes it.
TS = "2026-09-17 17:08:17.095680+0800 xctest[1112:8721793] "


class TornRecordsDoNotBorrowAVerdict(unittest.TestCase):
    """A record torn by a log line must not take `passed` from the log line.

    Constructed, not copied from a log: nothing like these has been seen. Each
    one is a record that did NOT pass, glued to log text that ends in `passed`.
    The first two are the counterexamples from the review of #716.

    Mutation: drop the `[✔━] ` marker from `RAN` → all four are counted.
    Mutation: keep the marker for the raw text but match the stripped text with
    a marker-less pattern → only the third is counted, the one where cutting
    the log line out assembles `◇ Test foo() passed`.
    """

    def test_a_started_record_torn_at_its_paren_is_not_counted(self):
        text = "◇ Test foo(" + TS + "helper: probe (ok) passed\n) started.\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_failed_record_torn_at_its_paren_is_not_counted(self):
        text = "✘ Test foo(" + TS + "check(x) passed\n) failed after 0.001 seconds with 1 issue.\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_started_record_whose_tail_lands_in_a_log_line_is_not_counted(self):
        # Record head, log head, record tail, log tail. Cutting the log line out
        # (through the record's newline) leaves `◇ Test foo() passed`.
        text = "◇ Test foo(" + TS + "msg) started.\n) passed\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_marker_from_another_record_is_not_borrowed(self):
        text = "✔ Test bar() passed after 0.001 seconds.\n◇ Test foo(" + TS + "probe (ok) passed\n) started.\n"
        self.assertEqual(atc.ran_cases(text), {"bar"})


class SFSymbolsOutput(unittest.TestCase):
    """With SF Symbols on, swift-testing prints private-use characters instead of
    `✔`/`━`. That happens when SWT_SF_SYMBOLS_ENABLED is set, or when it's unset
    and /Library/Fonts/SF-Pro.ttf exists. The code points are from
    `Event.Symbol._sfSymbolInfo` on swift-testing release/6.4.0: pass U+10105B,
    pass with known issues U+100882, fail U+100884, default (started) U+1007C8.

    Mutation: drop U+10105B / U+100882 from `RAN`'s marker class → the two pass
    cases come back empty, and on such a Mac every case is reported as never run.
    Mutation: widen the marker to any non-space character → the torn SF failure
    is counted.
    """

    def test_an_sf_symbols_pass_is_counted(self):
        text = "\U0010105B Test foo() passed after 0.001 seconds.\n"
        self.assertEqual(atc.ran_cases(text), {"foo"})

    def test_an_sf_symbols_pass_with_a_known_issue_is_counted(self):
        text = "\U00100882 Test foo(_:) with 2 test cases passed after 0.001 seconds with 1 known issue.\n"
        self.assertEqual(atc.ran_cases(text), {"foo"})

    def test_a_torn_sf_symbols_failure_is_not_counted(self):
        text = "\U00100884 Test foo(" + TS + "probe (ok) passed\n) failed after 0.001 seconds with 1 issue.\n"
        self.assertEqual(atc.ran_cases(text), set())


class ReadsUTF8WhateverTheLocale(unittest.TestCase):
    """The markers are non-ASCII, so a log read with the locale's encoding
    stops matching. Measured 2026-09-17: under LC_ALL=en_US.ISO8859-1 the gate
    reported 0 of 51 cases run, and under LC_ALL=C with PYTHONUTF8=0 it crashed
    reading the Swift sources. Which locales a host has is host state, so
    rather than switch locales this runs the gate with every implicit-encoding
    read turned into an error.

    Mutation: drop `encoding="utf-8"` from either `read_text` call in
    `app_test_coverage` → the subprocess exits non-zero with an EncodingWarning.
    """

    def test_the_gate_names_its_encoding_for_every_read(self):
        import subprocess
        import tempfile

        # EncodingWarning and `-X warn_default_encoding` are 3.10+; older
        # interpreters ignore both and this would pass without checking anything.
        self.assertGreaterEqual(sys.version_info[:2], (3, 10))
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Tests").mkdir()
            (root / "Tests" / "ZZFixtureTests.swift").write_text(
                "// — non-ASCII on purpose\n@Test func zzFixtureCase() {}\n", encoding="utf-8")
            (root / "app-tests.log").write_text(
                "✔ Test zzFixtureCase() passed after 0.001 seconds.\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, "-X", "warn_default_encoding", "-W", "error::EncodingWarning",
                 str(pathlib.Path(atc.__file__)), str(root / "app-tests.log"), str(root / "Tests")],
                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], "1 1")


if __name__ == "__main__":
    unittest.main()
