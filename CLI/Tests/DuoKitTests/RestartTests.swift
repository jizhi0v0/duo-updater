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

    /// Nothing to do is success, not failure — asking to restart an app that
    /// isn't running (or has no bundle id to match) didn't fail at anything.
    @Test func notRunningAndNoBundleIDAreNotFailures() {
        #expect(!Restart.isFailure(.notRunning))
        #expect(!Restart.isFailure(.noBundleID))
    }
}
