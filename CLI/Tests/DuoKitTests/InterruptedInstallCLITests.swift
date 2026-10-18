import Testing
import Foundation
@testable import DuoKit
@testable import DuoUpdaterCore

/// What `duo` says about an install that was cut off, and how
/// `duo backups restore` finds one whose app is gone. Pure: the restore itself
/// is `BackupStore`'s, covered in `InstallJournalTests`.
struct InterruptedInstallCLITests {

    private func interrupted(
        name: String = "ZZFixture Journal", path: String = "/Applications/ZZFixture Journal.app",
        bundleID: String? = "com.example.zzfixture.journal",
        source: InstallJournal.RestoreSource? = nil
    ) -> InstallJournal.InterruptedInstall {
        InstallJournal.InterruptedInstall(
            id: UUID().uuidString, appID: path, appName: name, bundleID: bundleID,
            appPath: URL(fileURLWithPath: path), oldVersion: "1.0", oldBuild: nil,
            route: "homebrew", damage: .missing, restoreFrom: source, iconSource: nil)
    }

    @Test func theWarningNamesTheAppAndTheCommandThatPutsItBack() {
        let source = InstallJournal.RestoreSource(
            key: "k", purpose: .installRollbackPoint, version: "1.0", bundle: nil)
        #expect(Install.interruptedWarning(interrupted(source: source)) == """
            duo: warning: an update of ZZFixture Journal was interrupted, and the app is missing at /Applications/ZZFixture Journal.app.
                 Restore 1.0 (from the restore point saved before the update) with: duo backups restore '/Applications/ZZFixture Journal.app'
            """)
    }

    @Test func withNothingToRestoreFromTheWarningSaysSo() {
        #expect(Install.interruptedWarning(interrupted()).hasSuffix(
            "\n     No backup or restore point exists for it; reinstall it."))
    }

    @Test func aGoneAppIsFoundByPathBundleIDOrName() throws {
        let item = interrupted()
        for query in [
            "/Applications/ZZFixture Journal.app", "/Applications/./ZZFixture Journal.app",
            "com.example.ZZFixture.journal", "zzfixture journal",
        ] {
            let found = try Backups.matchInterrupted(query: query, in: [item]).get()
            #expect(found == item, "\(query)")
        }
        #expect(try Backups.matchInterrupted(query: "Other", in: [item]).get() == nil)
        #expect(try Backups.matchInterrupted(query: "ZZFixture Journal", in: []).get() == nil)
    }

    @Test func twoInterruptedInstallsOfOneNameAskForThePath() {
        let a = interrupted(path: "/Applications/ZZFixture Journal.app")
        let b = interrupted(path: "/Users/Shared/ZZFixture Journal.app")
        guard case .failure(let failure) = Backups.matchInterrupted(query: "ZZFixture Journal", in: [a, b])
        else { Issue.record("expected an ambiguity"); return }
        #expect(failure.description.contains("matches 2 interrupted installs"))
    }

    @Test func shellQuotingLeavesPlainPathsAlone() {
        #expect(Backups.shellQuoted("/Applications/Zed.app") == "/Applications/Zed.app")
        #expect(Backups.shellQuoted("/Applications/It's Here.app") == #"'/Applications/It'\''s Here.app'"#)
    }
}
