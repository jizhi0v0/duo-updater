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


# A semaphore and a group wait, the two CLAUDE.md names that the first version
# of BLOCKING did not carry — while `GitHub.run`, added in the same PR, waits on
# a semaphore of its own.
SEMAPHORE = """\
    private func drain() async -> Data {
        let drained = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        drained.wait()
        group.wait()
        return Data()
    }
"""

# An async wait is not a parked thread. Both of these are real lines from
# `AppListModel`, and reporting them would be the kind of noise that gets a gate
# switched off.
AWAITED_WAIT = """\
    private func gated() async {
        await Self.prewarmNetworkGate.wait()
        await gate?.wait()
    }
"""

# GCD closures do not run on the cooperative pool, so blocking inside one is the
# fix. ~10 sites in this repo look like this, `ArchiveExtractor.run`'s stderr
# drain among them.
GCD_CLOSURE = """\
    private func drainBoth() async {
        errQueue.async {
            errBox.data = errHandle.readDataToEndOfFile()
        }
        DispatchQueue.global().async {
            process.waitUntilExit()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            process.waitUntilExit()
        }
        let work = DispatchWorkItem {
            process.waitUntilExit()
        }
        Thread {
            process.waitUntilExit()
        }.start()
    }
"""

# ⚠️ `.sync { }` runs the block on the CALLING thread, so it is NOT a hop. This
# is the one member of the GCD family that must still be reported, and the
# distinction is the reason `GCD` does not simply match `Dispatch`.
GCD_SYNC_IS_NOT_A_HOP = """\
    private func inline() async {
        queue.sync {
            process.waitUntilExit()
        }
    }
"""

# A live exemption whose reason is a PREFIX of a stale one's. Under containment
# matching, the live text is found inside the stale line, so the stale exemption
# reads as used and is never reviewed again.
PREFIX_MARKER = """\
    /// offpool-lint:allow — network
    func probe() async {
        process.waitUntilExit()
    }

    /// offpool-lint:allow — network retry budget
    func settled() {}
"""

BLOCK_COMMENT = """\
    private func probe() async {
        /* a closing brace in prose: }
           and another } here */
        process.waitUntilExit()
    }
"""

# `/*` inside a `//` comment — `Scan/AppRuntime.swift:252` really does this.
SLASH_STAR_INSIDE_LINE_COMMENT = """\
    private func probe() async {
        // `Contents/MacOS/*.app` is also where subprocesses live
        process.waitUntilExit()
    }
"""

GET_ASYNC = """\
struct Fixture {
    var token: String? {
        get async {
            process.waitUntilExit()
            return nil
        }
    }
}
"""

# A default closure argument inside a wrapped signature. Its braces balance on
# their own line and open no body, so resetting the accumulated declaration
# there loses the `async` two lines above.
DEFAULT_CLOSURE_ARGUMENT = """\
    private func install(
        _ app: URL,
        onDone: @Sendable () -> Void = { },
        onStage: @Sendable (Int) -> Void = { _ in }
    ) async throws {
        process.waitUntilExit()
    }
"""

# An extended literal carrying quotes AND a brace, which is what every regex in
# this repo looks like.
# One bare quote and then a brace: the naive pair-matching stripper consumes
# `"say "` and leaves the `}` behind as code, which pops the function's frame and
# makes everything after it read as type-level — silently green.
EXTENDED_STRING = """\
    private func probe() async {
        let pattern = #"say " then }"#
        process.waitUntilExit()
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

    # CLAUDE.md names `DispatchGroup.wait()` and `DispatchSemaphore.wait()` in
    # the same breath as `waitUntilExit`; the first BLOCKING list carried
    # neither, while this PR's own `GitHub.run` added a semaphore wait.
    def test_semaphore_and_group_waits_are_blocking(self):
        self.write(SEMAPHORE)
        self.assertEqual(len(self.review()["offences"]), 2, self.review())

    # …and the cost of carrying `.wait()`: `await x.wait()` must not be reported.
    def test_an_awaited_wait_is_not_a_parked_thread(self):
        self.write(AWAITED_WAIT)
        self.assertEqual(self.review()["offences"], [])

    # FALSE POSITIVE this gate shipped with: a GCD closure inside an `async func`
    # inherited the async verdict, so ~10 correct sites in this repo were
    # reported as violations. Blocking inside `DispatchQueue.async` is the fix.
    def test_gcd_closures_are_not_the_cooperative_pool(self):
        self.write(GCD_CLOSURE)
        self.assertEqual(self.review()["offences"], [], self.review())

    # The other half, which keeps the fix above from becoming a hole: `.sync`
    # runs the block on the calling thread.
    def test_dispatch_sync_is_still_the_calling_thread(self):
        self.write(GCD_SYNC_IS_NOT_A_HOP)
        self.assertEqual(len(self.review()["offences"]), 1, self.review())

    # Mutation: match markers by substring. A live `…allow — network retry
    # budget` then covers a stale `…allow — network`, and the stale one is never
    # reviewed again — the exact hole the dead-exemption half exists to close.
    def test_a_stale_marker_is_not_covered_by_a_longer_live_one(self):
        self.write(PREFIX_MARKER)
        dead = self.review()["dead"]
        self.assertEqual([line for _, line in dead], [6], self.review())

    def test_a_brace_inside_a_block_comment_is_not_a_scope(self):
        self.write(BLOCK_COMMENT)
        self.assertEqual(len(self.review()["offences"]), 1, self.review())

    # …and `/*` inside a line comment must not open one.
    def test_a_block_opener_inside_a_line_comment_is_inert(self):
        self.write(SLASH_STAR_INSIDE_LINE_COMMENT)
        self.assertEqual(len(self.review()["offences"]), 1, self.review())

    def test_an_async_getter_is_an_async_scope(self):
        self.write(GET_ASYNC)
        self.assertEqual(len(self.review()["offences"]), 1, self.review())

    def test_a_default_closure_argument_does_not_end_the_signature(self):
        self.write(DEFAULT_CLOSURE_ARGUMENT)
        self.assertEqual(len(self.review()["offences"]), 1, self.review())

    def test_an_extended_string_literal_is_not_code(self):
        self.write(EXTENDED_STRING)
        self.assertEqual(len(self.review()["offences"]), 1, self.review())

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
