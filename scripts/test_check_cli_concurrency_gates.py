#!/usr/bin/env python3
"""Tests for check_cli_concurrency_gates.py."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_cli_concurrency_gates as check  # noqa: E402


def flagged(source):
    return [expr for _, _, expr in check.violations("View.swift", source)]


class GateTests(unittest.TestCase):

    def test_the_pre_1312_gates_are_flagged(self):
        # Upgrade All's, over several lines; the popover's argument form.
        self.assertEqual(len(flagged("""
            .disabled(model.brewUpgrading || !model.upgradingFormulae.isEmpty || model.homebrewUpdating
                || model.cliTools.updatingAll || !model.cliTools.updating.isEmpty)
        """)), 1)
        self.assertEqual(len(flagged("""
            button: updateButton(
                disabled: tools.updatingAll || model.homebrewUpdating,
                help: "x")
        """)), 1)
        self.assertEqual(len(flagged(".disabled(brewBusy)")), 1)

    def test_tool_against_tool_and_other_gates_pass(self):
        self.assertEqual(flagged(".disabled(tools.updatingAll || tools.batchable.isEmpty)"), [])
        self.assertEqual(flagged(".disabled(!model.canRollback(result.id))"), [])
        # State read outside a gate is not a gate.
        self.assertEqual(flagged("if model.brewUpgrading { ProgressView() }"), [])

    def test_the_tree_is_clean(self):
        self.assertEqual(check.main(), 0)


if __name__ == "__main__":
    unittest.main()
