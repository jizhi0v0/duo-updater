import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite("PackageRestartState")
struct PackageRestartStateTests {
    private let handOff = Date(timeIntervalSince1970: 1_000_000)

    /// These cases all predate the pair comparison and describe apps whose
    /// marketing version moves, so a marketing-only side is the faithful fixture.
    private func v(_ marketing: String) -> VersionSide { VersionSide(marketing: marketing) }

    /// The install hasn't landed: the on-disk version is still not the one the
    /// package installs (user hasn't clicked through the Installer, or cancelled).
    @Test func notLandedIsPending() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: v("2.02.2608040"),   // still the old build on disk
            stagedVersion: v("2.02.2608182"),
            stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-60)]) == .pending)
    }

    /// Landed, and a copy that started BEFORE the hand-off is still running the old
    /// code — the case the whole feature exists for. Crucially decided WITHOUT
    /// comparing versions, so it works for WeChat DevTools, whose reported version is
    /// frozen at Electron's across every build.
    @Test func landedWithAnOlderRunningCopyAsksForRestart() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: v("2.02.2608182"),
            stagedVersion: v("2.02.2608182"),
            stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-3600)]) == .readyToRestart)
    }

    /// The vendor's own pkg relaunched the app: the running copy started AFTER the
    /// hand-off, so nothing stale remains — no prompt. This is the "厂商自己重启了 →
    /// 正好看不见" case, free from the launch-time signal.
    @Test func landedButVendorAlreadyRelaunchedIsSettled() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: v("2.02.2608182"),
            stagedVersion: v("2.02.2608182"),
            stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(120)]) == .settled)
    }

    /// Landed and the app isn't running at all — nothing to restart.
    @Test func landedWithNothingRunningIsSettled() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: v("2.02.2608182"),
            stagedVersion: v("2.02.2608182"),
            stagedAt: handOff,
            runningLaunchDates: []) == .settled)
    }

    /// Mixed instances (one predates the hand-off, one doesn't) still count as stale
    /// — the old process is running old code no matter how many fresh ones joined it.
    @Test func anyOlderInstanceAmongNewerOnesStillCountsStale() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: v("2.02.2608182"),
            stagedVersion: v("2.02.2608182"),
            stagedAt: handOff,
            runningLaunchDates: [
                handOff.addingTimeInterval(300),
                handOff.addingTimeInterval(-5),
            ]) == .readyToRestart)
    }

    /// A running copy whose launch date is UNKNOWN is fed in as `.distantPast` (see
    /// `runningLaunchDatesByPath`), which predates any real hand-off — so we err
    /// toward offering a restart rather than silently deciding it's fresh.
    @Test func anUnknownLaunchDateCountsAsStale() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: v("2.02.2608182"),
            stagedVersion: v("2.02.2608182"),
            stagedAt: handOff,
            runningLaunchDates: [.distantPast]) == .readyToRestart)
    }

    /// A newer version than the staged one is on disk: the package was superseded,
    /// not applied, so it's not "landed" — no restart is owed to THIS package.
    @Test func aNewerOnDiskVersionIsNotThisPackageLanding() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: v("2.02.2608190"),
            stagedVersion: v("2.02.2608182"),
            stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-60)]) == .pending)
    }

    /// The frozen-marketing case, which the marketing-only signature could not
    /// even express. On disk build 128, the package installs 130, both called
    /// "1.0": `onDiskVersion == stagedVersion` was true, so a package that had not
    /// run yet was classified as landed and the row stopped asking for the install.
    @Test func aFrozenMarketingVersionIsNotLandedUntilTheBuildMoves() {
        let staged = VersionSide(marketing: "1.0", build: "130")
        #expect(PackageRestartState.resolve(
            onDiskVersion: VersionSide(marketing: "1.0", build: "128"),
            stagedVersion: staged, stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-60)]) == .pending,
            "build 128 is not build 130 — the installer has not run")

        #expect(PackageRestartState.resolve(
            onDiskVersion: VersionSide(marketing: "1.0", build: "130"),
            stagedVersion: staged, stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-3600)]) == .readyToRestart,
            "the build arrived, and a copy from before the hand-off is still up")
    }

    /// `AppScanner` substitutes a vendor-facing build for a small set of apps.
    /// A package feed's build is not thereby in that namespace, so disagreement
    /// between those strings cannot veto marketing evidence that the target landed.
    @Test func aDerivedOnDiskBuildFallsBackToMarketing() {
        let staged = VersionSide(marketing: "1.1", build: "bundle-build-11")

        #expect(PackageRestartState.resolve(
            onDiskVersion: VersionSide(marketing: "1.1", build: "vendor-code-1100"),
            stagedVersion: staged, stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-60)],
            buildIsDerived: true) == .readyToRestart,
            "matching marketing is the only shared namespace")

        #expect(PackageRestartState.resolve(
            onDiskVersion: VersionSide(marketing: "1.0", build: "vendor-code-1000"),
            stagedVersion: staged, stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-60)],
            buildIsDerived: true) == .pending,
            "dropping an incomparable build must not make every package landed")
    }
}
