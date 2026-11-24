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
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ci_build_cache as cbc  # noqa: E402
import ci_mini_core_cache as mini  # noqa: E402

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


    def test_mini_refreshes_changed_files_with_mtimes_from_the_other_job(self):
        self.touch("same.swift", BUILT)
        self.touch("edited.swift", BUILT)
        cbc.stamp(self.build)
        (self.build / mini.READY).write_text("toolchain")
        self.touch("same.swift", CHECKOUT)
        pathlib.Path("edited.swift").write_text("a newer branch's content")
        subprocess.run(["git", "add", "edited.swift"], check=True)
        self.touch("edited.swift", BUILT - 10)

        mini.prepare(self.build, "toolchain")

        self.assertEqual(self.mtime("same.swift"), BUILT)
        self.assertGreater(self.mtime("edited.swift"), BUILT)
        self.assertFalse((self.build / mini.READY).exists())

    def test_mini_discards_a_build_left_in_progress(self):
        mini.prepare(self.build, "toolchain")
        (self.build / "partial.o").touch()
        cbc.stamp(self.build)

        mini.prepare(self.build, "toolchain")

        self.assertEqual(list(self.build.iterdir()), [])

    def test_mini_save_makes_the_cache_reusable_for_that_key_only(self):
        mini.prepare(self.build, "toolchain")
        (self.build / "complete.o").touch()
        with patch.object(mini, "MIN_FREE_BYTES", 0):
            mini.save(self.build, "toolchain")
        self.assertEqual((self.build / mini.READY).read_text(), "toolchain")

        mini.prepare(self.build, "new toolchain")

        self.assertEqual(list(self.build.iterdir()), [])

    def test_mini_evicts_an_oversize_cache_without_touching_the_other_job(self):
        workspace = pathlib.Path.cwd() / "checkout"
        swift = mini.scratch_path(workspace, "swift")
        release = mini.scratch_path(workspace, "release")
        mini.prepare(swift, "toolchain")
        mini.prepare(release, "toolchain")
        (swift / "swift.o").write_bytes(b"swift")
        (release / "release.o").write_bytes(b"release")

        with patch.object(mini, "MAX_CACHE_KIB", 0):
            mini.save(swift, "toolchain")

        self.assertFalse(swift.exists())
        self.assertEqual((release / "release.o").read_bytes(), b"release")

    def test_mini_refuses_a_cache_root_symlink(self):
        workspace = pathlib.Path.cwd() / "checkout"
        unrelated = pathlib.Path.cwd() / "unrelated"
        unrelated.mkdir()
        (pathlib.Path.cwd() / ".duo-core-cache").symlink_to(unrelated)
        with self.assertRaisesRegex(ValueError, "Unexpected symlink"):
            mini.scratch_path(workspace, "release")


    def test_mini_rebuilds_from_scratch_if_the_mtime_manifest_is_unreadable(self):
        mini.prepare(self.build, "toolchain")
        (self.build / "old.o").touch()
        (self.build / mini.READY).write_text("toolchain")
        (self.build / cbc.MANIFEST).write_text("{")

        mini.prepare(self.build, "toolchain")

        self.assertEqual(list(self.build.iterdir()), [])

    def test_mini_uses_temporary_scratch_after_evicting_caches_for_low_disk(self):
        workspace = pathlib.Path.cwd()
        # Put the fixture checkout one level down, so the cache stays within
        # the temporary directory even though it is next to the checkout.
        checkout = workspace / "checkout"
        checkout.mkdir()
        swift = mini.scratch_path(checkout, "swift")
        release = mini.scratch_path(checkout, "release")
        mini.prepare(swift, "key")
        mini.prepare(release, "key")
        env_file = workspace / "env"
        with patch.dict(os.environ, {
            "GITHUB_JOB": "swift",
            "GITHUB_WORKSPACE": str(checkout),
            "GITHUB_ENV": str(env_file),
            "RUNNER_TEMP": str(workspace),
        }), patch.object(mini, "MIN_FREE_BYTES", sys.maxsize):
            os.chdir(checkout)
            try:
                mini.main("prepare")
            finally:
                os.chdir(workspace)

        self.assertFalse(swift.exists())
        self.assertFalse(release.exists())
        scratch_line, key_line = env_file.read_text().splitlines()
        self.assertTrue(scratch_line.startswith(f"SWIFTPM_TEST_SCRATCH={workspace}/duo-core-ci."))
        self.assertEqual(key_line, "DUO_MINI_CORE_CACHE_KEY=")


if __name__ == "__main__":
    unittest.main()
