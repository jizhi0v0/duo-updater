import Foundation
import Testing

/// `AsyncSemaphore.waitOrCancel()`, the wait the install gates use (the per-host
/// gate and the App Store's single slot): a queued install the user cancels must
/// leave the queue now, not when another install happens to free a slot.
/// `wait()` keeps ignoring cancellation, for the callers that want that.
struct AsyncSemaphoreTests {

    /// Nothing is signalled before the cancelled waiter is expected back, so a wait
    /// that only notices cancellation on wake-up never returns inside the bound.
    /// The others keep their places, and the count is untouched by the one that left.
    ///
    /// Mutation: make `waitOrCancel`'s `onCancel` do nothing → `cancelled` is not
    /// back within the bound and this test fails.
    @Test func cancellingAQueuedWaiterThrowsAndKeepsTheOthersInOrder() async throws {
        let gate = AsyncSemaphore(value: 1)
        let order = Order()
        await gate.wait()                                     // the slot everyone queues behind

        let first = Task { try await gate.waitOrCancel(); order.append("first") }
        #expect(await Self.parked(gate, 1))
        let cancelled = Task { try await gate.waitOrCancel(); order.append("cancelled") }
        #expect(await Self.parked(gate, 2))
        let last = Task { try await gate.waitOrCancel(); order.append("last") }
        #expect(await Self.parked(gate, 3))

        cancelled.cancel()
        let threw = Flag()
        let returned = await Self.within(seconds: 60) {
            do { try await cancelled.value } catch is CancellationError { threw.set() } catch {}
        }
        #expect(returned, "a cancelled waiter must leave the queue without a permit being freed")
        #expect(threw.isSet)
        #expect(await gate.parkedWaiters == 2)
        #expect(await gate.availablePermits == 0)

        // Each task keeps the permit it gets; the next signal hands that slot on.
        await gate.signal()
        try await first.value
        // A mutant still has `cancelled` queued between the two: serve it.
        if !returned { await gate.signal(); _ = try? await cancelled.value }
        await gate.signal()
        try await last.value
        #expect(order.values == ["first", "last"])
        await gate.signal()
        #expect(await gate.availablePermits == 1)
        #expect(await gate.parkedWaiters == 0)
    }

    /// Already cancelled when it asks: throws, and a free permit stays free.
    @Test func anAlreadyCancelledTaskThrowsWithoutTakingAPermit() async {
        let gate = AsyncSemaphore(value: 1)
        let outcome = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await gate.waitOrCancel()
                return "acquired"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "other"
            }
        }.value
        #expect(outcome == "cancelled")
        #expect(await gate.availablePermits == 1)
    }

    /// `wait()` is unchanged: a cancelled waiter stays queued and gets its turn.
    @Test func plainWaitIgnoresCancellation() async {
        let gate = AsyncSemaphore(value: 1)
        await gate.wait()
        let waiter = Task { await gate.wait() }
        #expect(await Self.parked(gate, 1))
        waiter.cancel()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await gate.parkedWaiters == 1)
        await gate.signal()
        await waiter.value
        #expect(await gate.availablePermits == 0)             // the waiter holds it
        await gate.signal()
        #expect(await gate.availablePermits == 1)
    }

    /// A signal racing the cancel of the waiter it would serve: the waiter keeps the
    /// permit (and gives it back, as callers do) or never got it. Either way the
    /// gate ends at its capacity with nobody queued. Half the rounds cancel before
    /// the waiter has queued.
    ///
    /// Mutation: in `leaveQueue`, resume without removing the entry → the next
    /// signal resumes the same continuation twice and the process traps.
    @Test func cancelRacingASignal_neverLeaksAPermit() async {
        let gate = AsyncSemaphore(value: 2)
        var stuck = 0
        for round in 0..<2000 {
            await gate.wait()
            await gate.wait()
            let waiter = Task {
                do {
                    try await gate.waitOrCancel()
                    await gate.signal()                       // kept it: give it back
                } catch {}
            }
            if round.isMultiple(of: 2) { _ = await Self.parked(gate, 1) }
            async let cancel: Void = Task.detached { waiter.cancel() }.value
            async let release: Void = Task.detached { await gate.signal() }.value
            _ = await (cancel, release)
            if !(await Self.within(seconds: 60) { await waiter.value }) { stuck += 1; break }
            await gate.signal()
        }
        #expect(stuck == 0)
        #expect(await gate.availablePermits == 2)
        #expect(await gate.parkedWaiters == 0)
    }

    // MARK: - Helpers

    private static func parked(_ gate: AsyncSemaphore, _ count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            if await gate.parkedWaiters == count { return true }
            // A sleep, not a yield: a spinning poll holds a cooperative
            // thread the waiter under test may need, and a loaded machine
            // running the whole suite has few to spare.
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    /// True when `body` finished within `seconds`; abandons it otherwise.
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
