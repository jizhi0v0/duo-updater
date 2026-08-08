import Testing
import Foundation
@testable import DuoUpdaterCore

/// The split install pipeline: a *download* permit bounds concurrent fetches,
/// an *apply* permit bounds concurrent extract/verify/swap — independently.
/// The two pools must never share slots or wake each other, or the pipelining
/// they exist for (download while another install swaps) silently collapses
/// back into one coupled gate.
struct InstallPermitsTests {

    /// Exhausting one pool must leave the other untouched, and a permit freed
    /// in one pool must not wake a waiter parked in the other.
    @Test func poolsAreIndependent() async {
        let permits = InstallPermits(downloads: 2, applies: 1)
        defer {
            // Drain anything left parked so the test can't strand a waiter.
            permits.signalDownload(); permits.signalDownload()
            permits.signalApply(); permits.signalApply()
        }

        await permits.waitForDownload()
        await permits.waitForDownload()
        await permits.waitForApply()
        #expect(permits.availableDownloadPermits == 0)
        #expect(permits.availableApplyPermits == 0)

        // A third download parks while both pools are exhausted. It must not
        // eat an apply slot, and must not be woken by an apply release.
        async let parkedDownload: Void = permits.waitForDownload()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(permits.availableDownloadPermits == 0)
        #expect(permits.availableApplyPermits == 0)

        permits.signalApply()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(permits.availableApplyPermits == 1)          // apply slot freed
        #expect(permits.availableDownloadPermits == 0)       // download waiter still parked

        permits.signalDownload()
        await parkedDownload                                  // the freed slot went to the waiter
        #expect(permits.availableDownloadPermits == 0)        // …not back to the pool
    }

    /// The headline behavior: while apply slots are fully held by in-flight
    /// swaps, a download can still start — the whole point of the split.
    @Test func downloadsProceedWhileAppliesHeld() async {
        let permits = InstallPermits(downloads: 4, applies: 2)
        defer {
            permits.signalApply(); permits.signalApply()
            permits.signalDownload(); permits.signalDownload(); permits.signalDownload()
        }

        await permits.waitForApply()
        await permits.waitForApply()
        #expect(permits.availableApplyPermits == 0)
        #expect(permits.availableDownloadPermits == 4)        // untouched by held applies

        await permits.waitForDownload()                       // completes immediately
        #expect(permits.availableDownloadPermits == 3)
        permits.signalDownload()
    }

    /// A download permit must not be held past its fetch: acquiring the apply
    /// permit while a download permit is still held would re-couple the two
    /// stages (the apply wait would pin a network slot). Both `with*` helpers
    /// hand their permit back before returning.
    @Test func scopedHelpersReleaseBeforeReturning() async throws {
        struct Boom: Error {}
        let permits = InstallPermits(downloads: 1, applies: 1)

        // Success path: the permit is back in the pool once the body returns.
        let value = try await permits.withDownloadPermit { 42 }
        #expect(value == 42)
        #expect(permits.availableDownloadPermits == 1)

        // Error path: the permit is back even though the body threw.
        do {
            try await permits.withDownloadPermit { throw Boom() }
            Issue.record("expected Boom")
        } catch is Boom {}
        do {
            try await permits.withApplyPermit { throw Boom() }
            Issue.record("expected Boom")
        } catch is Boom {}
        #expect(permits.availableDownloadPermits == 1)
        #expect(permits.availableApplyPermits == 1)
    }
}
