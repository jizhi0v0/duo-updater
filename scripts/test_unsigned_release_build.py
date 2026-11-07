#!/usr/bin/env python3
"""Reusing CI's project/cache must still compile and check both shipping schemes."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("unsigned-release-build.sh")


class ReleaseBuild(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        (self.root / "App").mkdir()
        (self.root / "App/project.yml").write_text("spec")
        (self.root / "App/Package.resolved").write_text("committed pins")
        shutil.copy(SCRIPT, self.root / "scripts/unsigned-release-build.sh")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls"
        self.stub("xcodegen", 'echo generate >> "$CALLS"\nmkdir -p DuoUpdater.xcodeproj\ntouch DuoUpdater.xcodeproj/project.pbxproj')
        pinned = self.root / "scripts/pinned-xcodegen.sh"
        pinned.write_text('#!/bin/sh\nprintf "%s\\n" "$FAKE_BIN/xcodegen"\n')
        pinned.chmod(0o755)
        self.stub("xcodebuild", '''printf '%s\\n' "$*" >> "$CALLS"
if [ "${FAIL_BUILD:-0}" = 1 ]; then exit 65; fi
if [ "${OMIT_PRODUCTS:-0}" != 1 ]; then
  mkdir -p "$UNSIGNED_RELEASE_DD/Build/Products/Release/DuoUpdater.app/Contents/MacOS"
  touch "$UNSIGNED_RELEASE_DD/Build/Products/Release/DuoUpdater.app/Contents/MacOS/DuoUpdater"
  touch "$UNSIGNED_RELEASE_DD/Build/Products/Release/duo-cli"
  chmod +x "$UNSIGNED_RELEASE_DD/Build/Products/Release/DuoUpdater.app/Contents/MacOS/DuoUpdater" "$UNSIGNED_RELEASE_DD/Build/Products/Release/duo-cli"
fi''')
        self.stub("lipo", 'printf "%s\\n" "${FAKE_ARCHS:-arm64}"')

    def stub(self, name, body):
        p = self.bin / name
        p.write_text("#!/bin/sh\n" + body + "\n")
        p.chmod(0o755)

    def run_build(self, **extra):
        env = {**os.environ, "PATH": str(self.bin) + ":/usr/bin:/bin", "FAKE_BIN": str(self.bin),
               "CALLS": str(self.log), "UNSIGNED_RELEASE_DD": str(self.root / "dd"),
               "XCODE_CLONED_SOURCE_PACKAGES": str(self.root / "dd/SourcePackages"),
               "XCODE_PROJECT_PREGENERATED": "0", **extra}
        return subprocess.run(["/bin/bash", str(self.root / "scripts/unsigned-release-build.sh")],
                              env=env, capture_output=True, text=True)

    def test_a_warm_pregenerated_project_still_builds_both_schemes(self):
        project = self.root / "App/DuoUpdater.xcodeproj"
        project.mkdir()
        (project / "project.pbxproj").write_text("generated for this revision")
        run = self.run_build(XCODE_PROJECT_PREGENERATED="1")
        self.assertEqual(run.returncode, 0, run.stderr)
        calls = self.log.read_text().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertIn("-scheme DuoUpdater -configuration Release", calls[0])
        self.assertIn("-scheme duo-cli -configuration Release", calls[1])
        for call in calls:
            self.assertIn("-onlyUsePackageVersionsFromResolvedFile", call)
            self.assertIn("-clonedSourcePackagesDirPath", call)
            self.assertIn("CODE_SIGNING_ALLOWED=NO", call)
            self.assertIn("ARCHS=arm64", call)
            self.assertTrue(call.endswith(" build"))
        pins = project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        self.assertEqual(pins.read_text(), "committed pins")

    def test_local_runs_regenerate_even_if_a_project_already_exists(self):
        project = self.root / "App/DuoUpdater.xcodeproj"
        project.mkdir()
        (project / "project.pbxproj").write_text("old project, new source files")
        run = self.run_build()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(self.log.read_text().splitlines()[0], "generate")

    def test_build_errors_and_missing_products_still_fail(self):
        run = self.run_build(FAIL_BUILD="1")
        self.assertEqual(run.returncode, 65)
        run = self.run_build(OMIT_PRODUCTS="1")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("no executable", run.stderr)

    def test_intel_and_universal_products_are_rejected(self):
        for architectures in ("x86_64", "x86_64 arm64"):
            with self.subTest(architectures=architectures):
                run = self.run_build(FAKE_ARCHS=architectures)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn("not arm64-only", run.stderr)


if __name__ == "__main__":
    unittest.main()
