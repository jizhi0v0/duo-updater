#!/usr/bin/env python3
"""Regression tests for `ci_build_cache`. Run by `make test`.

    python3 scripts/test_ci_build_cache.py
"""

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ci_build_cache as cbc  # noqa: E402

BUILT = 1_600_000_000_000_000_000   # when the cached build ran
CHECKOUT = 1_900_000_000_000_000_000  # when this run checked out, later


class RoundTrip(unittest.TestCase):
    def setUp(self):
        self.old = os.getcwd()
        self.tmp = tempfile.TemporaryDirectory()
        os.chdir(self.tmp.name)
        git = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(["git", "init", "-q"], check=True)
        for name in ("same.swift", "edited.swift"):
            pathlib.Path(name).write_text(name)
        subprocess.run(git + ["add", "."], check=True)
        subprocess.run(git + ["commit", "-qm", "a"], check=True)
        self.build = pathlib.Path(".build")

    def tearDown(self):
        os.chdir(self.old)
        self.tmp.cleanup()

    def touch(self, name, ns):
        os.utime(name, ns=(ns, ns))

    def mtime(self, name):
        return os.stat(name).st_mtime_ns

    def test_only_unchanged_files_get_the_build_time_back(self):
        for name in ("same.swift", "edited.swift"):
            self.touch(name, BUILT)
        cbc.stamp(self.build)

        # The next run: a fresh checkout of a commit that edited one file.
        pathlib.Path("edited.swift").write_text("changed")
        subprocess.run(["git", "add", "edited.swift"], check=True)
        pathlib.Path("new.swift").write_text("new")
        subprocess.run(["git", "add", "new.swift"], check=True)
        for name in ("same.swift", "edited.swift", "new.swift"):
            self.touch(name, CHECKOUT)

        self.assertIn("restored 1 mtimes; 2 files new or changed", cbc.restore(self.build))
        self.assertEqual(self.mtime("same.swift"), BUILT)
        self.assertEqual(self.mtime("edited.swift"), CHECKOUT)
        self.assertEqual(self.mtime("new.swift"), CHECKOUT)

    def test_a_file_dirty_at_stamp_time_is_not_recorded(self):
        pathlib.Path("edited.swift").write_text("uncommitted")
        self.touch("edited.swift", BUILT)
        cbc.stamp(self.build)
        subprocess.run(["git", "checkout", "-q", "edited.swift"], check=True)
        self.touch("edited.swift", CHECKOUT)

        cbc.restore(self.build)
        self.assertEqual(self.mtime("edited.swift"), CHECKOUT)

    def test_no_manifest_leaves_every_file_alone(self):
        self.touch("same.swift", CHECKOUT)
        self.assertIn("no manifest", cbc.restore(self.build))
        self.assertEqual(self.mtime("same.swift"), CHECKOUT)


if __name__ == "__main__":
    unittest.main()
