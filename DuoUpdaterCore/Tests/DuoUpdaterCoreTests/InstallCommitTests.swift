import Foundation
import Testing
@testable import DuoUpdaterCore

/// `InstallCommit.run`: the point of no return. A caller cancelled before it
/// never starts the body; a caller cancelled after it started does not reach
/// the body, which finishes and hands its value back. Task-locals bound outside
/// are still bound inside — a detached task would lose them, and the repo's
/// `@TaskLocal` test overrides (`BackupStore.rootOverride`, …) with them.
///
/// Labels are unique per test (`ZZFixture-…-<uuid>`): the active count is
/// process-wide and other suites run commits in parallel, so a test reads only
/// its own label's count.
@Suite struct InstallCommitTests {

    @TaskLocal static var zzBound: String?

    private struct ZZBodyFailed: Error {}

    /// Mutation: drop the `checkCancellation` → the body runs, red.
    @Test func aCallerCancelledBeforeNeverStartsTheBody() async {
        let ran = Counter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await InstallCommit.run(Self.label()) { ran.bump(); return 1 }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(ran.value == 0)
    }

    /// The caller is cancelled while the body runs. The body does not see it —
    /// a `Task.sleep` inside would throw if it did — and its value comes back.
    /// Mutation: call `body()` directly instead of in an unstructured task → the
    /// sleep throws `CancellationError` and the caller gets that, red.
    @Test func aCallerCancelledDuringTheBodyGetsItsValue() async throws {
        let entered = Signal()
        let release = Signal()
        let sawCancel = Flag()
        let task = Task {
            try await InstallCommit.run(Self.label()) {
                entered.fire()
                await release.wait()
                if Task.isCancelled { sawCancel.set() }
                try await Task.sleep(for: .milliseconds(20))
                return 42
            }
        }
        await entered.wait()
        task.cancel()
        release.fire()
        let value = try await task.value
        #expect(value == 42)
        #expect(!sawCancel.value)
    }

    /// Mutation: `Task.detached` instead of `Task` → nil inside, red.
    @Test func aTaskLocalBoundOutsideIsVisibleInside() async throws {
        let seen = try await Self.$zzBound.withValue("ZZFixture-bound") {
            try await InstallCommit.run(Self.label()) { Self.zzBound }
        }
        #expect(seen == "ZZFixture-bound")
    }

    /// Counted while the body runs, uncounted once it returns or throws.
    /// Mutation: drop the decrement on the throwing path → 1 after the throw, red.
    @Test func theActiveCountFollowsTheBody() async throws {
        let label = Self.label()
        #expect(InstallCommit.activeCount(label: label) == 0)
        let during = try await InstallCommit.run(label) {
            (InstallCommit.activeCount(label: label), InstallCommit.isAnyActive, InstallCommit.activeCount)
        }
        #expect(during.0 == 1)
        #expect(during.1)
        #expect(during.2 >= 1)
        #expect(InstallCommit.activeCount(label: label) == 0)

        await #expect(throws: ZZBodyFailed.self) {
            _ = try await InstallCommit.run(label) { () throws -> Int in throw ZZBodyFailed() }
        }
        #expect(InstallCommit.activeCount(label: label) == 0)
    }

    /// A commit inside a commit is the same commit: not counted again, and its
    /// value passes straight through.
    /// Mutation: drop the pass-through → the inner label is counted, red.
    @Test func aNestedCommitPassesThrough() async throws {
        let outer = Self.label()
        let inner = Self.label()
        let seen = try await InstallCommit.run(outer) {
            try await InstallCommit.run(inner) {
                (InstallCommit.activeCount(label: outer), InstallCommit.activeCount(label: inner))
            }
        }
        #expect(seen.0 == 1)
        #expect(seen.1 == 0)
    }

    // MARK: - Helpers

    static func label() -> String { "ZZFixture-commit-\(UUID().uuidString)" }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var isSet = false
        func set() { lock.withLock { isSet = true } }
        var value: Bool { lock.withLock { isSet } }
    }

    /// A one-shot latch: `wait` returns once `fire` has been called, whether
    /// before or after. Not cancellable on purpose — a waiter that the caller's
    /// cancel reached would say nothing about the body.
    final class Signal: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func fire() {
            let toResume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                fired = true
                defer { waiters = [] }
                return waiters
            }
            toResume.forEach { $0.resume() }
        }

        func wait() async {
            await withCheckedContinuation { cont in
                let now = lock.withLock { () -> Bool in
                    if fired { return true }
                    waiters.append(cont)
                    return false
                }
                if now { cont.resume() }
            }
        }
    }
}

