import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite("PackageRestartState")
struct PackageRestartStateTests {
    private let handOff = Date(timeIntervalSince1970: 1_000_000)

    /// The install hasn't landed: the on-disk version is still not the one the
    /// package installs (user hasn't clicked through the Installer, or cancelled).
    @Test func notLandedIsPending() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: "2.02.2608040",   // still the old build on disk
            stagedVersion: "2.02.2608182",
            stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-60)]) == .pending)
    }

    /// Landed, and a copy that started BEFORE the hand-off is still running the old
    /// code — the case the whole feature exists for. Crucially decided WITHOUT
    /// comparing versions, so it works for WeChat DevTools, whose reported version is
    /// frozen at Electron's across every build.
    @Test func landedWithAnOlderRunningCopyAsksForRestart() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: "2.02.2608182",
            stagedVersion: "2.02.2608182",
            stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-3600)]) == .readyToRestart)
    }

    /// The vendor's own pkg relaunched the app: the running copy started AFTER the
    /// hand-off, so nothing stale remains — no prompt. This is the "厂商自己重启了 →
    /// 正好看不见" case, free from the launch-time signal.
    @Test func landedButVendorAlreadyRelaunchedIsSettled() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: "2.02.2608182",
            stagedVersion: "2.02.2608182",
            stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(120)]) == .settled)
    }

    /// Landed and the app isn't running at all — nothing to restart.
    @Test func landedWithNothingRunningIsSettled() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: "2.02.2608182",
            stagedVersion: "2.02.2608182",
            stagedAt: handOff,
            runningLaunchDates: []) == .settled)
    }

    /// Mixed instances (one predates the hand-off, one doesn't) still count as stale
    /// — the old process is running old code no matter how many fresh ones joined it.
    @Test func anyOlderInstanceAmongNewerOnesStillCountsStale() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: "2.02.2608182",
            stagedVersion: "2.02.2608182",
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
            onDiskVersion: "2.02.2608182",
            stagedVersion: "2.02.2608182",
            stagedAt: handOff,
            runningLaunchDates: [.distantPast]) == .readyToRestart)
    }

    /// A newer version than the staged one is on disk: the package was superseded,
    /// not applied, so it's not "landed" — no restart is owed to THIS package.
    @Test func aNewerOnDiskVersionIsNotThisPackageLanding() {
        #expect(PackageRestartState.resolve(
            onDiskVersion: "2.02.2608190",
            stagedVersion: "2.02.2608182",
            stagedAt: handOff,
            runningLaunchDates: [handOff.addingTimeInterval(-60)]) == .pending)
    }
}
