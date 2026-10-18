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

    // MARK: - Cancellation while queued

    /// The headline of the cancellable waits: a queued install the user cancels
    /// leaves the queue NOW, not when some other download or swap happens to
    /// finish. Nothing is signalled before the cancelled waiter is expected
    /// back, so a wait that only notices cancellation on wake-up never returns
    /// inside the bound. The others keep their places in line, and the pool's
    /// count is not touched by the waiter that left.
    ///
    /// Mutation: make the cancellation handler a no-op → `cancelled` is not
    /// back within the bound and this test fails.
    @Test func cancellingAQueuedWaiterThrowsAndKeepsTheOthersInOrder() async throws {
        let permits = InstallPermits(downloads: 1, applies: 1)
        let order = Order()
        await permits.waitForDownload()                       // the slot everyone queues behind

        let first = Task { try await permits.waitForDownloadOrCancel(); order.append("first") }
        #expect(await Self.parked(permits, downloads: 1))
        let cancelled = Task { try await permits.waitForDownloadOrCancel(); order.append("cancelled") }
        #expect(await Self.parked(permits, downloads: 2))
        let last = Task { try await permits.waitForDownloadOrCancel(); order.append("last") }
        #expect(await Self.parked(permits, downloads: 3))

        cancelled.cancel()
        let threw = Flag()
        let returned = await Self.within(seconds: 10) {
            do { try await cancelled.value } catch is CancellationError { threw.set() } catch {}
        }
        #expect(returned, "a cancelled waiter must leave the queue without a permit being freed")
        #expect(threw.isSet)
        #expect(permits.parkedDownloadWaiters == 2)
        #expect(permits.availableDownloadPermits == 0)       // it took nothing and gave nothing back

        // The two that stayed are served in the order they queued. Each task
        // keeps the permit it gets; the test's next signal is what hands that
        // slot on, so after the last one the pool is back to its one permit.
        permits.signalDownload()
        try await first.value
        // A mutant that never woke `cancelled` still has it queued between the
        // two: serve it, or `last` would wait forever behind it.
        if !returned { permits.signalDownload(); _ = try? await cancelled.value }
        permits.signalDownload()
        try await last.value
        #expect(order.values == ["first", "last"])
        permits.signalDownload()
        #expect(permits.availableDownloadPermits == 1)
        #expect(permits.parkedDownloadWaiters == 0)
    }

    /// A task already cancelled when it asks never takes a permit, even when
    /// one is free — the fast path must not hand out a slot the caller would
    /// then have to remember to return.
    @Test func anAlreadyCancelledTaskThrowsWithoutTakingAPermit() async {
        let permits = InstallPermits(downloads: 1, applies: 1)
        let outcome = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await permits.waitForApplyOrCancel()
                return "acquired"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other"
            }
        }.value
        #expect(outcome == "cancelled")
        #expect(permits.availableApplyPermits == 1)
    }

    /// The scoped helper with `cancellable: true` — the form the coordinator
    /// uses for the download — leaves the queue on cancel without ever running
    /// its body.
    @Test func cancellableScopedHelperSkipsTheBodyWhenCancelledInQueue() async {
        let permits = InstallPermits(downloads: 1, applies: 1)
        await permits.waitForDownload()
        let ran = Flag()
        let queued = Task {
            try await permits.withDownloadPermit(cancellable: true) { ran.set() }
        }
        #expect(await Self.parked(permits, downloads: 1))
        queued.cancel()
        let returned = await Self.within(seconds: 10) { _ = try? await queued.value }
        #expect(returned)
        #expect(!ran.isSet)
        permits.signalDownload()
        if !returned { _ = try? await queued.value }          // a mutant: let it finish
        #expect(permits.availableDownloadPermits == 1)
    }

    /// The non-cancellable form `InPlaceSwap.elevationPanel` relies on: a
    /// cancelled waiter stays in line and, when its turn comes, gets the permit
    /// like anyone else. The swap it guards must not be abandoned half-way.
    @Test func theNonCancellableWaitIgnoresCancellation() async throws {
        let permits = InstallPermits(downloads: 0, applies: 1)
        await permits.waitForApply()
        let got = Flag()
        let waiter = Task {
            try await permits.withApplyPermit { got.set() }
        }
        #expect(await Self.parked(permits, applies: 1))
        waiter.cancel()
        // Still queued after the cancel: the handler-free path has nothing to
        // wake it, so the count stays at one however long we look.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(permits.parkedApplyWaiters == 1)
        #expect(!got.isSet)

        permits.signalApply()
        try await waiter.value                               // ran its body, did not throw
        #expect(got.isSet)
        #expect(permits.availableApplyPermits == 1)
    }

    /// The race the handler must get right: a permit handed to a waiter at the
    /// very moment it is cancelled. Either the waiter keeps it (and returns it,
    /// as every caller does on every exit) or it never got it — the pool must
    /// end at its capacity either way. Half the rounds cancel before the waiter
    /// has even queued, which drives the "cancelled before it parked" path.
    ///
    /// Mutation: in the handler, resume the waiter without removing it from
    /// the queue → a later release resumes the same continuation again and the
    /// process traps ("tried to resume its continuation more than once").
    @Test func cancelRacingARelease_neverLeaksAPermit() async {
        let permits = InstallPermits(downloads: 2, applies: 1)
        var stuck = 0
        for round in 0..<2000 {
            await permits.waitForDownload()
            await permits.waitForDownload()                   // pool exhausted
            let waiter = Task {
                do {
                    try await permits.waitForDownloadOrCancel()
                    permits.signalDownload()                  // kept it: give it back
                } catch {}
            }
            if round.isMultiple(of: 2) { _ = await Self.parked(permits, downloads: 1) }
            async let cancel: Void = Task.detached { waiter.cancel() }.value
            async let release: Void = Task.detached { permits.signalDownload() }.value
            _ = await (cancel, release)
            if !(await Self.within(seconds: 10) { await waiter.value }) { stuck += 1; break }
            permits.signalDownload()
        }
        #expect(stuck == 0)
        #expect(permits.availableDownloadPermits == 2)
        #expect(permits.parkedDownloadWaiters == 0)
    }

    /// A cancel that lands while the waiter is between "no permit free" and
    /// "queued", with no release coming to rescue it: the handler runs before
    /// there is a queue entry to remove, so the waiter must see the mark it
    /// left and throw instead of queueing — or it waits forever.
    ///
    /// Mutation: drop the `.cancelled` check before queueing → some round's
    /// waiter queues after its handler already ran and the bound fails.
    @Test func cancelRacingTheQueueing_neverStrandsAWaiter() async {
        let permits = InstallPermits(downloads: 1, applies: 1)
        await permits.waitForDownload()                       // pool exhausted for the whole test
        var stuck = 0
        for _ in 0..<5000 {
            let waiter = Task { try? await permits.waitForDownloadOrCancel() }
            await Task.detached { waiter.cancel() }.value
            if !(await Self.within(seconds: 10) { await waiter.value }) { stuck += 1; break }
        }
        #expect(stuck == 0)
        #expect(permits.parkedDownloadWaiters == 0)
        if stuck > 0 { permits.signalDownload() }            // a mutant: free the stranded one
        permits.signalDownload()
    }

    // MARK: - Helpers

    /// Waits (bounded) until `downloads` / `applies` waiters are queued — so
    /// the order the tests enqueue in is the order the pool saw, with no sleep
    /// standing in for "it has probably parked by now".
    private static func parked(
        _ permits: InstallPermits, downloads: Int? = nil, applies: Int? = nil
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if (downloads.map { permits.parkedDownloadWaiters == $0 } ?? true),
               (applies.map { permits.parkedApplyWaiters == $0 } ?? true) {
                return true
            }
            await Task.yield()
        }
        return false
    }

    /// True when `body` finished within `seconds`; abandons it otherwise. (The
    /// same helper `ChildProcessTests` keeps.)
    private static func within(seconds: Double, _ body: @escaping @Sendable () async -> Void) async -> Bool {
        final class Once: @unchecked Sendable {
            let lock = NSLock()
            var continuation: CheckedContinuation<Bool, Never>?
            func resume(_ value: Bool) {
                let c: CheckedContinuation<Bool, Never>? = lock.withLock {
                    defer { continuation = nil }
                    return continuation
                }
                c?.resume(returning: value)
            }
        }
        let once = Once()
        return await withCheckedContinuation { continuation in
            once.lock.withLock { once.continuation = continuation }
            Task { await body(); once.resume(true) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.resume(false) }
        }
    }

    private final class Order: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func append(_ s: String) { lock.withLock { list.append(s) } }
        var values: [String] { lock.withLock { list } }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
}
