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

    private func app(_ name: String, path: String, bundleID: String) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: bundleID, shortVersion: "3.0", buildVersion: nil,
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    /// Found by the rules installed apps are found by: path, bundle id, name.
    @Test func aGoneAppIsFoundByPathBundleIDOrName() throws {
        let item = interrupted()
        let other = app("Other", path: "/Applications/Other.app", bundleID: "com.example.other")
        for query in [
            "/Applications/ZZFixture Journal.app",
            "com.example.zzfixture.journal", "ZZFixture Journal",
        ] {
            let found = try Backups.resolveRestoreTarget(
                query: query, installed: [other], interrupted: [item]).get()
            #expect(found == .interrupted(item), "\(query)")
        }
        #expect(try Backups.resolveRestoreTarget(
            query: "Other", installed: [other], interrupted: [item]).get() == .installed(other))
    }

    /// A query naming an installed app and an interrupted install is refused,
    /// as two installed apps would be — the interrupted one does not win.
    @Test func aQueryNamingAnInstalledAppAndAnInterruptedOneIsAmbiguous() {
        let item = interrupted()
        let sibling = app("ZZFixture Journal Beta", path: "/Applications/ZZFixture Journal Beta.app",
                          bundleID: "com.example.zzfixture.journal.beta")
        guard case .failure(let failure) = Backups.resolveRestoreTarget(
            query: "ZZFixture", installed: [sibling], interrupted: [item])
        else { Issue.record("expected an ambiguity"); return }
        #expect(failure.description.contains("matches 2 apps"))
    }

    /// The damaged bundle the scan still found counts once, as the
    /// interrupted install.
    @Test func aDamagedBundleTheScanFoundCountsOnceAsInterrupted() throws {
        let item = interrupted()
        let scanned = app("ZZFixture Journal", path: "/Applications/ZZFixture Journal.app",
                          bundleID: "com.example.zzfixture.journal")
        #expect(try Backups.resolveRestoreTarget(
            query: "ZZFixture Journal", installed: [scanned], interrupted: [item]).get()
            == .interrupted(item))
    }

    /// With the scan abandoned an interrupted install can still be named; a
    /// miss says what an abandoned scan says.
    @Test func anAbandonedScanStillFindsInterruptedInstalls() throws {
        let item = interrupted()
        #expect(try Backups.resolveRestoreTarget(
            query: "ZZFixture Journal", installed: nil, interrupted: [item]).get() == .interrupted(item))
        guard case .failure(let viaInterrupted) = Backups.resolveRestoreTarget(
                query: "Other", installed: nil, interrupted: [item]),
              case .failure(let plain) = Backups.resolveTarget(query: "Other", installed: nil)
        else { Issue.record("expected failures"); return }
        #expect(viaInterrupted.description == plain.description)
    }

    @Test func theStillRunningReasonNamesThePid() {
        #expect(Install.stillRunningReason(pid: 4242).contains("process 4242"))
    }

    @Test func shellQuotingLeavesPlainPathsAlone() {
        #expect(Backups.shellQuoted("/Applications/Zed.app") == "/Applications/Zed.app")
        #expect(Backups.shellQuoted("/Applications/It's Here.app") == #"'/Applications/It'\''s Here.app'"#)
    }
}