/// `InstallJobs`: which install is where, and a cancel that answers truthfully.
/// Serialized: the registry is process-wide and `anyCommitting` reads all of it.
@Suite(.serialized) struct InstallJobsTests {

    typealias Signal = InstallCommitTests.Signal
    typealias Flag = InstallCommitTests.Flag

    private struct ZZBodyFailed: Error {}

    static func id() -> String { "ZZFixture-job-\(UUID().uuidString)" }

    /// Unknown → nil; registered → preparing; inside a commit → committing; a
    /// commit that returned keeps it committing (past the point of no return);
    /// one that threw puts it back to preparing (nothing changed).
    /// Mutations: never set committing → red; reset to preparing after a
    /// returning commit → red.
    @Test func phasesFollowTheCommits() async throws {
        let failing = Self.id()
        #expect(InstallJobs.phase(of: failing) == nil)
        InstallJobs.register(failing, cancel: {})
        defer { InstallJobs.unregister(failing) }
        #expect(InstallJobs.phase(of: failing) == .preparing)
        await #expect(throws: ZZBodyFailed.self) {
            try await InstallJobs.$currentID.withValue(failing) {
                _ = try await InstallCommit.run("ZZFixture-swap") { () throws -> Int in
                    #expect(InstallJobs.phase(of: failing) == .committing)
                    throw ZZBodyFailed()
                }
            }
        }
        #expect(InstallJobs.phase(of: failing) == .preparing)

        let landing = Self.id()
        InstallJobs.register(landing, cancel: {})
        defer { InstallJobs.unregister(landing) }
        try await InstallJobs.$currentID.withValue(landing) {
            try await InstallCommit.run("ZZFixture-swap") {
                #expect(InstallJobs.phase(of: landing) == .committing)
                #expect(InstallJobs.anyCommitting)
            }
        }
        #expect(InstallJobs.phase(of: landing) == .committing)
        InstallJobs.unregister(landing)
        #expect(InstallJobs.phase(of: landing) == nil)
    }

    /// Cancelled while preparing: the job's own cancel runs, and no commit of
    /// that job starts afterwards — even one whose task the cancel has not
    /// reached (the registry's answer must stay true).
    /// Mutation: drop the registry's `cancelRequested` check in the commit →
    /// the body runs, red.
    @Test func aCancelWhilePreparingCancelsAndNoCommitStarts() async throws {
        let id = Self.id()
        let cancelled = Flag()
        InstallJobs.register(id, cancel: { cancelled.set() })
        defer { InstallJobs.unregister(id) }
        #expect(InstallJobs.cancel(id) == .cancelled)
        #expect(cancelled.value)
        let ran = Flag()
        await #expect(throws: CancellationError.self) {
            try await InstallJobs.$currentID.withValue(id) {
                try await InstallCommit.run("ZZFixture-swap") { ran.set() }
            }
        }
        #expect(!ran.value)
    }

    /// Cancelled while committing: too late, the job's cancel is not called and
    /// the commit finishes.
    /// Mutation: ignore the phase in `cancel` → the job's cancel runs, red.
    @Test func aCancelWhileCommittingIsTooLateAndDoesNotInterrupt() async throws {
        let id = Self.id()
        let cancelled = Flag()
        InstallJobs.register(id, cancel: { cancelled.set() })
        defer { InstallJobs.unregister(id) }
        let entered = Signal()
        let release = Signal()
        let task = Task {
            try await InstallJobs.$currentID.withValue(id) {
                try await InstallCommit.run("ZZFixture-swap") {
                    entered.fire()
                    await release.wait()
                    try await Task.sleep(for: .milliseconds(20))
                    return "landed"
                }
            }
        }
        await entered.wait()
        #expect(InstallJobs.cancel(id) == .tooLate(committing: "ZZFixture-swap"))
        #expect(InstallJobs.cancelAll()[id] == .tooLate(committing: "ZZFixture-swap"))
        release.fire()
        #expect(try await task.value == "landed")
        #expect(!cancelled.value)
    }

    @Test func anUnknownJobIsNotFound() {
        #expect(InstallJobs.cancel(Self.id()) == .notFound)
    }

    /// `cancelAll` cancels every job still preparing and reports the rest.
    @Test func cancelAllCancelsEveryPreparingJob() {
        let a = Self.id(), b = Self.id()
        let cancelledA = Flag(), cancelledB = Flag()
        InstallJobs.register(a, cancel: { cancelledA.set() })
        InstallJobs.register(b, cancel: { cancelledB.set() })
        defer { InstallJobs.unregister(a); InstallJobs.unregister(b) }
        let answers = InstallJobs.cancelAll()
        #expect(answers[a] == .cancelled)
        #expect(answers[b] == .cancelled)
        #expect(cancelledA.value && cancelledB.value)
    }
}
