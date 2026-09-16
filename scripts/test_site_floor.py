#!/usr/bin/env python3
"""Regression tests for `site_floor`. Run by `make test`.

    python3 scripts/test_site_floor.py

The site text below is copied from duoupdater.app's `origin/main` on 2026-09-16
(app/layout.tsx, app/page.tsx, components/DownloadButton.tsx) — the three places
it states a minimum macOS — so a pattern that stops matching the real phrasing
goes red here rather than printing "found nothing" on release day.
"""

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import site_floor as sf  # noqa: E402

SITE = [
    ("app/layout.tsx", 57, "                Silicon, macOS 14+."),
    ("app/page.tsx", 35, '    operatingSystem: "macOS 14 or later, Apple Silicon",'),
    ("components/DownloadButton.tsx", 13,
     '        Apple Silicon, macOS 14 or later. Free and open source.{" "}'),
]


class Parsing(unittest.TestCase):
    def test_every_real_site_phrasing_is_read(self):
        """Mutation: drop `\\+` from the pattern → layout.tsx is not read."""
        found = sf.stated_floors(SITE)
        self.assertEqual([(p, n, m) for p, n, m, _ in found],
                         [("app/layout.tsx", 57, "14"), ("app/page.tsx", 35, "14"),
                          ("components/DownloadButton.tsx", 13, "14")])

    def test_a_minor_version_reads_as_its_major(self):
        self.assertEqual(sf.major("15.0"), "15")
        self.assertEqual(sf.major("15"), "15")
        self.assertEqual(sf.stated_floors([("x", 1, "macOS 26.4 or later")])[0][2], "26")

    def test_the_site_copy_of_the_changelog_is_not_the_site_speaking(self):
        """Release notes describe other apps: "needs macOS 26 or later"."""
        self.assertEqual(sf.stated_floors([("content/changelog.md", 9, "needs macOS 26 or later")]), [])

    def test_unreadable_floor_is_none(self):
        self.assertIsNone(sf.major(""))
        self.assertIsNone(sf.major(None))


class Verdict(unittest.TestCase):
    def test_a_site_behind_a_raised_floor_is_reported_line_by_line(self):
        status, lines = sf.verdict("15.0", sf.stated_floors(SITE))
        self.assertEqual(status, 1)
        self.assertEqual(len(lines), 3)
        self.assertIn("app/layout.tsx:57", lines[0])
        self.assertIn("says macOS 14", lines[0])

    def test_a_site_that_agrees(self):
        status, _ = sf.verdict("14.0", sf.stated_floors(SITE))
        self.assertEqual(status, 0)

    def test_one_line_left_behind_is_still_a_mismatch(self):
        """Mutation: report a mismatch only when every statement differs → green."""
        mixed = [SITE[0], ("app/page.tsx", 35, '"macOS 15 or later, Apple Silicon"'),
                 ("components/DownloadButton.tsx", 13, "Apple Silicon, macOS 15 or later.")]
        status, lines = sf.verdict("15.0", sf.stated_floors(mixed))
        self.assertEqual(status, 1)
        self.assertEqual(len(lines), 1)

    def test_finding_nothing_is_not_agreement(self):
        """The site reworded to "Sequoia or newer": no statement is read, and that
        must not print the green line.

        Mutation: return 0 for an empty statement list → status 0."""
        status, _ = sf.verdict("15.0", sf.stated_floors([("app/page.tsx", 35, "Requires Sequoia or newer")]))
        self.assertEqual(status, 2)

    def test_no_floor_in_the_app_is_not_agreement(self):
        status, _ = sf.verdict("", sf.stated_floors(SITE))
        self.assertEqual(status, 2)


class AgainstAGitRepository(unittest.TestCase):
    """The git half, on a throwaway repository with an `origin` of its own — no
    network, and never the real site checkout.

    The fixture's own git runs without the machine's global and system config:
    a `commit.gpgsign = true` there made every commit here invoke a signer, and
    the three tests error out (reproduced with a config whose gpg program is
    `/usr/bin/false`). A hooks path or template set globally would do the same."""

    ENV = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}

    def git(self, cwd, *args):
        subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True,
                       env=self.ENV)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.origin = root / "origin"
        self.origin.mkdir()
        self.git(self.origin, "init", "-q", "-b", "main")
        self.git(self.origin, "config", "user.email", "t@example.invalid")
        self.git(self.origin, "config", "user.name", "t")
        (self.origin / "app").mkdir()
        (self.origin / "app" / "layout.tsx").write_text("Apple Silicon, macOS 14+.\n")
        (self.origin / "content").mkdir()
        (self.origin / "content" / "changelog.md").write_text("needs macOS 26 or later\n")
        self.git(self.origin, "add", ".")
        self.git(self.origin, "commit", "-q", "-m", "site")
        self.clone = root / "clone"
        subprocess.run(["git", "clone", "-q", str(self.origin), str(self.clone)],
                       check=True, capture_output=True, env=self.ENV)

    def tearDown(self):
        self.tmp.cleanup()

    def test_reads_the_fetched_branch_not_the_local_checkout(self):
        """The site is fixed on origin after this clone was made: the local tree
        still says 14, the deployed branch says 15.

        Mutation: grep HEAD instead of origin/main → reports layout.tsx as 14."""
        (self.origin / "app" / "layout.tsx").write_text("Apple Silicon, macOS 15+.\n")
        self.git(self.origin, "commit", "-q", "-am", "raise")
        ref, lines = sf.site_lines(str(self.clone))
        self.assertEqual(ref, "origin/main")
        self.assertEqual(sf.verdict("15.0", sf.stated_floors(lines))[0], 0)

    def test_the_changelog_copy_is_excluded_end_to_end(self):
        _, lines = sf.site_lines(str(self.clone))
        self.assertEqual([s[0] for s in sf.stated_floors(lines)], ["app/layout.tsx"])

    def test_a_directory_that_is_not_a_checkout_cannot_be_compared(self):
        with self.assertRaises(RuntimeError):
            sf.site_lines(str(pathlib.Path(self.tmp.name) / "nowhere"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
