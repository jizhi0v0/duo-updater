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
            wasRunningBeforeInstall: true,
            needsRestartAfterRescan: false
        )

        #expect(disposition == .awaitingBatchRestart)
    }

    @Test func stoppedBatchInstallIsCompleteImmediately() {
        let disposition = PostInstallDisposition.resolve(
            defersBookkeeping: true,
            wasRunningBeforeInstall: false,
            needsRestartAfterRescan: false
        )

        #expect(disposition == .complete)
    }

    @Test func singleInstallUsesFreshRestartProbe() {
        #expect(PostInstallDisposition.resolve(
            defersBookkeeping: false,
            wasRunningBeforeInstall: true,
            needsRestartAfterRescan: true
        ) == .awaitingRestart)

        #expect(PostInstallDisposition.resolve(
            defersBookkeeping: false,
            wasRunningBeforeInstall: true,
            needsRestartAfterRescan: false
        ) == .complete)
    }
}
