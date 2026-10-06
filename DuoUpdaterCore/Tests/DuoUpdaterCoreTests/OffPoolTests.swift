import Testing
import Foundation
@testable import DuoUpdaterCore

/// `offCooperativePool` exists for when the cooperative pool is blocked, so its
/// hop has to run in exactly that state.
@Suite struct OffPoolTests {

    /// Every other cooperative thread is blocked when the hop is made: the work
    /// still runs.
    ///
    /// The hop used to go to `DispatchQueue.global(qos:)`, which is not an
    /// overcommit queue, and such a queue gets no thread while the cooperative
    /// pool is all blocked. Measured 2026-10-07, release build, 14-core Mac: a
    /// 0.05 s `global().asyncAfter` ran 19.5 s late, and one
    /// `SecStaticCodeCheckValidity` of FileMerge.app took 6.003 s instead of
    /// 0.017 s, both exactly as long as the blocking tasks held the pool.
    ///
    /// The pool is released from a plain `Thread` once the work has run or 30 s
    /// have passed. The 30 s is only how long a broken build takes to fail.
    /// Mutation: hop to `DispatchQueue.global(qos: qos)` again → red at 30 s.
    @Test func theWorkRunsWhileEveryCooperativeThreadIsBlocked() async throws {
        let pool = BlockedCooperativePool(tasks: 2 * ProcessInfo.processInfo.activeProcessorCount)
        // Hold this thread too, so the blocking tasks take every other one first.
        usleep(300_000)
        let ran = Flag()
        let released = pool.release(within: 30) { ran.isSet }
        await offCooperativePool { ran.set() }
        let outcome = await released.value
        #expect(outcome.conditionMet, "the hop had not run after 30 s with the pool blocked")
        // More blocking tasks than threads, so some were still queued: the pool
        // was full when the hop ran, or this test showed nothing.
        #expect(outcome.saturated, "the pool was not full when the hop ran")
    }

    /// Hops still run side by side: each one gets its own serial queue, not one
    /// shared queue that would put every blocking call in the process in a line.
    /// Two hops that each wait for the other can only finish together.
    @Test func hopsRunConcurrently() async throws {
        let a = DispatchSemaphore(value: 0)
        let b = DispatchSemaphore(value: 0)
        async let first: Bool = offCooperativePool { a.signal(); return b.wait(timeout: .now() + 30) == .success }
        async let second: Bool = offCooperativePool { b.signal(); return a.wait(timeout: .now() + 30) == .success }
        let (x, y) = await (first, second)
        #expect(x && y, "one hop waited for the other to start")
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
}
