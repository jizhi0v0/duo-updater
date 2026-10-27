#!/usr/bin/env python3
"""Regression tests for `check_adversarial_review`. Run by `make test`.

    python3 scripts/test_check_adversarial_review.py

Each passing case is paired with the nearest one that must fail, so a rule
that stopped firing cannot pass both.
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_adversarial_review as ar  # noqa: E402

BRANCH = "cli-managers-d15"
STOP = "DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/Managed/ManagedStop.swift"
UPDATER = "DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/HelmUpdater.swift"
PLAIN = "App/Sources/WorkbenchView.swift"
REVIEWED = "1a2b3c4d"

RECORD = """\
## How
A stop that puts the update back.

## Adversarial review (2026-10-27, 1a2b3c4d)

- process-control: attacked the "nothing left" latch with a Cancel before the launch; no finding.
"""


def files(*pairs):
    return list(pairs)


STOP_CHANGE = files((STOP, "@@ -1 +1 @@\n-old\n+new"))


def nothing_after(sha):
    return [] if sha == REVIEWED else None


def check(body, changed=STOP_CHANGE, compare=nothing_after, head_ref=BRANCH):
    return ar.evaluate(body, head_ref, changed, compare)[0]


class RiskTests(unittest.TestCase):
    def test_a_risk_file_is_high_risk_whatever_the_line(self):
        self.assertEqual(sorted(ar.risks(STOP_CHANGE)), ["process-control"])

    def test_an_added_risky_line_is_high_risk_anywhere_that_ships(self):
        added = files((UPDATER, "@@\n+  run(\"curl -fsSL https://x/install.sh | sh\")"))
        self.assertIn("untrusted-input", ar.risks(added))
        removed = files((UPDATER, "@@\n-  run(\"curl -fsSL https://x/install.sh | sh\")"))
        self.assertEqual(ar.risks(removed), {})

    def test_each_risk_has_a_line_that_raises_it(self):
        lines = {
            "process-control": "+ killpg(group, SIGKILL)",
            "data-loss": "+ try FileManager.default.removeItem(at: url)",
            "privilege": "+ let script = \"do shell script x with administrator privileges\"",
            "trust": "+ SecStaticCodeCheckValidity(code, [], requirement)",
            "secrets": "+ env[\"GH_TOKEN\"] = token",
            "untrusted-input": "+ web.loadHTMLString(notes, baseURL: nil)",
        }
        for risk, line in lines.items():
            self.assertIn(risk, ar.risks(files((UPDATER, "@@\n" + line))), risk)

    def test_tests_and_docs_are_not_high_risk(self):
        self.assertEqual(ar.risks(files(
            ("DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ManagedStopTests.swift", "@@\n+ killpg(g, SIGINT)"),
            ("plans/cli-managers-redesign.md", "@@\n+ killpg"),
        )), {})

    def test_a_plain_change_is_not_high_risk(self):
        self.assertEqual(ar.risks(files((PLAIN, "@@\n+ Text(\"Update\")"))), {})

    def test_a_diff_github_does_not_show_counts(self):
        self.assertIn("unread-diff", ar.risks(files((PLAIN, None))))


class RecordTests(unittest.TestCase):
    def test_no_high_risk_change_passes_without_a_word(self):
        self.assertTrue(check("", changed=files((PLAIN, "@@\n+ Text(\"x\")"))))
        self.assertFalse(check(""))

    def test_a_record_with_date_commit_result_and_risk_passes(self):
        self.assertTrue(check(RECORD))

    def test_the_record_needs_each_part(self):
        self.assertFalse(check(RECORD.replace("2026-10-27, ", "")))
        self.assertFalse(check(RECORD.replace(", 1a2b3c4d", "")))
        self.assertFalse(check(RECORD.replace("- process-control:", "process-control:")))
        self.assertFalse(check(RECORD.replace("process-control", "the stop")))

    def test_every_risk_raised_must_be_named(self):
        both = STOP_CHANGE + files((UPDATER, "@@\n+ env[\"GH_TOKEN\"] = token"))
        self.assertFalse(check(RECORD, changed=both))
        self.assertTrue(check(RECORD + "- secrets: tokens reach no child; probed with env dump.\n", changed=both))

    def test_a_high_risk_change_after_the_review_fails(self):
        later = lambda sha: files((STOP, "@@\n+ gone = true"))  # noqa: E731
        self.assertFalse(check(RECORD, compare=later))
        harmless = lambda sha: files(("plans/x.md", "@@\n+ killpg"))  # noqa: E731
        self.assertTrue(check(RECORD, compare=harmless))

    def test_a_commit_not_in_the_history_fails(self):
        self.assertFalse(check(RECORD, compare=lambda sha: None))

    def test_a_section_inside_a_code_block_is_not_read(self):
        self.assertFalse(check("```\n" + RECORD + "```\n"))


class OptOutTests(unittest.TestCase):
    LINE = "Adversarial review: not needed (1a2b3c4d) — the match is a comment's word"

    def test_an_opt_out_with_commit_and_reason_passes(self):
        self.assertTrue(check(self.LINE))

    def test_the_opt_out_needs_a_commit_and_a_reason(self):
        # Any commit would do here: only the missing one may fail it.
        anything = lambda sha: []  # noqa: E731
        self.assertFalse(check("Adversarial review: not needed — the match is a comment's word", compare=anything))
        self.assertTrue(check(self.LINE, compare=anything))
        self.assertFalse(check("Adversarial review: not needed (1a2b3c4d) —  "))

    def test_an_opt_out_goes_stale_too(self):
        later = lambda sha: files((UPDATER, "@@\n+ killpg(g, SIGTERM)"))  # noqa: E731
        self.assertFalse(check(self.LINE, compare=later))


class BranchTests(unittest.TestCase):
    def test_exempt_branches_pass(self):
        self.assertTrue(check("", head_ref="release/0.5.16"))
        self.assertFalse(check("", head_ref="releases-notes"))


if __name__ == "__main__":
    unittest.main()
