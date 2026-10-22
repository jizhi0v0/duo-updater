#!/usr/bin/env python3
"""Regression tests for `check_real_machine_record`. Run by `make test`.

    python3 scripts/test_check_real_machine_record.py

Each passing case is paired with the nearest body that must fail, so a rule
that stopped firing cannot pass both.
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_real_machine_record as rm  # noqa: E402

CORE = ["DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/AppRecipeIndex.swift"]
BRANCH = "onboard-example"

RECORD = """\
## Status
One-click wired.

## Real-machine result (2026-10-22)

Done on the dev Mac with this branch's `duo` (`make cli`).

- 一键端到端 ✓ 两轮（不运行 / 运行中）
"""


def check(body, files=CORE, head_ref=BRANCH, complete=True):
    return rm.evaluate(body, files, head_ref, complete)[0]


class CheckRealMachineRecordTests(unittest.TestCase):
    def test_a_dated_section_with_a_result_passes(self):
        self.assertTrue(check(RECORD))

    def test_a_missing_record_fails(self):
        self.assertFalse(check("## Change\n- rewrote the gate\n"))
        self.assertFalse(check(""))

    def test_the_section_needs_a_date(self):
        self.assertFalse(check(RECORD.replace(" (2026-10-22)", "")))
        # The date may sit in the body instead of the heading.
        self.assertTrue(check(RECORD.replace(" (2026-10-22)", "").replace(
            "Done on", "2026-10-22: done on")))

    def test_an_impossible_date_is_not_a_date(self):
        self.assertFalse(check(RECORD.replace("2026-10-22", "2026-13-45")))

    def test_the_section_needs_a_result_line(self):
        self.assertFalse(check(RECORD.replace("- 一键", "一键")))
        # A fenced block of output counts.
        self.assertTrue(check(RECORD.replace(
            "- 一键端到端 ✓ 两轮（不运行 / 运行中）", "```\n1 installed, 0 failed.\n```")))
        # A table row counts, its rule line does not.
        self.assertTrue(check(RECORD.replace(
            "- 一键端到端 ✓ 两轮（不运行 / 运行中）", "| | before | after |\n|---|---|---|\n| log | a | b |")))
        self.assertFalse(check(RECORD.replace(
            "- 一键端到端 ✓ 两轮（不运行 / 运行中）", "|---|---|")))

    def test_the_result_must_be_inside_the_section(self):
        body = "## Real-machine result (2026-10-22)\nDone.\n\n## Tests\n- make test ✓\n"
        self.assertFalse(check(body))
        # A sub-heading stays inside its section.
        self.assertTrue(check(body.replace("## Tests", "### Round 1")))

    def test_a_pending_placeholder_is_not_a_record(self):
        self.assertFalse(check("## Real machine: pending (main session) 2026-10-22\n- later\n"))
        self.assertFalse(check("## 真机：待主会话 2026-10-22\n- later\n"))
        self.assertTrue(check("## 真机结果 (2026-10-22)\n- ✓\n"))

    def test_a_dated_not_done_section_is_not_a_record(self):
        # #1588's heading, with the date its failure message asked for.
        body = (
            "## Not done here (real-machine checks for the main session) 2026-10-22\n"
            "- Tropy: `duo restart Tropy` with 1.17.3 staged\n"
        )
        self.assertFalse(check(body))
        self.assertFalse(check(body.replace("Not done here", "Checks")))
        self.assertTrue(check(body.replace(" for the main session", "").replace("Not done here", "Done")))
        self.assertFalse(check("## Real-machine run: not yet (2026-10-22)\n- ✓\n"))
        self.assertFalse(check("## 真机：未做 (2026-10-22)\n- ✓\n"))

    def test_an_unticked_item_is_not_a_result(self):
        body = "## Real-machine result (2026-10-22)\n- [ ] run one-click on the dev Mac\n"
        self.assertFalse(check(body))
        self.assertFalse(check(body.replace("- [ ]", "1. [ ]")))
        self.assertTrue(check(body.replace("[ ]", "[x]")))

    def test_a_pending_line_is_not_a_result_unless_it_marks_an_outcome(self):
        body = "## Real-machine result (2026-10-22)\n- round 2 not done yet\n"
        self.assertFalse(check(body))
        self.assertFalse(check(body.replace("not done yet", "planned for the main session")))
        # #1576's line: one round passed, the other was not run.
        self.assertTrue(check(body.replace(
            "round 2 not done yet", "一键端到端 ✓ 不运行一轮（运行中一轮未跑：启动会弹本地网络授权框）")))

    def test_result_wording_that_contains_pending_words_still_counts(self):
        # Review round 2: "not running" is a round's name and `duo restart`'s output.
        body = (
            "## Real-machine result (2026-10-23)\n"
            "- 2.1.0 → 2.1.1, app not running: refused (`noTeamIdentifier`), nothing changed on disk\n"
        )
        self.assertTrue(check(body))
        self.assertTrue(check(
            "## Real-machine result (2026-10-23)\n"
            "- `duo restart Foo` → `not running — nothing to restart`\n"))
        self.assertTrue(check(body.replace("app not running: refused", "nothing to do")))
        self.assertTrue(check(body.replace("app not running: refused", "等待 ShipIt 换包后是 2.1.1")))
        # Paired: the same line with the phrase that does mean "not run".
        self.assertFalse(check(body.replace("app not running: refused (`noTeamIdentifier`), nothing changed on disk", "app not run")))
        self.assertFalse(check(body.replace("app not running: refused (`noTeamIdentifier`), nothing changed on disk", "待跑")))

    def test_the_failure_says_items_were_read_as_not_done(self):
        passed, msg = rm.evaluate(
            "## Real-machine result (2026-10-22)\n- [ ] run it\n", CORE, BRANCH, True)
        self.assertFalse(passed)
        self.assertIn("1 item(s) read as not done", msg)

    def test_a_heading_inside_a_code_block_is_not_read(self):
        body = "```\n" + RECORD + "```\n"
        self.assertFalse(check(body))

    def test_an_opt_out_with_a_reason_passes(self):
        self.assertTrue(check("Real-machine: not needed — refactor, no behaviour change\n"))
        self.assertTrue(check("- **Real machine: not needed** - test-only helper\n"))

    def test_an_opt_out_needs_a_reason(self):
        self.assertFalse(check("Real-machine: not needed —\n"))
        self.assertFalse(check("Real-machine: not needed — **\n"))
        self.assertFalse(check("Real-machine: not needed — …\n"))
        self.assertFalse(check("Real-machine: not needed\n"))

    def test_an_opt_out_inside_a_code_block_is_not_read(self):
        self.assertFalse(check("```\nReal-machine: not needed — example\n```\n"))

    def test_a_docs_and_tests_only_change_is_exempt(self):
        files = [
            "docs/app-audits/README.md",
            "DuoUpdaterCore/Tests/RecipeGoldens/x.json",
            "DuoUpdaterCore/Tests/DuoUpdaterCoreTests/XTests.swift",
            "scripts/check_x.py",
        ]
        self.assertTrue(check("", files=files))
        self.assertFalse(check("", files=files + ["App/Helper/HelperService.swift"]))

    def test_an_incomplete_file_list_is_treated_as_covered(self):
        self.assertFalse(check("", files=["docs/x.md"], complete=False))
        self.assertTrue(check(RECORD, files=["docs/x.md"], complete=False))

    def test_an_exempt_branch_passes_without_a_record(self):
        for ref in ("release/0.5.13", "appcast/v0.5.12-20261021T173913Z-1",
                    "verify/baseline-20261022T022254Z", "verify/install-20261022T104308Z",
                    "recipe-autofix/x", "bench/run-1"):
            self.assertTrue(check("", head_ref=ref), ref)
        # Only as a prefix.
        self.assertFalse(check("", head_ref="claude/release/x"))

    def test_the_failure_says_what_to_add(self):
        passed, msg = rm.evaluate(
            "## Real machine (lease held)\n- ran it\n", CORE, BRANCH, True)
        self.assertFalse(passed)
        self.assertIn("has no date", msg)
        self.assertIn("Real-machine: not needed — <reason>", msg)


if __name__ == "__main__":
    unittest.main()
