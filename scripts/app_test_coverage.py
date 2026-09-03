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
FUNC = re.compile(r"\bfunc\s+([A-Za-z0-9_]+)\s*\(")


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
    ran = set(RAN.findall(log.read_text(errors="replace")))
    declared = declared_cases(tests)
    print(f"{len(declared)} {len(ran & declared)}")
    print(" ".join(sorted(declared - ran)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
