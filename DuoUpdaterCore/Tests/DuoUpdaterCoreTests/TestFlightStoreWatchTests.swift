import Foundation
import Testing
@testable import DuoUpdaterCore

/// Each case names the mutation it dies to, and each mutation was run: all four
/// compile (none is caught by the type checker) and each one reddens exactly the case
/// named, not the others.
@Suite struct TestFlightStoreWatchTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// The case the watcher exists for: the user launched TestFlight, the store moved
    /// past what we last read, nothing of ours is running.
    ///
    /// Mutation: `return false` at the end — this fails, and the watcher becomes an
    /// expensive no-op that never re-reads anything.
    @Test func aStoreThatMovedPastOurLastReadIsWorthReading() {
        #expect(TestFlightStoreWatch.reacts(
            stamp: t0.addingTimeInterval(60), lastRead: t0, ourSyncInFlight: false))
    }

    /// Our own hourly sync cold-launches TestFlight and therefore trips this watcher.
    /// It re-checks the rows itself when it finishes, and the store answers nothing
    /// while it runs.
    ///
    /// Mutation: drop the `ourSyncInFlight` guard — this fails. Note the stamp here is
    /// newer than `lastRead`, so nothing else in the function would refuse it.
    @Test func ourOwnSyncIsNotSomethingToReactTo() {
        #expect(!TestFlightStoreWatch.reacts(
            stamp: t0.addingTimeInterval(60), lastRead: t0, ourSyncInFlight: true))
    }

    /// The watcher fires on any change in that directory. A reader touching `-shm`
    /// leaves the log date where it was, and our own snapshot reads do exactly that.
    ///
    /// Mutation: `return stamp >= lastRead` — this fails, and every snapshot read the
    /// app takes feeds itself another re-read.
    @Test func aChangeThatLeftTheStoreWhereWeReadItIsNot() {
        #expect(!TestFlightStoreWatch.reacts(stamp: t0, lastRead: t0, ourSyncInFlight: false))
        #expect(!TestFlightStoreWatch.reacts(
            stamp: t0.addingTimeInterval(-60), lastRead: t0, ourSyncInFlight: false))
    }

    /// Nothing to compare against: an unreadable store cannot say it moved, and a
    /// store we have never read has nothing to be newer than.
    ///
    /// Mutation: make the stamp `guard` return true — **both** nil expectations fail
    /// (verified: 2 issues, this case only). The third pins the opposite direction: a
    /// first read must go ahead, or the watcher never starts working after launch.
    @Test func anUnreadableStoreRefusesAndAFirstReadDoesNot() {
        #expect(!TestFlightStoreWatch.reacts(stamp: nil, lastRead: t0, ourSyncInFlight: false))
        #expect(!TestFlightStoreWatch.reacts(stamp: nil, lastRead: nil, ourSyncInFlight: false))
        #expect(TestFlightStoreWatch.reacts(stamp: t0, lastRead: nil, ourSyncInFlight: false))
    }
}

/// `pollReason` is `reason` with the floor removed. Both mutations were run: each
/// compiles and reddens exactly the case named.
@Suite struct TestFlightPollReasonTests {

    private let now = Date(timeIntervalSince1970: 2_000_000)
    private var ev: [TestFlightSyncPolicy.Evidence] {
        [.init(bundleID: "com.example.beta", installedBuild: "42")]
    }

    /// Evidence is what a poll is for: it names a build to learn about, and the ledger
    /// stops it repeating, so asking often makes the sync earlier rather than extra.
    ///
    /// Mutation: `return nil` — this fails, and the poll becomes a timer that does
    /// nothing.
    @Test func evidenceStillStartsASync() {
        var ledger = TestFlightSyncPolicy.Ledger()
        ledger.begin(at: now.addingTimeInterval(-30))
        #expect(TestFlightSyncPolicy.pollReason(
            evidence: ev, storeStamp: now.addingTimeInterval(-30),
            ledger: ledger, now: now) != nil)
    }

    /// The floor belongs to the round, whose cadence the user chose. A poll that fired
    /// it would re-time that choice — on "Once a day" into roughly hourly.
    ///
    /// Mutation: return `reason(...)` unchanged — this fails. `reason` answers `.floor`
    /// for exactly this input, which is what makes the case load-bearing rather than
    /// decorative.
    @Test func theFloorIsNotAPollsToFire() {
        let ledger = TestFlightSyncPolicy.Ledger()
        let old = now.addingTimeInterval(-TestFlightSyncPolicy.floorInterval - 60)
        #expect(TestFlightSyncPolicy.reason(
            evidence: [], storeStamp: old, ledger: ledger, now: now) != nil)
        #expect(TestFlightSyncPolicy.pollReason(
            evidence: [], storeStamp: old, ledger: ledger, now: now) == nil)
    }
}
