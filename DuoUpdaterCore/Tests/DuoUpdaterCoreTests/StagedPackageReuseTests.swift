import Foundation
import Testing
@testable import DuoUpdaterCore

/// When a downloaded package may still be offered for re-opening.
///
/// The case that motivated it: a pkg-route app whose package installed during an
/// Update All batch. The row read up to date, yet its note still said the package
/// "is downloaded — Install re-opens it", because the staged entry outlives the
/// install until the reconciler settles it and the old check only asked whether
/// the package matched the offer.
struct StagedPackageReuseTests {

    private func side(_ marketing: String?, _ build: String? = nil) -> VersionSide {
        VersionSide(marketing: marketing, build: build)
    }

    /// Replays the reported row: the source offers a marketing version with no
    /// build, the package was staged from that offer, and the install then landed
    /// (the bundle now carries the same marketing version plus its own build).
    ///
    /// Mutation: drop the `hasLanded` guard (return `true` after the offer check).
    @Test func aPackageThatHasAlreadyInstalledIsNotReusable() {
        #expect(!StagedPackageReuse.isReusable(
            staged: side("4.40.0"), offered: side("4.40.0"),
            onDisk: side("4.40.0", "621"), buildIsDerived: false))
    }

    /// Before the installer has run, the same package is exactly what Install
    /// should re-open. Pins that the new guard did not switch reuse off.
    ///
    /// Mutation: return `false` unconditionally, or negate the `hasLanded` guard.
    @Test func aPackageWaitingToBeInstalledIsReusable() {
        #expect(StagedPackageReuse.isReusable(
            staged: side("4.40.0"), offered: side("4.40.0"),
            onDisk: side("4.39.1", "618"), buildIsDerived: false))
    }

    /// A newer release on offer makes the downloaded package the wrong one.
    ///
    /// Mutation: drop the `isSame(staged, as: offered)` check.
    @Test func aPackageForAVersionNoLongerOfferedIsNotReusable() {
        #expect(!StagedPackageReuse.isReusable(
            staged: side("4.40.0"), offered: side("4.41.0"),
            onDisk: side("4.39.1", "618"), buildIsDerived: false))
        #expect(!StagedPackageReuse.isReusable(
            staged: side("4.40.0"), offered: nil,
            onDisk: side("4.39.1", "618"), buildIsDerived: false))
    }

    /// A frozen-marketing app: same marketing version, builds differ. The staged
    /// build has not landed while the disk still carries the old build.
    ///
    /// Mutation: compare marketing only in the landed check (pass
    /// `buildIsDerived: true` through), which reads the old build as landed.
    @Test func sameMarketingOlderBuildOnDiskIsStillReusable() {
        #expect(StagedPackageReuse.isReusable(
            staged: side("1.0", "120"), offered: side("1.0", "120"),
            onDisk: side("1.0", "119"), buildIsDerived: false))
        #expect(!StagedPackageReuse.isReusable(
            staged: side("1.0", "120"), offered: side("1.0", "120"),
            onDisk: side("1.0", "120"), buildIsDerived: false))
    }

    /// A scanner-derived build is a different namespace from the package's, so
    /// landing falls back to marketing — the same rule the reconciler uses.
    ///
    /// Mutation: pass `buildIsDerived: false` to `hasLanded` regardless.
    @Test func aDerivedBuildDoesNotKeepALandedPackageReusable() {
        #expect(!StagedPackageReuse.isReusable(
            staged: side("0.9.7", "20260910"), offered: side("0.9.7", "20260910"),
            onDisk: side("0.9.7", "88"), buildIsDerived: true))
    }
}
