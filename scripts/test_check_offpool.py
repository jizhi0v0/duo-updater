#!/usr/bin/env python3
"""Regression tests for `check_offpool`. Run by `make test`.

    python3 scripts/test_check_offpool.py

Every case names the mutation it catches. The must-hit fixtures are real shapes
from this repository as they stood at 924be257, before the hops went in — the
`lsappinfo` probe's `Task.detached`, and a wrapped `async` signature, which a
scanner that judges the `{` line alone reads as synchronous.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_offpool as co  # noqa: E402

# `AppListModel.runningBuildVersions` as it was: a detached task, which still
# runs on the cooperative pool.
DETACHED = """\
    private static func runningBuildVersions() async -> [String: String] {
        await Task.detached(priority: .utility) {
            let process = Process()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return LSAppInfoParser.runningBuildVersions(from: text)
        }.value
    }
"""

# `VendorProbeSource.zipEntryPlistValue`'s shape: the brace that opens the body
# is three lines below the word `func`, and `async` is on the brace's line but
# `func` is not.
WRAPPED_SIGNATURE = """\
    private func zipEntryPlistValue(
        url: URL, entry: String, key: String
    ) async -> Result<String, ProbeFailure> {
        let plistData = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return .success("")
    }
"""

HOPPED = """\
    private func installApp(_ newApp: URL, over target: URL) async throws {
        try await offCooperativePool {
            let process = Process()
            try process.run()
            process.waitUntilExit()
        }
    }
"""

# A synchronous helper. Out of this check's reach on purpose — whether its
# callers hop is a call-graph question — so it must NOT be reported, or the
# check turns into an exemption list over every `Process` wrapper in the repo.
SYNCHRONOUS = """\
    private static func run(_ launchPath: String) -> Int32 {
        let p = Process()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
"""

# A one-line body plus a `} else {`, the two shapes that break brace COUNTING in
# opposite directions: counted closes-first, `func f() -> Int { 5 }` pops the
# type body; counted opens-first, `} else {` nests forever.
BRACE_ARITHMETIC = """\
enum Fixture {
    static func size() -> Int { 5 }

    static func pick(_ flag: Bool) -> Int {
        if flag {
            return 1
        } else {
            return 2
        }
    }

    static func probe() async {
        let p = Process()
        p.waitUntilExit()
    }
}
"""


class OffPool(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="duo-offpool-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "Sources").mkdir()

    def write(self, text, name="Fixture.swift"):
        (self.root / "Sources" / name).write_text(text)

    def review(self):
        return co.review(self.root, roots=["Sources"])

    # Mutation: drop `Task` from the frames that count as async. The App layer's
    # two worst sites were both detached tasks, and `OffPool.swift` says in so
    # many words that a detached task is not an alternative.
    def test_a_detached_task_is_not_a_hop(self):
        self.write(DETACHED)
        found = self.review()
        self.assertEqual(len(found["offences"]), 2, found)

    # Mutation: judge the brace's own line instead of the accumulated
    # declaration. Every wrapped `async` signature then reads as synchronous and
    # the check goes green over the real thing.
    def test_a_wrapped_async_signature_is_still_async(self):
        self.write(WRAPPED_SIGNATURE)
        self.assertEqual(len(self.review()["offences"]), 2)

    def test_a_hopped_call_passes(self):
        self.write(HOPPED)
        self.assertEqual(self.review()["offences"], [])

    def test_a_synchronous_helper_is_not_reported(self):
        self.write(SYNCHRONOUS)
        self.assertEqual(self.review()["offences"], [])

    # Mutation: count braces per line rather than walking them in order. Both
    # halves of this fixture are ordinary Swift, and either miscount moves the
    # `probe()` body to the wrong depth — which silently changes the answer for
    # every function after it in the file.
    def test_brace_arithmetic_survives_one_line_bodies_and_else(self):
        self.write(BRACE_ARITHMETIC)
        found = self.review()
        self.assertEqual(len(found["offences"]), 1, found)

    def test_an_exemption_needs_a_reason(self):
        self.write("    /// offpool-lint:allow\n" + DETACHED)
        found = self.review()
        self.assertTrue(all(o[2] == "no-reason" for o in found["offences"]),
                        found)

    def test_an_exemption_with_a_reason_exempts(self):
        self.write("    /// offpool-lint:allow — fixture\n" + DETACHED)
        found = self.review()
        self.assertEqual(found["offences"], [])
        self.assertEqual(found["dead"], [])

    # The half that keeps the exemption list honest: an exemption matching
    # nothing is a standing pass for whatever is written under it next.
    def test_a_stale_exemption_fails(self):
        self.write("    /// offpool-lint:allow — fixture\n"
                   "    func f() {}\n")
        self.assertEqual(len(self.review()["dead"]), 1)

    # Both emptiness floors, because a check that inspects nothing prints the
    # same ✓ as one that inspects everything.
    def test_a_missing_root_fails(self):
        self.assertEqual(co.main(self.root, roots=["Nope"]), 1)

    def test_too_few_files_fails(self):
        self.write(HOPPED)
        self.assertEqual(co.main(self.root, roots=["Sources"]), 1)

    # The floor that catches the spellings going stale: roots intact, files
    # scanned, and nothing to look at because the call was renamed.
    def test_too_few_blocking_calls_fails(self):
        for index in range(250):
            self.write("func f() {}\n", name=f"F{index}.swift")
        self.assertEqual(
            co.main(self.root, roots=["Sources"], minimum=200), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
