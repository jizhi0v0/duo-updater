#!/usr/bin/env python3
"""Regression tests for `check_swift_backdeploy`. Run by `make test`.

    python3 scripts/test_check_swift_backdeploy.py

The `otool -l` listings are trimmed copies of real ones: the Debug `duo` built
from the swift-subprocess branch, and Sparkle 2.9.6's `BinaryDelta` as embedded
in the app. One test reads a real Mach-O — a copy of the toolchain's own Span
shim, only ever read by `otool`, never loaded or run. Each case names the
mutation it catches.
"""

import glob
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_swift_backdeploy as cb  # noqa: E402

DEBUG_DUO = """\
Load command 12
          cmd LC_LOAD_DYLIB
      cmdsize 56
         name /usr/lib/swift/libswiftCore.dylib (offset 24)
   time stamp 2 Thu Jan  1 08:00:02 1970
Load command 13
          cmd LC_LOAD_DYLIB
      cmdsize 64
         name @rpath/libswiftCompatibilitySpan.dylib (offset 24)
   time stamp 2 Thu Jan  1 08:00:02 1970
Load command 14
          cmd LC_RPATH
      cmdsize 32
         path /usr/lib/swift (offset 12)
Load command 15
          cmd LC_RPATH
      cmdsize 32
         path @loader_path (offset 12)
Load command 16
          cmd LC_RPATH
      cmdsize 128
         path /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx (offset 12)
"""
BINARY_DELTA = """\
Load command 10
          cmd LC_LOAD_DYLIB
      cmdsize 56
         name @rpath/libswiftCore.dylib (offset 24)
Load command 11
          cmd LC_LOAD_WEAK_DYLIB
      cmdsize 64
         name @rpath/libswiftFoundation.dylib (offset 24)
Load command 12
          cmd LC_RPATH
      cmdsize 32
         path /usr/lib/swift (offset 12)
"""
EXECUTE_HEADER = """\
/x/y:
Mach header
      magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags
MH_MAGIC_64    ARM64        ALL  0x00     EXECUTE    51       6624   NOUNDEFS DYLDLINK TWOLEVEL PIE
"""
DYLIB_HEADER = EXECUTE_HEADER.replace("EXECUTE", "  DYLIB")


def toolchain_span_shim():
    """The Span shim shipped with the active toolchain, or None."""
    swiftc = subprocess.run(["xcrun", "--find", "swiftc"], capture_output=True, text=True).stdout.strip()
    if not swiftc:
        return None
    usr = pathlib.Path(swiftc).resolve().parent.parent
    hits = sorted(glob.glob(str(usr / "lib/swift-*/macosx/libswiftCompatibilitySpan.dylib")))
    return pathlib.Path(hits[-1]) if hits else None


