import Testing
import Foundation
@testable import DuoUpdaterCore

/// Review of #763: `BundleArchive` kept the running `aa` in a single slot, on the
/// reading that only one runs at a time. The transfer queue archives in the
/// background while the workbench extracts a backup to compare it with, so a
/// second run overwrote the first, the first's `defer` then cleared the second's
/// entry, and the terminate on quit cancelled whichever happened to be left —
/// orphaning the archive it exists to kill, which finishes and renames a complete
/// archive into place that no sidecar records.
@Suite struct BundleArchiveRunningChildrenTests {

    /// A task that ends only by being cancelled, so nothing here depends on
    /// timing. It sleeps rather than spinning, and **is never awaited**: under a
    /// mutation that breaks cancelling, awaiting it would hang the suite instead
    /// of failing it, which is a worse test than no test.
    private func neverEnding() -> Task<ChildProcess.Outcome, Error> {
        Task {
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
    }

    @Test func everyRunningChildIsCancelledNotJustTheLatest() {
        let running = RunningChildren()
        let first = neverEnding(), second = neverEnding()
        defer { first.cancel(); second.cancel() }
        _ = running.add(first)
        _ = running.add(second)
        #expect(running.count == 2, "the second must not displace the first")

        running.cancelAll()
        #expect(first.isCancelled)
        #expect(second.isCancelled)
    }

    @Test func aFinishedRunRemovesItsOwnEntryAndNoOther() {
        let running = RunningChildren()
        let first = neverEnding(), second = neverEnding()
        defer { first.cancel(); second.cancel() }
        let firstToken = running.add(first)
        _ = running.add(second)

        running.remove(firstToken)
        #expect(running.count == 1)
        // Removing the same token twice — what a stale `defer` does — must not
        // take the other run's entry with it.
        running.remove(firstToken)
        #expect(running.count == 1)

        running.cancelAll()
        #expect(second.isCancelled, "the run still going must still be reachable")
    }
}
