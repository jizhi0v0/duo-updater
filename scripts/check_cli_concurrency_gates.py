#!/usr/bin/env python3
"""No CLI-tab button decides on its own which brew or tool run blocks it (#1312).

No button is disabled by another run at all: every model action
(`AppListModel.upgradeBrewFormulae`, `upgradeBrewFormula`, `updateHomebrew`,
`CLIToolsModel.update`/`updateAll`) takes the click and waits its turn in one
queue, `CLIRunQueue` in Core. Before #1312, each Update and Upgrade All carried
its own `.disabled(…)` over brew's and the tools' state, and they drifted:
Upgrade All waited for every tool, a formula row for `brew update` only, its
detail pane for nothing.

This lint fails on a `.disabled(…)` or `disabled:` argument in the popover or
the workbench that reads that state again. Tool against tool stays each tool's
own rule, so `tools.updatingAll` alone is not flagged.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCANNED = [
    ROOT / "App" / "Sources" / "MenuContentView.swift",
    ROOT / "App" / "Sources" / "WorkbenchWindowView.swift",
    ROOT / "App" / "Sources" / "CLIToolsWorkbench.swift",
]

# The state a gate used to read, in every spelling it had.
STATE = re.compile(
    r"\b(?:brewUpgrading|upgradingFormulae|homebrewUpdating|brewUpgradeRunning|brewBusy)\b"
    r"|\bcliTools\.updating")
GATE = re.compile(r"\.disabled\(|\bdisabled:")


def gate_expressions(text):
    """(line number, expression) for each gate: from its opening to the paren
    that closes the call, or for `disabled:` to the argument's end."""
    for match in GATE.finditer(text):
        start = match.end()
        depth = 1 if match.group().endswith("(") else 0
        i = start
        while i < len(text):
            c = text[i]
            if c in "([":
                depth += 1
            elif c in ")]":
                depth -= 1
                if depth < 0 or (depth == 0 and match.group().endswith("(")):
                    break
            elif c == "," and depth == 0:
                break
            i += 1
        yield text.count("\n", 0, match.start()) + 1, text[start:i]


def violations(path, text):
    return [(path, line, expr.strip()) for line, expr in gate_expressions(text) if STATE.search(expr)]


def main():
    found = []
    for path in SCANNED:
        found += violations(path.relative_to(ROOT), path.read_text(encoding="utf-8"))
    for path, line, expr in found:
        print(f"✗ {path}:{line}: a button gates on brew or tool state itself: {' '.join(expr.split())}")
    if found:
        print("  Let the model action wait its turn (CLIRunQueue) instead.")
        return 1
    print(f"✓ No inline brew/tool gate in {len(SCANNED)} CLI-tab views")
    return 0


if __name__ == "__main__":
    sys.exit(main())
