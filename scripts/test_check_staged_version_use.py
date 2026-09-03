#!/usr/bin/env python3
"""Regression tests for `check_staged_version_use.py`'s `DISPLAY_VERSION_AS_MARKETING` rule.

#286: the rule PR #250 added used `[\\w.]*` between `marketing:` and
`displayVersion`, which excludes `?` — so it missed the standard way this
codebase reaches a `RemoteVersion?` (`result.remote?.displayVersion`), single-
or multi-line, and also missed the #235 bug's exact original shape
(`displayVersion` assigned to a local, then `marketing: <that local>`). The
four cases below are the ones from the issue, pinned to what the fixed rule
actually does with each — including the one that stays a documented miss.

    python3 scripts/test_check_staged_version_use.py
"""

import pathlib
import re
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_staged_version_use as csvu  # noqa: E402


def hits(text):
    return bool(csvu.DISPLAY_VERSION_AS_MARKETING.search(text))


class DisplayVersionAsMarketingOptionalChain(unittest.TestCase):
    """`result.remote?.displayVersion` is the standard way this file reaches a
    `RemoteVersion?` — the natural spelling of the exact site this rule exists
    to catch. A character class that excludes `?` lets it straight through."""

    def test_optional_chain_single_line_is_caught(self):
        self.assertTrue(hits(
            "VersionSide(marketing: result.remote?.displayVersion, build: nil)"))

    def test_optional_chain_multiline_is_caught(self):
        self.assertTrue(hits(
            "VersionSide(\n"
            "    marketing: result.remote?.displayVersion,\n"
            "    build: nil)"))

    def test_plain_unwrapped_access_is_still_caught(self):
        """Not a regression case — pins the shape #250 already caught."""
        self.assertTrue(hits(
            "VersionSide(marketing: remote.displayVersion, build: nil)"))

    def test_via_variable_indirection_remains_an_undetected_blind_spot(self):
        """The #235 bug's exact original shape on main before it was fixed:
        `displayVersion` assigned to a local first, then `marketing: <local>`.
        No feasible character class sees this — it is cross-statement data
        flow, not a spelling variant — so this pins the documented miss rather
        than pretending the rule covers it. See the comment above
        `DISPLAY_VERSION_AS_MARKETING` in check_staged_version_use.py."""
        self.assertFalse(hits(
            "VersionSide(marketing: version, build: buildVersion)"))


class MutationGuard(unittest.TestCase):
    """Proves the tests above actually depend on the widened character class,
    not just on `VersionSide`/`marketing:`/`displayVersion` appearing somewhere
    in the line. Re-runs the two optional-chain cases against the pre-#286
    pattern and requires them to miss — i.e. this test class itself must fail
    if the fix in `check_staged_version_use.py` is reverted to the pattern
    below (the case this whole file exists to prevent from going undetected)."""

    PRE_286_PATTERN = re.compile(
        r"VersionSide\s*\([^)]*marketing:\s*[\w.]*displayVersion", re.DOTALL)

    def test_pre_fix_pattern_missed_the_optional_chain_single_line(self):
        self.assertFalse(bool(self.PRE_286_PATTERN.search(
            "VersionSide(marketing: result.remote?.displayVersion, build: nil)")))

    def test_pre_fix_pattern_missed_the_optional_chain_multiline(self):
        self.assertFalse(bool(self.PRE_286_PATTERN.search(
            "VersionSide(\n"
            "    marketing: result.remote?.displayVersion,\n"
            "    build: nil)")))

    def test_current_pattern_differs_from_the_pre_fix_pattern(self):
        """If someone "fixes" the regex back to the narrow character class,
        this fails loudly instead of the two tests above silently no longer
        exercising the fix."""
        self.assertNotEqual(
            csvu.DISPLAY_VERSION_AS_MARKETING.pattern, self.PRE_286_PATTERN.pattern)


if __name__ == "__main__":
    unittest.main()
