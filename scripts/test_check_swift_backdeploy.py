#!/usr/bin/env python3
"""Regression tests for `check_swift_backdeploy`. Run by `make test`.

    python3 scripts/test_check_swift_backdeploy.py

The `otool` listings are trimmed copies of real ones: the Debug `duo` built from
the swift-subprocess branch, and Sparkle 2.9.6's `BinaryDelta` as embedded in the
app. Each case names the mutation it catches.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_swift_backdeploy as cb  # noqa: E402

DEBUG_DUO_L = """\
/x/duo:
\t/usr/lib/swift/libswiftCore.dylib (compatibility version 0.0.0, current version 0.0.0)
\t/usr/lib/swift/libswift_Concurrency.dylib (compatibility version 0.0.0, current version 0.0.0)
\t@rpath/libswiftCompatibilitySpan.dylib (compatibility version 0.0.0, current version 0.0.0)
"""
DEBUG_DUO_RPATHS = """\
          cmd LC_RPATH
      cmdsize 32
         path /usr/lib/swift (offset 12)
          cmd LC_RPATH
      cmdsize 32
         path @loader_path (offset 12)
          cmd LC_RPATH
      cmdsize 128
         path /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx (offset 12)
"""
BINARY_DELTA_L = """\
/x/BinaryDelta:
\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)
\t@rpath/libswiftCore.dylib (compatibility version 1.0.0, current version 1300.0.0)
\t@rpath/libswiftFoundation.dylib (compatibility version 1.0.0, current version 1.0.0)
"""
BINARY_DELTA_RPATHS = """\
          cmd LC_RPATH
      cmdsize 32
         path /usr/lib/swift (offset 12)
"""


class BackDeploy(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="ZZFixture-backdeploy-"))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def offences(self, loads, rpaths, binary, root):
        return cb.offences(binary, root, cb.load_paths(loads), cb.run_paths(rpaths),
                           binary.parent)

    def test_the_parsers_read_real_listings(self):
        self.assertIn("@rpath/libswiftCompatibilitySpan.dylib", cb.load_paths(DEBUG_DUO_L))
        self.assertEqual(cb.run_paths(DEBUG_DUO_RPATHS)[:2], ["/usr/lib/swift", "@loader_path"])

    # Mutation: let `/usr/lib/swift` satisfy a shim too → the Debug `duo` passes,
    # though an OS before 26 has no such library there.
    def test_an_unembedded_span_shim_fails(self):
        binary = self.dir / "duo"
        found = self.offences(DEBUG_DUO_L, DEBUG_DUO_RPATHS, binary, binary)
        self.assertEqual([dep for dep, _ in found], ["@rpath/libswiftCompatibilitySpan.dylib"])

    # Mutation: count absolute run paths → a build-machine path satisfies the
    # shim. Here it even points into the bundle being checked (as a derived-data
    # products path would at build time), which the user's copy will not be at.
    def test_an_absolute_run_path_does_not_count(self):
        app = self.dir / "ZZFixture.app"
        frameworks = app / "Contents/Frameworks"
        frameworks.mkdir(parents=True)
        (frameworks / "libswiftCompatibilitySpan.dylib").write_bytes(b"")
        rpaths = f"         path {frameworks} (offset 12)\n"
        binary = app / "Contents/MacOS/ZZFixture"
        self.assertEqual(len(self.offences(DEBUG_DUO_L, rpaths, binary, app)), 1)

    # Mutation: never accept an embedded copy → an app that embeds the shim
    # (what Xcode is meant to do for an app) fails.
    def test_a_shim_embedded_in_the_bundle_passes(self):
        app = self.dir / "ZZFixture.app"
        macos, frameworks = app / "Contents/MacOS", app / "Contents/Frameworks"
        macos.mkdir(parents=True)
        frameworks.mkdir(parents=True)
        (frameworks / "libswiftCompatibilitySpan.dylib").write_bytes(b"")
        rpaths = "         path @executable_path/../Frameworks (offset 12)\n"
        self.assertEqual(self.offences(DEBUG_DUO_L, rpaths, macos / "ZZFixture", app), [])

    # Mutation: a lone binary's directory counted as shipped (`root = parent`) →
    # a shim sitting in the build products directory passes, though
    # `build-cli.sh` copies only the binary.
    def test_a_shim_beside_a_lone_binary_is_not_embedded(self):
        binary = self.dir / "duo"
        binary.write_bytes(b"\xcf\xfa\xed\xfe")
        (self.dir / "libswiftCompatibilitySpan.dylib").write_bytes(b"")
        original = cb.otool
        cb.otool = lambda flag, _: DEBUG_DUO_L if flag == "-L" else DEBUG_DUO_RPATHS
        try:
            checked, found = cb.check(binary)
        finally:
            cb.otool = original
        self.assertEqual((checked, len(found)), (1, 1))

    # Mutation: `/usr/lib/swift` not honoured → Sparkle's own BinaryDelta, which
    # links the OS runtime the pre-5.1 way, fails every app build.
    def test_the_os_runtime_by_run_path_passes(self):
        app = self.dir / "ZZFixture.app"
        binary = app / "Contents/MacOS/BinaryDelta"
        self.assertEqual(self.offences(BINARY_DELTA_L, BINARY_DELTA_RPATHS, binary, app), [])

    # Mutation: no "nothing to inspect" floor → a wrong path passes.
    def test_a_path_without_mach_o_fails(self):
        (self.dir / "notes.txt").write_text("x")
        self.assertEqual(cb.main([str(self.dir)]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
