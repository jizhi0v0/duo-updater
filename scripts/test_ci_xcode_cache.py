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

    def test_mini_reuses_products_but_only_after_a_complete_run(self):
        checkout = self.root
        slot_parent = checkout / "runner"
        slot_parent.mkdir()
        workspace = slot_parent / "checkout"
        # The helper stamps the current checkout, just as it does in Actions.
        subprocess.run(["git", "init", "-q", str(workspace)], check=True)
        env_file = checkout / "env"
        old = Path.cwd()
        os.chdir(workspace)
        self.addCleanup(os.chdir, old)
        runner_temp = checkout / "_temp"
        runner_temp.mkdir()
        with mock.patch.dict(os.environ, {"GITHUB_ENV": str(env_file), "RUNNER_TEMP": str(runner_temp)}), \
             mock.patch.object(cache.mini, "MIN_FREE_BYTES", 0):
            cache.prepare_mini(workspace, "platform")
            slot = cache.mini_slot(workspace)
            key = cache.cache_key(workspace, "platform")
            for name in ("build", "localizable"):
                dd = slot / name
                (dd / "Build").mkdir(parents=True)
                (dd / "Build/product").touch()
                (dd / "app-tests-123.log").touch()
                (dd / "app-tests-123.xcresult").mkdir()
                (dd / "Logs").mkdir()
            cache.save_mini(workspace, key)
            self.assertEqual((slot / cache.mini.READY).read_text(), key)
            cache.prepare_mini(workspace, "platform")
            for name in ("build", "localizable"):
                self.assertEqual(sorted(p.name for p in (slot / name).iterdir()), ["Build"])
                self.assertTrue((slot / name / "Build/product").is_file())
            # Cancel before save. The next job must discard both build trees.
            cache.prepare_mini(workspace, "platform")
            self.assertEqual(list(slot.iterdir()), [])

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


class MiniCompilationCache(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        runner_temp = self.root / "_temp"
        runner_temp.mkdir()
        env = mock.patch.dict(os.environ, {"RUNNER_TEMP": str(runner_temp)})
        env.start()
        self.addCleanup(env.stop)
        self.slot = cache.mini_cas_slot()
        self.ready = self.slot / cache.mini.READY
        disk_usage = mock.patch.object(cache.shutil, "disk_usage")
        self.disk = disk_usage.start()
        self.addCleanup(disk_usage.stop)
        self.disk.return_value.free = 20 * 1024**3

    def prepare(self, platform="platform", persistent_build=True):
        build_slot = cache.mini_slot(self.workspace) if persistent_build else None
        # Exercise retention independently of the machine's temporary paths.
        with mock.patch.object(cache, "supports_cas_paths", return_value=True):
            return cache.prepare_mini_cas(self.workspace, platform, build_slot)

    def test_rejects_macos_path_aliases_and_xcconfig_syntax(self):
        self.assertTrue(cache.supports_cas_paths(Path("/Users/runner/_work/duo-updater")))
        for path in ("/private/tmp/checkout", "/private/var/checkout", "/Users/runner/work space",
                     "/Users/runner/work$(SETTING)"):
            with self.subTest(path=path):
                self.assertFalse(cache.supports_cas_paths(Path(path)))

    def test_success_survives_a_derived_data_reset_but_a_cancelled_run_does_not(self):
        config = Path(self.prepare()).read_text()
        self.assertIn(f"COMPILATION_CACHE_CAS_PATH = {self.slot}\n", config)
        packages = cache.mini_slot(self.workspace) / "build/SourcePackages"
        for compiler in ("SWIFT", "CLANG"):
            self.assertIn(
                f"{compiler}_OTHER_PREFIX_MAPPINGS = "
                f"{self.workspace}=/^duo-source {packages}=/^duo-packages\n", config
            )
        product = self.slot / "replay-data"
        product.touch()
        cache.save_mini_cas("platform")
        derived_data = cache.mini_slot(self.workspace)
        derived_data.mkdir()
        shutil.rmtree(derived_data)
        # Even if the next checkout has a different parent, its runner is the
        # same. Only the per-checkout DerivedData and source mapping change.
        self.workspace = self.root / "other" / "checkout"
        self.workspace.mkdir(parents=True)

        self.assertTrue(self.prepare())
        self.assertTrue(product.is_file())
        self.assertFalse(self.ready.exists())
        self.assertTrue(self.prepare())  # Previous job ended before the save step.
        self.assertFalse(product.exists())

    def test_platform_change_and_excess_size_drop_old_entries(self):
        for platform, oversize in (("new-platform", False), ("platform", True)):
            with self.subTest(platform=platform, oversize=oversize):
                self.prepare()
                product = self.slot / "replay-data"
                product.touch()
                cache.save_mini_cas("platform")
                with mock.patch.object(cache, "cas_over_budget", return_value=oversize):
                    self.assertTrue(self.prepare(platform))
                self.assertFalse(product.exists())

    def test_disk_pressure_evicts_cas_and_falls_back(self):
        self.prepare()
        cache.save_mini_cas("platform")
        self.disk.return_value.free = cache.mini.MIN_FREE_BYTES
        self.assertIsNone(self.prepare())
        self.assertFalse(self.slot.exists())
        self.assertIsNone(self.prepare(persistent_build=False))

    def test_invalid_checkout_path_still_evicts_under_disk_pressure(self):
        self.prepare()
        cache.save_mini_cas("platform")
        self.disk.return_value.free = cache.mini.MIN_FREE_BYTES
        # Supply a valid CAS root alongside a checkout with xcconfig syntax.
        with mock.patch.object(cache, "supports_cas_paths", side_effect=lambda *paths: paths == (self.slot,)):
            self.assertIsNone(cache.prepare_mini_cas(self.workspace, "platform", cache.mini_slot(self.workspace)))
        self.assertFalse(self.slot.exists())

    def test_symlink_slot_cannot_be_used_as_a_cache_or_deleted(self):
        target = self.root / "unrelated"
        target.mkdir()
        (target / "keep").touch()
        self.slot.symlink_to(target, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.prepare()
        with self.assertRaises(ValueError):
            cache.save_mini_cas("platform")
        self.assertTrue((target / "keep").is_file())


if __name__ == "__main__":
    unittest.main()
