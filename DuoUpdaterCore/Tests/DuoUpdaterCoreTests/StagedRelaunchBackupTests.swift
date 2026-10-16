import Foundation
import Testing
@testable import DuoUpdaterCore

/// The two decisions around the rollback point a Relaunch takes before quitting
/// an app for its own updater. The copy and the quit are wiring in
/// `AppListModel.relaunchStagedUpdate`, which no test target compiles; what is
/// decided about them lives here.
///
/// Fixtures use the Amp shape (marketing frozen at "1.0", build climbing), so a
/// comparison that reads marketing alone answers wrong in every case below.
@Suite struct StagedRelaunchBackupTests {

    private func amp(_ build: String?) -> VersionSide {
        VersionSide(marketing: "1.0", build: build)
    }

    // MARK: - shouldTake

    /// The ordinary case: backups on, disk still the build the row was built
    /// from. Mutation: `shouldTake` returning false turns this red.
    @Test func backsUpWhileTheOldBuildIsStillOnDisk() {
        #expect(StagedRelaunchBackup.shouldTake(
            keepBackups: true, old: amp("128"), disk: amp("128"), buildIsDerived: false))
    }

    /// The user's setting wins. Mutation: dropping the `keepBackups` guard.
    @Test func respectsTheBackupsSetting() {
        #expect(!StagedRelaunchBackup.shouldTake(
            keepBackups: false, old: amp("128"), disk: amp("128"), buildIsDerived: false))
    }

    /// The row is a stale snapshot and the app already replaced itself: a copy
    /// now would be the new build under the old label. Build-only move, so a
    /// marketing-only comparison would miss it. Mutation: dropping the
    /// `hasLanded` check.
    @Test func skipsWhenDiskAlreadyMovedPastTheRow() {
        #expect(!StagedRelaunchBackup.shouldTake(
            keepBackups: true, old: amp("128"), disk: amp("129"), buildIsDerived: false))
    }

    /// Unreadable is not a landing: attempt it, and let `backUp` say it could
    /// not read the bundle instead of skipping in silence.
    @Test func anUnreadableBundleStillGetsAnAttempt() {
        #expect(StagedRelaunchBackup.shouldTake(
            keepBackups: true, old: amp("128"), disk: VersionSide(), buildIsDerived: false))
    }

    // MARK: - isIntact

    /// Nothing quit, nothing moved: keep the copy and go on to quit the app.
    /// Mutation: `isIntact` returning false turns this red.
    @Test func aCopyWithEveryInstanceStillUpIsIntact() {
        #expect(StagedRelaunchBackup.isIntact(
            runningBefore: [501], runningAfter: [501],
            old: amp("128"), diskAfter: amp("128"), buildIsDerived: false))
        // An unrelated extra instance appearing does not tear anything.
        #expect(StagedRelaunchBackup.isIntact(
            runningBefore: [501], runningAfter: [501, 777],
            old: amp("128"), diskAfter: amp("128"), buildIsDerived: false))
    }

    /// The user quit the app during the copy, so a swap-on-quit updater may have
    /// been rewriting the bundle under `ditto`. Mutation: dropping the subset
    /// check.
    @Test func quittingDuringTheCopyIsNotIntact() {
        #expect(!StagedRelaunchBackup.isIntact(
            runningBefore: [501], runningAfter: [],
            old: amp("128"), diskAfter: amp("128"), buildIsDerived: false))
    }

    /// Quit and reopened (by the user or by the updater's own relaunch): the
    /// process ids are new, even though something is running again. A check on
    /// "is anything running" instead of "are the same instances running" passes
    /// this. Disk is deliberately unchanged here so only the pid rule can fail it.
    @Test func quitAndReopenDuringTheCopyIsNotIntact() {
        #expect(!StagedRelaunchBackup.isIntact(
            runningBefore: [501], runningAfter: [902],
            old: amp("128"), diskAfter: amp("128"), buildIsDerived: false))
    }

    /// Same instances, but the bundle moved underneath anyway (an updater that
    /// swaps without waiting for a quit). Build-only move. Mutation: dropping the
    /// `hasLanded` check in `isIntact`.
    @Test func aBundleThatMovedDuringTheCopyIsNotIntact() {
        #expect(!StagedRelaunchBackup.isIntact(
            runningBefore: [501], runningAfter: [501],
            old: amp("128"), diskAfter: amp("129"), buildIsDerived: false))
    }

    /// No instances going in proves nothing about the copy. Mutation: dropping
    /// the `isEmpty` guard (an empty set is a subset of everything).
    @Test func noInstancesGoingInIsNotIntact() {
        #expect(!StagedRelaunchBackup.isIntact(
            runningBefore: [], runningAfter: [],
            old: amp("128"), diskAfter: amp("128"), buildIsDerived: false))
    }

    // MARK: - take

    private let app = InstalledApp(
        name: "Amp", bundleID: "com.example.zz-fixture-amp",
        shortVersion: "1.0", buildVersion: "128",
        path: URL(fileURLWithPath: "/ZZFixture/Amp.app"),
        isMASApp: false, sparkleFeedURL: nil)

    /// The fake machine `take` runs against, recording what it was asked to do.
    private final class Machine: @unchecked Sendable {
        var disk: VersionSide
        var running: Set<pid_t> = [501]
        var lockHeldElsewhere = false
        var outcome: InstallCoordinator.BackupOutcome = .saved
        /// What happens to the app while the copy runs.
        var duringCopy: (Machine) -> Void = { _ in }
        var claims = 0, releases = 0, copies = 0, removals = 0

        init(disk: VersionSide) { self.disk = disk }

        var system: StagedRelaunchBackup.System {
            StagedRelaunchBackup.System(
                diskVersion: { self.disk },
                runningPIDs: { self.running },
                claimLock: {
                    if self.lockHeldElsewhere { throw CocoaError(.fileLocking) }
                    self.claims += 1
                },
                releaseLock: { self.releases += 1 },
                backUp: { self.copies += 1; self.duringCopy(self); return self.outcome },
                remove: { self.removals += 1 })
        }
    }

    private func take(_ m: Machine, keepBackups: Bool = true) async -> StagedRelaunchBackup.Taken {
        await StagedRelaunchBackup.take(
            app, keepBackups: keepBackups, old: amp("128"), runningBefore: [501], system: m.system)
    }

    /// The ordinary case: copied under the lock, kept, lock released. Mutation:
    /// dropping `releaseLock` leaves the machine-wide lock held, red.
    @Test func takeCopiesUnderTheLockAndKeepsIt() async {
        let m = Machine(disk: amp("128"))
        #expect(await take(m) == .attempted(.saved))
        #expect(m.copies == 1)
        #expect((m.claims, m.releases, m.removals) == (1, 1, 0))
    }

    /// Backups off: no lock, no copy.
    @Test func takeHonoursTheBackupsSetting() async {
        let m = Machine(disk: amp("128"))
        #expect(await take(m, keepBackups: false) == .skipped)
        #expect((m.claims, m.copies) == (0, 0))
    }

    /// The bundle is already the new build: a copy would be mislabelled.
    @Test func takeSkipsABundleAlreadyPastTheOldBuild() async {
        let m = Machine(disk: amp("129"))
        #expect(await take(m) == .skipped)
        #expect(m.copies == 0)
    }

    /// The other host holds the lock: no copy, and nothing to release.
    @Test func takeWithTheLockHeldElsewhereCopiesNothing() async {
        let m = Machine(disk: amp("128"))
        m.lockHeldElsewhere = true
        #expect(await take(m) == .lockRefused)
        #expect((m.copies, m.releases) == (0, 0))
    }

    /// The user quit the app mid-copy: the stored copy may be torn, so it is
    /// removed and the caller stands down. Mutation: skipping `remove` → a torn
    /// backup survives, red.
    @Test func aQuitDuringTheCopyDiscardsItAndStandsDown() async {
        let m = Machine(disk: amp("128"))
        m.duringCopy = { $0.running = [] }
        #expect(await take(m) == .standDown(discarded: true))
        #expect(m.removals == 1)
        #expect(m.releases == 1, "the lock is released on this path too")
    }

    /// The bundle moved under the copy while the app stayed up.
    @Test func aSwapDuringTheCopyDiscardsIt() async {
        let m = Machine(disk: amp("128"))
        m.duringCopy = { $0.disk = VersionSide(marketing: "1.0", build: "129") }
        #expect(await take(m) == .standDown(discarded: true))
        #expect(m.removals == 1)
    }

    /// A copy that failed never replaced the previous backup, which must
    /// survive. Mutation: removing regardless of the outcome, red.
    @Test func aFailedCopyLeavesThePreviousBackupAlone() async {
        let m = Machine(disk: amp("128"))
        m.outcome = .failed
        m.duringCopy = { $0.running = [] }
        #expect(await take(m) == .standDown(discarded: false))
        #expect(m.removals == 0)
    }
}
