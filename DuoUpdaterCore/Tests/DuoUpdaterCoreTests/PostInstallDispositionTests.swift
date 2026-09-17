import Foundation
import Testing
@testable import DuoUpdaterCore

struct PostInstallDispositionTests {

    /// Regression: during Update All the expensive running-version rescan is
    /// deliberately deferred. A running app whose bundle has already been
    /// replaced must stay visible as awaiting the batch restart; treating the
    /// temporarily-empty `needsRestart` value as completion makes the row flash
    /// "Updated ✓" and disappear while its old process is still running.
    @Test func runningBatchInstallWaitsForDeferredRestartBookkeeping() {
        let disposition = PostInstallDisposition.resolve(
            defersBookkeeping: true,
            preInstallProcessStillRunning: true,
            needsRestartAfterRescan: false
        )

        #expect(disposition == .awaitingBatchRestart)
    }

    @Test func stoppedBatchInstallIsCompleteImmediately() {
        let disposition = PostInstallDisposition.resolve(
            defersBookkeeping: true,
            preInstallProcessStillRunning: false,
            needsRestartAfterRescan: false
        )

        #expect(disposition == .complete)
    }

    @Test func singleInstallUsesFreshRestartProbe() {
        #expect(PostInstallDisposition.resolve(
            defersBookkeeping: false,
            preInstallProcessStillRunning: true,
            needsRestartAfterRescan: true
        ) == .awaitingRestart)

        #expect(PostInstallDisposition.resolve(
            defersBookkeeping: false,
            preInstallProcessStillRunning: true,
            needsRestartAfterRescan: false
        ) == .complete)
    }

    // MARK: - preInstallProcessStillRunning

    /// An in-place swap (vendor, Sparkle, Homebrew) leaves the old process up, so
    /// the row still owes a restart.
    /// Mutation: returning `false` whenever there are pids.
    @Test func aSurvivingPreInstallProcessStillNeedsTheRestart() {
        #expect(PostInstallDisposition.preInstallProcessStillRunning(
            wasRunningBeforeInstall: true,
            preInstallPIDs: [52480],
            isAlive: { $0 == 52480 }))
    }

    /// Regression, Excel on the mini 2026-09-16: the user clicked Continue in App
    /// Store's close-to-update sheet, the store quit pid 52480 and later relaunched
    /// Excel as pid 8100 on the new bundle. The row said "Relaunch now" over the
    /// new build until Update All finished.
    /// Mutation: answering from `wasRunningBeforeInstall` alone (the old wiring).
    @Test func aProcessTheStoreQuitAndRelaunchedIsNotStale() {
        let runningNow: Set<pid_t> = [8100]
        #expect(!PostInstallDisposition.preInstallProcessStillRunning(
            wasRunningBeforeInstall: true,
            preInstallPIDs: [52480],
            isAlive: { runningNow.contains($0) }))
    }

    /// One survivor among several is enough.
    /// Mutation: `allSatisfy(isAlive)` instead of `contains(where:)`.
    @Test func oneSurvivorOutOfSeveralStillNeedsTheRestart() {
        #expect(PostInstallDisposition.preInstallProcessStillRunning(
            wasRunningBeforeInstall: true,
            preInstallPIDs: [101, 202],
            isAlive: { $0 == 202 }))
    }

    /// No pids to check: keep the pre-install answer rather than guess "complete".
    /// Mutation: `contains(where:)` on the empty list without the guard (→ false).
    @Test func withNoPIDsTheWasRunningFlagDecides() {
        #expect(PostInstallDisposition.preInstallProcessStillRunning(
            wasRunningBeforeInstall: true,
            preInstallPIDs: [],
            isAlive: { _ in false }))
    }

    /// Not running when the install started: nothing can have survived it, whatever
    /// the pid list says.
    /// Mutation: dropping the `wasRunningBeforeInstall` guard.
    @Test func notRunningBeforeInstallIsNeverStale() {
        #expect(!PostInstallDisposition.preInstallProcessStillRunning(
            wasRunningBeforeInstall: false,
            preInstallPIDs: [303],
            isAlive: { _ in true }))
    }
}
