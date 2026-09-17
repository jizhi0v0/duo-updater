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
}
