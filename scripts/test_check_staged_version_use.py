#!/usr/bin/env python3
"""Regression tests for `check_staged_version_use.py`'s `DISPLAY_VERSION_AS_MARKETING`
rule and for the expiry on its opt-out marker.

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

class DeadAllowMarkers(unittest.TestCase):
    """The opt-out marker had no expiry. A marker whose marketing-first pick has
    been rewritten or moved away stays in the file silencing rule 3 for whatever
    is written there next — the standing-pass failure `check_prose_claims.py`
    fails on for its own marker, and the one `make gallery`'s `mayBeBlank` was
    allowed to skip (#271)."""

    PICK = "guard let v = app.shortVersion ?? app.buildVersion else { return }"

    def lines(self, text):
        return text.splitlines()

    def test_a_marker_with_no_pick_below_it_is_dead(self):
        lines = self.lines(f"// {csvu.ALLOW} — reason\nlet x = 1\n")
        self.assertEqual(csvu.dead_allow_markers(lines), [1])

    def test_a_marker_on_the_same_line_as_a_pick_is_alive(self):
        lines = self.lines(f"{self.PICK}  // {csvu.ALLOW} — reason\n")
        self.assertEqual(csvu.dead_allow_markers(lines), [])

    def test_a_marker_within_the_lookback_is_alive(self):
        body = f"// {csvu.ALLOW} — reason\n" + "// filler\n" * (csvu.ALLOW_LOOKBACK - 1)
        lines = self.lines(body + self.PICK + "\n")
        self.assertEqual(csvu.dead_allow_markers(lines), [])

    def test_a_marker_beyond_the_lookback_is_dead(self):
        """The same file one line further apart. This is what pins the two halves
        to ONE window: a marker that no longer exempts the pick must be reported,
        or the check would have to be read as "some marker somewhere below"."""
        body = f"// {csvu.ALLOW} — reason\n" + "// filler\n" * csvu.ALLOW_LOOKBACK
        lines = self.lines(body + self.PICK + "\n")
        self.assertEqual(csvu.dead_allow_markers(lines), [1])
        # …and the pick it no longer covers is not exempt either.
        self.assertEqual(csvu.markers_covering(lines, len(lines)), [])

if __name__ == "__main__":
    unittest.main()