class BackDeploy(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="ZZFixture-backdeploy-"))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def offences(self, listing, binary, root):
        return cb.offences(binary, root, cb.load_paths(listing), cb.run_paths(listing),
                           binary.parent)

    def with_otool(self, listing, header):
        """Run `cb.check` against canned `otool` output."""
        original = cb.otool
        cb.otool = lambda flag, _: header if flag == "-hv" else listing
        self.addCleanup(setattr, cb, "otool", original)

    def test_the_parsers_read_real_listings(self):
        self.assertEqual(cb.load_paths(DEBUG_DUO), [
            "/usr/lib/swift/libswiftCore.dylib", "@rpath/libswiftCompatibilitySpan.dylib"])
        self.assertEqual(cb.run_paths(DEBUG_DUO)[:2], ["/usr/lib/swift", "@loader_path"])
        self.assertTrue(cb.is_executable(EXECUTE_HEADER))
        self.assertFalse(cb.is_executable(DYLIB_HEADER))

    # The false positive the round-2 review found, on a real Mach-O: a dylib's
    # `otool -L` starts with its own install name, and the Span shim's is
    # `/usr/lib/swift/libswiftCompatibilitySpan.dylib`. An app embedding the shim
    # correctly must pass.
    #
    # Mutation: `load_paths` back to `otool -L` parsing → the embedded shim is
    # flagged as "a shim at a fixed path".
    def test_a_correctly_embedded_real_shim_passes(self):
        shim = toolchain_span_shim()
        self.assertIsNotNone(shim, "no libswiftCompatibilitySpan.dylib in the active toolchain")
        frameworks = self.dir / "ZZFixture.app/Contents/Frameworks"
        frameworks.mkdir(parents=True)
        copy = frameworks / "libswiftCompatibilitySpan.dylib"
        shutil.copyfile(shim, copy)
        # Its listing really does carry its own name first — otherwise this test
        # would not be exercising the case.
        own = subprocess.run(["otool", "-D", str(copy)], capture_output=True, text=True).stdout
        self.assertIn("/usr/lib/swift/libswiftCompatibilitySpan.dylib", own)
        checked, found = cb.check(self.dir / "ZZFixture.app")
        self.assertEqual((checked, found), (1, []))

    # Mutation: let `/usr/lib/swift` satisfy a shim too → the Debug `duo` passes,
    # though an OS before 26 has no such library there.
    def test_an_unembedded_span_shim_fails(self):
        binary = self.dir / "duo"
        found = self.offences(DEBUG_DUO, binary, binary)
        self.assertEqual([dep for dep, _ in found], ["@rpath/libswiftCompatibilitySpan.dylib"])

    # Mutation: count absolute run paths → a build-machine path satisfies the
    # shim. Here it even points into the bundle being checked (as a derived-data
    # products path would at build time), which the user's copy will not be at.
    def test_an_absolute_run_path_does_not_count(self):
        app = self.dir / "ZZFixture.app"
        frameworks = app / "Contents/Frameworks"
        frameworks.mkdir(parents=True)
        (frameworks / "libswiftCompatibilitySpan.dylib").write_bytes(b"")
        listing = DEBUG_DUO.split("Load command 14")[0] + f"          cmd LC_RPATH\n         path {frameworks} (offset 12)\n"
        binary = app / "Contents/MacOS/ZZFixture"
        self.assertEqual(len(self.offences(listing, binary, app)), 1)

    # Mutation: never accept an embedded copy → an app that embeds the shim
    # (what Xcode is meant to do for an app) fails.
    def test_a_shim_embedded_in_the_bundle_passes(self):
        app = self.dir / "ZZFixture.app"
        macos, frameworks = app / "Contents/MacOS", app / "Contents/Frameworks"
        macos.mkdir(parents=True)
        frameworks.mkdir(parents=True)
        (frameworks / "libswiftCompatibilitySpan.dylib").write_bytes(b"")
        listing = DEBUG_DUO.split("Load command 14")[0] + "          cmd LC_RPATH\n         path @executable_path/../Frameworks (offset 12)\n"
        self.assertEqual(self.offences(listing, macos / "ZZFixture", app), [])

    # A nested executable (Sparkle's `Updater.app`, an XPC service) resolves
    # `@executable_path` against its own directory, not the app's Contents/MacOS.
    #
    # Mutation: `@executable_path` always the outer `Contents/MacOS` → the
    # nested executable's own embedded shim is not found.
    def test_a_nested_executable_uses_its_own_executable_path(self):
        app = self.dir / "ZZFixture.app"
        nested = app / "Contents/Frameworks/ZZKit.framework/Versions/B/ZZHelper.app/Contents"
        (nested / "MacOS").mkdir(parents=True)
        (nested / "Frameworks").mkdir(parents=True)
        (nested / "Frameworks/libswiftCompatibilitySpan.dylib").write_bytes(b"")
        helper = nested / "MacOS/ZZHelper"
        helper.write_bytes(b"\xcf\xfa\xed\xfe")
        listing = DEBUG_DUO.split("Load command 14")[0] + "          cmd LC_RPATH\n         path @executable_path/../Frameworks (offset 12)\n"
        self.with_otool(listing, EXECUTE_HEADER)
        checked, found = cb.check(app)
        self.assertEqual((checked, found), (1, []))

    # Mutation: a lone binary's directory counted as shipped (`root = parent`) →
    # a shim sitting in the build products directory passes, though
    # `build-cli.sh` copies only the binary.
    def test_a_shim_beside_a_lone_binary_is_not_embedded(self):
        binary = self.dir / "duo"
        binary.write_bytes(b"\xcf\xfa\xed\xfe")
        (self.dir / "libswiftCompatibilitySpan.dylib").write_bytes(b"")
        self.with_otool(DEBUG_DUO, EXECUTE_HEADER)
        checked, found = cb.check(binary)
        self.assertEqual((checked, len(found)), (1, 1))

    # Mutation: `/usr/lib/swift` not honoured → Sparkle's own BinaryDelta, which
    # links the OS runtime the pre-5.1 way, fails every app build.
    def test_the_os_runtime_by_run_path_passes(self):
        app = self.dir / "ZZFixture.app"
        binary = app / "Contents/MacOS/BinaryDelta"
        self.assertEqual(self.offences(BINARY_DELTA, binary, app), [])

    # Mutation: no "nothing to inspect" floor → a wrong path passes.
    def test_a_path_without_mach_o_fails(self):
        (self.dir / "notes.txt").write_text("x")
        self.assertEqual(cb.main([str(self.dir)]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
