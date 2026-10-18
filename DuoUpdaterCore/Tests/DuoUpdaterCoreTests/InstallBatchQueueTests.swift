import Foundation
import Testing
@testable import DuoUpdaterCore

/// `InstallBatchQueue`: Update All's Cancel All over a mix of targets.
/// Serialized: the jobs go through the process-wide `InstallJobs` registry.
/// The time limit is a hang guard, not a duration (`InstallJobsRunTests`).
@Suite(.serialized, .timeLimit(.minutes(1))) struct InstallBatchQueueTests {

    typealias Signal = InstallCommitTests.Signal
    typealias Flag = InstallCommitTests.Flag

    /// One preparing, one committing, one queued, one cancelled on its own row
    /// while queued: Cancel All takes the queued one off the queue, cancels the
    /// preparing one, and the committing one finishes — wrap-up included —
    /// with nothing more started afterwards.
    /// Mutations: `cancelAll` cancels nothing it started → the preparing job
    /// never stops, its wait gives up, red; `remove` takes a started target too →
    /// red; `cancelAll` leaves `unstarted` → the queued one starts after
    /// Cancel All, red.
    @Test func cancelAllOverAMix() async throws {
        let preparing = InstallJobsTests.id(), committing = InstallJobsTests.id()
        let queued = InstallJobsTests.id(), rowCancelled = InstallJobsTests.id()
        let queue = InstallBatchQueue([preparing, committing, queued, rowCancelled])

        let preparingEntered = Signal()
        let preparingCommitted = Flag()
        #expect(queue.start(preparing))
        let first = Task {
            await InstallJobs.run(preparing) { () async -> Bool in
                preparingEntered.fire()
                await InstallCommitTests.untilCancelled()
                _ = try? await InstallCommit.run("ZZFixture-swap") { preparingCommitted.set() }
                return Task.isCancelled
            }
        }
        let inCommit = Signal(), release = Signal()
        let wrappedUp = Flag()
        #expect(queue.start(committing))
        let second = Task {
            await InstallJobs.run(committing) { () async -> Bool in
                _ = try? await InstallCommit.run("ZZFixture-swap") {
                    inCommit.fire()
                    await release.wait()
                }
                // The wrap-up: settle, journal, re-check.
                guard (try? await Task.sleep(for: .milliseconds(30))) != nil, !Task.isCancelled
                else { return false }
                wrappedUp.set()
                return true
            }
        }
        await preparingEntered.wait()
        await inCommit.wait()

        #expect(queue.remove(rowCancelled))
        #expect(!queue.remove(preparing))
        #expect(queue.cancelledBeforeStart == 1)

        let (removed, answers) = queue.cancelAll()
        #expect(removed == [queued])
        #expect(answers[preparing] == .cancelled)
        #expect(answers[committing] == .tooLate(committing: "ZZFixture-swap"))
        #expect(queue.isCancelled)
        #expect(!queue.start(queued))
        #expect(queue.cancelledBeforeStart == 2)

        #expect(await first.value)
        #expect(!preparingCommitted.value)
        release.fire()
        #expect(await second.value)
        #expect(wrappedUp.value)
    }

    /// The row's own Cancel on a target the batch has not reached: the batch
    /// skips it when its turn comes, and keeps starting the others.
    @Test func aRowCancelledWhileQueuedIsSkipped() {
        let a = InstallJobsTests.id(), b = InstallJobsTests.id()
        let queue = InstallBatchQueue([a, b])
        #expect(queue.remove(b))
        #expect(queue.start(a))
        #expect(!queue.start(b))
        #expect(!queue.isCancelled)
        #expect(queue.cancelledBeforeStart == 1)
    }
}
