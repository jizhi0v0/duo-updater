import Foundation
import Testing
@testable import DuoUpdaterCore

/// The workbench hides a rollback that would change nothing. That filter used to
/// compare the backup's marketing LABEL against the installed marketing string,
/// so for an app that keeps one marketing version across builds every rollback
/// looked like a no-op — the row vanished after a real update, with a complete
/// backup sitting on disk and no way to reach it.
@Suite struct BackupRollbackDistinctTests {

    private func s(_ m: String?, _ b: String?) -> VersionSide {
        VersionSide(marketing: m, build: b)
    }

    /// The bug: installed 129, backup 128, both "1.0".
    @Test func aBuildOnlyDifferenceIsStillWorthRollingBackTo() {
        #expect(BackupStore.rollbackIsDistinct(
            installed: s("1.0", "129"), backup: s("1.0", "128")))
    }

    /// A genuine no-op stays hidden — the filter still does its job.
    @Test func anIdenticalBuildIsANoOp() {
        #expect(!BackupStore.rollbackIsDistinct(
            installed: s("1.0", "129"), backup: s("1.0", "129")))
    }

    /// An old sidecar carries no build, and some carry no version at all. Offering
    /// a rollback that turns out to be a no-op is a far smaller failure than
    /// hiding one the user needs, so an uncomparable backup is treated as distinct.
    @Test func anUncomparableBackupIsOffered() {
        #expect(BackupStore.rollbackIsDistinct(
            installed: s("1.0", "129"), backup: VersionSide()))
        #expect(BackupStore.rollbackIsDistinct(
            installed: VersionSide(), backup: s("1.0", "128")))
    }

    /// A legacy sidecar with only a marketing version still compares on what it
    /// has: same marketing, nothing else known, so it reads as a no-op exactly as
    /// it did before the build was recorded.
    @Test func aLegacySidecarComparesOnWhatItHas() {
        #expect(!BackupStore.rollbackIsDistinct(
            installed: s("1.0", "129"), backup: s("1.0", nil)))
        #expect(BackupStore.rollbackIsDistinct(
            installed: s("1.8.0", "20"), backup: s("1.7.3", nil)))
    }
}
