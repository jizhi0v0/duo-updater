import Foundation
import Testing
@testable import DuoUpdaterCore

/// "Update All" posts one banner saying how many apps it updated, and it counts
/// the outcomes of the installs it ran. A vendor `.pkg` is not one of them: the
/// batch stages the package and opens macOS's Installer, which the user then has
/// to drive. While that hand-off returned the same `true` a finished swap did, a
/// batch of two pkg apps announced "2 apps were updated" with both Installer
/// windows still open and neither bundle replaced.
///
/// It is equally not a failure — the row keeps its staged package and shows no
/// error — which is why it is a third case rather than being folded into either
/// side.
@Suite struct InstallAttemptOutcomeTests {

    @Test func onlyARealInstallIsCountedIntoTheBatchBanner() {
        #expect(InstallAttemptOutcome.installed.countsAsUpdatedApp)
        #expect(!InstallAttemptOutcome.handedOffToSystemInstaller.countsAsUpdatedApp)
        #expect(!InstallAttemptOutcome.notInstalled.countsAsUpdatedApp)
    }

    /// The hand-off must stay distinguishable from the failure/early-out case, not
    /// merely uncounted: it is what tells the row it has a package waiting rather
    /// than an install that went nowhere.
    @Test func aHandOffIsNeitherAnInstallNorANonInstall() {
        #expect(InstallAttemptOutcome.handedOffToSystemInstaller != .installed)
        #expect(InstallAttemptOutcome.handedOffToSystemInstaller != .notInstalled)
    }
}
