#!/usr/bin/env python3
"""`derived_data_path.py` hands back a directory only this user can write.

The path is `/tmp/duo-<name>-<hash of the checkout path>`: shared parent, a name
anyone can compute. Another account that creates it first would own what the
build products are later run from (`generate_appcast`, which signs the appcast,
is found under the notary one). Run by `make test-scripts`.

    python3 scripts/test_derived_data_path.py
"""

import io
import os
import pathlib
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import derived_data_path as dd  # noqa: E402


class PrivateDirectory(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = pathlib.Path(self.tmp.name)
        self.repo = self.base / "checkout"
        self.repo.mkdir()
        patch = mock.patch.object(dd, "BASE", self.base)
        patch.start()
        self.addCleanup(patch.stop)

    def run_main(self):
        out = io.StringIO()
        with mock.patch.object(sys, "argv", ["derived_data_path.py", "install", str(self.repo)]):
            with redirect_stdout(out):
                dd.main()
        return pathlib.Path(out.getvalue().strip())

    def expected(self):
        # Created once to learn the name, then removed so each test controls the start.
        path = self.run_main()
        (path / dd.MARKER).unlink()
        path.rmdir()
        return path

    def test_a_new_directory_is_created_private(self):
        path = self.run_main()
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
        self.assertEqual((path / dd.MARKER).read_text(), f"{self.repo.resolve()}\n")

    def test_a_directory_that_is_already_ours_is_reused(self):
        first = self.run_main()
        (first / "Build").mkdir()
        self.assertEqual(self.run_main(), first)
        self.assertTrue((first / "Build").is_dir())

    def test_the_default_mode_an_earlier_version_used_is_accepted(self):
        path = self.expected()
        path.mkdir(mode=0o755)
        os.chmod(path, 0o755)
        self.assertEqual(self.run_main(), path)

    def test_a_directory_others_can_write_is_refused(self):
        for mode in (0o777, 0o770, 0o707):
            with self.subTest(mode=oct(mode)):
                path = self.expected()
                path.mkdir()
                os.chmod(path, mode)
                with self.assertRaises(SystemExit) as raised:
                    self.run_main()
                self.assertIn("writable by group or others", str(raised.exception))
                self.assertFalse((path / dd.MARKER).exists())
                path.rmdir()

    def test_a_symlink_is_refused_and_not_written_through(self):
        path = self.expected()
        elsewhere = self.base / "elsewhere"
        elsewhere.mkdir()
        path.symlink_to(elsewhere)
        with self.assertRaises(SystemExit) as raised:
            self.run_main()
        self.assertIn("symlink", str(raised.exception))
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_a_directory_owned_by_someone_else_is_refused(self):
        path = self.expected()
        path.mkdir(mode=0o700)
        with mock.patch("os.geteuid", return_value=os.geteuid() + 1):
            with self.assertRaises(SystemExit) as raised:
                self.run_main()
        self.assertIn("not owned by you", str(raised.exception))
        self.assertFalse((path / dd.MARKER).exists())

    def test_a_file_in_the_way_is_refused(self):
        path = self.expected()
        path.write_text("")
        with self.assertRaises(SystemExit) as raised:
            self.run_main()
        self.assertIn("not a directory", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
