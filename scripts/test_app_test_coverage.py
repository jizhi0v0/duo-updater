#!/usr/bin/env python3
"""Regression tests for `app_test_coverage`. Run by `make test`.

    python3 scripts/test_app_test_coverage.py

The fixtures are lines copied from real `scripts/app-tests.sh` logs on 2026-09-13,
where a stderr log line from the test process landed inside a swift-testing
record and the gate reported a passing case as never run. Every case names the
mutation it catches.
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

# A log line on its own line, between intact records — must change nothing.
STANDALONE = (
    "✔ Test aThreeDayFloorReadsInDays() passed after 0.003 seconds.\n"
    "2026-09-13 19:21:38.379184+0800 xctest[16965:13755191] [logging-persist] cannot open file\n"
    "✔ Test anEmptyStoreIsNotTreatedAsFullyCovered() passed after 0.002 seconds.\n"
)


class SplicedLogLines(unittest.TestCase):
    """Mutation: make `ran_cases` match `RAN` on the raw text (drop the
    `SPLICED_LOG_LINE.sub`) → both split cases come back empty."""

    def test_a_record_split_by_os_log_is_rejoined(self):
        self.assertEqual(atc.ran_cases(SPLIT_BY_OS_LOG), {"aCopyThatBecameABetaReadsTheStore"})

    def test_a_record_split_by_nslog_is_rejoined(self):
        self.assertEqual(atc.ran_cases(SPLIT_BY_NSLOG), {"aWrappedBetaIsRetaggedFromTheStoreItRead"})

    def test_a_standalone_log_line_changes_nothing(self):
        self.assertEqual(atc.ran_cases(STANDALONE),
                         {"aThreeDayFloorReadsInDays", "anEmptyStoreIsNotTreatedAsFullyCovered"})


class StillAGate(unittest.TestCase):
    """The repair must neither invent passes nor erase real ones.

    Mutation: loosen `SPLICED_LOG_LINE` to any text up to a newline (e.g.
    `r"[^\\n]*\\n"`) → records are cut out too, and `anotherCase` disappears.
    Mutation: drop the `passed` anchor from `RAN` → the started and failed cases
    are counted.
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


if __name__ == "__main__":
    unittest.main()
