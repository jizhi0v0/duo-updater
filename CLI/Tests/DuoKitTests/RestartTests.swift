import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `Restart.run` drives `AppRestarter`, which quits real processes, so these
/// cover the parts that don't touch one: the usage-error path, and the mapping
/// from an `AppRestarter.Outcome` to what gets printed and to the exit code.
@Suite struct RestartTests {

    @Test func namingNoAppIsAUsageError() async {
        let code = await Restart.run(Restart.Options())
        #expect(code == 2)
    }

    @Test func aSuccessfulRestartIsNotAFailure() {
        #expect(!Restart.isFailure(.relaunched(true)))
        #expect(Restart.describe(.relaunched(true)) == "restarted")
    }

    /// A quit that never came back is worse than doing nothing — the app is now
    /// down when it was up — so it must push the exit code to 1.
    @Test func aQuitThatNeverRelaunchesIsAFailure() {
        #expect(Restart.isFailure(.relaunched(false)))
    }

    /// An app that wouldn't quit (a save prompt) is left exactly as it was, but
    /// still counts as "didn't do what was asked" for the exit code.
    @Test func stillRunningIsAFailure() {
        #expect(Restart.isFailure(.stillRunning))
    }

    /// Held at macOS's first-open prompt: not "likely a save prompt", and the
    /// restart that was asked for did not happen, so it fails the run.
    @Test func anAppHeldAtTheOpenPromptSaysSoAndFails() {
        #expect(Restart.isFailure(.awaitingOpenConfirmation))
        #expect(Restart.describe(.awaitingOpenConfirmation)
            == "hasn't finished opening — if macOS is asking whether to open it, click Open, then run duo restart again")
    }

    /// The printed line, in the `name  text` columns every outcome uses.
    @Test func aHeldAppsLineKeepsTheColumns() async {
        let app = InstalledApp(
            name: "Hoppscotch", bundleID: "io.hoppscotch.desktop", shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/ZZFixture-held/Hoppscotch.app"), isMASApp: false, sparkleFeedURL: nil)
        let lines = SignalGateTests.Lines()
        let anyFailed = await Restart.restartEach(
            [app], staged: [:], keepBackups: false, waitsForAnswer: false, print: { lines.add($0) },
            restart: { _ in .awaitingOpenConfirmation })
        #expect(lines.all == ["Hoppscotch  hasn't finished opening — if macOS is asking whether to open it, click Open, then run duo restart again"])
        #expect(anyFailed)
    }

    /// Nothing to do is success, not failure — asking to restart an app that
    /// isn't running (or has no bundle id to match) didn't fail at anything.
    @Test func notRunningAndNoBundleIDAreNotFailures() {
        #expect(!Restart.isFailure(.notRunning))
        #expect(!Restart.isFailure(.noBundleID))
    }

    /// `.nestedOnly` covers the app-wasn't-running-itself case (see #72): the
    /// nested app(s) it needed cleared came back, so nothing is left worse off
    /// than before the restart was asked for.
    @Test func nestedOnlyThatCameBackIsNotAFailure() {
        #expect(!Restart.isFailure(.nestedOnly(relaunched: true)))
        #expect(Restart.describe(.nestedOnly(relaunched: true))
            == "wasn't running itself — its nested app(s) were cleared and came back")
    }

    /// The nested app was quit for the swap and never came back — that is worse
    /// off than doing nothing, the same reasoning as `.relaunched(false)`, so it
    /// must also push the exit code to 1.
    @Test func nestedOnlyThatDidNotComeBackIsAFailure() {
        #expect(Restart.isFailure(.nestedOnly(relaunched: false)))
        #expect(Restart.describe(.nestedOnly(relaunched: false))
            == "wasn't running itself — its nested app(s) were cleared, but didn't come back")
    }

    // MARK: - Staged self-update

    private static let gitKraken = InstalledApp(
        name: "GitKraken", bundleID: "com.axosoft.gitkraken",
        shortVersion: "12.5.0", buildVersion: "12.5.0",
        path: URL(fileURLWithPath: "/ZZFixture/GitKraken.app"),
        isMASApp: false, sparkleFeedURL: nil)

    private static func staged(_ version: String, _ updater: StagedUpdater = .shipIt) -> StagedSelfUpdate {
        StagedSelfUpdate(version: version, buildVersion: version,
                         stagedBundlePath: URL(fileURLWithPath: "/ZZFixture/update.x/GitKraken.app"),
                         updater: updater)
    }

    /// The 2026-10-16 bug: GitKraken had 12.6.0 staged and `duo restart` took the
    /// plain quit-and-reopen, which ShipIt aborted on. A staged build newer than
    /// the installed one takes the Relaunch path. Mutation: `path` always
    /// `.plain` → red.
    @Test func aStagedNewerBuildTakesTheStagedPath() {
        let build = Self.staged("12.6.0")
        #expect(Restart.path(for: Self.gitKraken, staged: build) == .staged(build))
    }

    /// No staging, or a staging at or below what is installed (relaunching would
    /// not move it forward): today's `AppRestarter.restart`, unchanged.
    @Test func noUsefulStagingKeepsThePlainRestart() {
        #expect(Restart.path(for: Self.gitKraken, staged: nil) == .plain)
        #expect(Restart.path(for: Self.gitKraken, staged: Self.staged("12.5.0")) == .plain)
        #expect(Restart.path(for: Self.gitKraken, staged: Self.staged("12.4.0")) == .plain)
    }

    /// Mozilla's actionable test needs the remote, which `duo restart` does not
    /// fetch — so it stays on the plain restart, whose reopen is the launch that
    /// applies its staging.
    @Test func aMozillaStagingStaysOnThePlainRestart() {
        #expect(Restart.path(for: Self.gitKraken, staged: Self.staged("12.6.0", .mozilla)) == .plain)
    }

    /// What gets printed, and which endings fail the run.
    @Test func stagedEndingsDescribeWhatHappened() {
        func line(_ o: StagedRelaunchOutcome, reopenFailed: Bool = false) -> (text: String, failed: Bool) {
            Restart.describe(
                StagedRelaunch.Ending(outcome: o, everQuit: o != .wontQuit, reopenFailed: reopenFailed),
                staged: "12.6.0", disk: VersionSide(marketing: "12.6.0", build: "12.6.0"))
        }
        #expect(line(.applied).text == "quit — its own updater applied 12.6.0")
        #expect(!line(.applied).failed)
        #expect(line(.applied, reopenFailed: true).failed)
        #expect(line(.wontQuit).text == "still running — likely a save prompt, left 12.6.0 staged")
        #expect(line(.wontQuit).failed)
        #expect(line(.swapDidNotLand).text == "quit, but its own updater didn't apply 12.6.0 in time")
        #expect(line(.swapDidNotLand).failed)
        #expect(line(.restartedWithoutUpdate).text == "restarted without applying 12.6.0")
        #expect(line(.restartedWithoutUpdate).failed)
        #expect(line(.awaitingOpenConfirmation).text
            == "hasn't finished opening, left 12.6.0 staged — if macOS is asking whether to open it, click Open, then run duo restart again")
        #expect(line(.awaitingOpenConfirmation).failed)
    }

    /// The rollback-point line, worded as `duo install` words its own. Nothing
    /// for a skip (backups off, or disk already past).
    @Test func backupStepsDescribeWhatHappened() {
        #expect(Restart.describe(.attempted(.saved), version: "12.5.0") == "backed up 12.5.0")
        #expect(Restart.describe(.attempted(.failed), version: "12.5.0")
            == "could not back up — restarting without a restore point")
        #expect(Restart.describe(.lockRefused, version: "12.5.0")?.hasPrefix("no restore point") == true)
        #expect(Restart.describe(.skipped, version: "12.5.0") == nil)
    }
}
