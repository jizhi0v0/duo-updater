#!/usr/bin/env python3
"""Cache compatibility must change when stale build metadata could be reused."""

import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import ci_xcode_cache as cache
import check_localizable_keys as localize


class Compatibility(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        for name, content in {
            "App/Sources/Main.swift": "old source",
            "App/Tests/Test.swift": "test",
            "App/project.yml": "settings",
            "App/Package.resolved": "pins",
            "scripts/app-tests.sh": "test command",
        }.items():
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
        self.git("add", ".")
        self.toolchain = ["Xcode 27.1", "arm64", "image"]
        self.key = self.current()

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.root), *args], check=True)

    def current(self):
        return cache.cache_key(self.root, self.toolchain)

    def test_content_edits_reuse_cache_but_settings_and_pins_do_not(self):
        source = self.root / "App/Sources/Main.swift"
        source.write_text("new source")
        os.utime(source, ns=(1_600_000_000_000_000_000,) * 2)
        self.assertEqual(self.current(), self.key)
        for name in ("App/project.yml", "App/Package.resolved", "scripts/app-tests.sh"):
            with self.subTest(name=name):
                p = self.root / name
                original = p.read_text()
                p.write_text("changed")
                self.assertNotEqual(self.current(), self.key)
                p.write_text(original)

    def test_added_deleted_and_renamed_inputs_start_cold(self):
        source = self.root / "App/Sources/Main.swift"
        source.rename(source.with_name("Renamed.swift"))
        self.git("add", "-A")
        self.assertNotEqual(self.current(), self.key)
        source.with_name("Renamed.swift").rename(source)
        self.git("add", "-A")
        self.assertEqual(self.current(), self.key)
        source.unlink()
        self.git("add", "-A")
        self.assertNotEqual(self.current(), self.key)
        source.write_text("old source")
        self.git("add", "-A")
        self.assertEqual(self.current(), self.key)
        (self.root / "App/Sources/New.swift").write_text("new")
        self.git("add", "-A")
        self.assertNotEqual(self.current(), self.key)

    def test_toolchain_and_absolute_checkout_path_are_not_interchangeable(self):
        self.assertNotEqual(cache.cache_key(self.root, ["different SDK"]), self.key)
        alias = self.root.with_name(self.root.name + "-other")
        shutil.copytree(self.root, alias)
        self.addCleanup(shutil.rmtree, alias)
        # Identical input paths and contents at another absolute source root.
        self.assertNotEqual(cache.cache_key(alias, self.toolchain), self.key)

    def test_docs_and_baselines_do_not_invalidate_the_build(self):
        (self.root / "README.md").write_text("documentation")
        self.git("add", "README.md")
        self.assertEqual(self.current(), self.key)

    def test_localization_keeps_its_own_sparkle_artifacts_with_shared_modules(self):
        project = self.root / "DuoUpdater.xcodeproj"
        project.mkdir()
        loc = self.root / "localization-dd"
        env = {"XCODE_CLONED_SOURCE_PACKAGES": "/other-build/SourcePackages",
               "XCODE_MODULE_CACHE_PATH": "/shared/ModuleCache.noindex"}
        with mock.patch.object(localize, "PROJECT", project), \
             mock.patch.dict(os.environ, env), \
             mock.patch.object(localize.subprocess, "run", return_value=
                               subprocess.CompletedProcess([], 0, "", "")) as run:
            localize.build(loc)
        args = run.call_args.args[0]
        self.assertNotIn("-clonedSourcePackagesDirPath", args)
        self.assertIn(str(loc), args)
        self.assertIn("CLANG_MODULE_CACHE_PATH=/shared/ModuleCache.noindex", args)
        self.assertIn("SWIFT_EMIT_LOC_STRINGS=YES", args)
        self.assertEqual(args[-1], "build")


if __name__ == "__main__":
    unittest.main()
