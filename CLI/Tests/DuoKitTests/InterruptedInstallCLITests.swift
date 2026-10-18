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

    /// Round 3, #6a: an earlier install that was cut off but never looked at
    /// (the lock was busy at launch) may have left nothing to restore from.
    /// The line says what the way back is, and that there is none when there
    /// is none — not that "the restore point stays".
    @Test func theNoBackupLineSaysWhatTheWayBackIs() {
        let point = InstallJournal.RestoreSource(
            key: "k", purpose: .installRollbackPoint, version: "1.0", bundle: nil)
        let backup = InstallJournal.RestoreSource(key: "k", purpose: .userBackup, version: "0.9", bundle: nil)
        #expect(Install.earlierInstallBackupNote(.interrupted, wayBack: point) == "no new backup: an earlier"
            + " update of it was interrupted, and the app on disk may be the copy it damaged;"
            + " the restore point saved before that update stays as it is")
        #expect(Install.earlierInstallBackupNote(.interrupted, wayBack: backup)
            .hasSuffix("; your backup of 0.9 stays as it is"))
        let none = Install.earlierInstallBackupNote(.interrupted, wayBack: nil)
        #expect(none.hasSuffix("; there is no backup or restore point of it from before that update"))
        #expect(!none.contains("stays"))
        #expect(Install.earlierInstallBackupNote(.stillRunning(pid: 4242), wayBack: nil)
            == "no new backup: an earlier install of it is still running (process 4242)")
        #expect(Restart.describe(
            .attempted(.skippedForEarlierInstall(.interrupted)), version: "1.0", wayBack: nil) == none)
    }

    /// Round 4, #4: `duo restart` processes the journal first, as `duo install`
    /// does, so a dead install no launch has looked at is classified before
    /// the restart's backup asks the app's standing. Here its app is gone, so
    /// processing marks it missing; unprocessed it would carry no damage.
    /// The query names no app, so nothing is restarted (exit 2).
    @Test func restartProcessesTheJournalFirst() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-restart-journal-\(UUID().uuidString)", isDirectory: true)
        let journal = dir.appendingPathComponent("install-journal", isDirectory: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = dir.appendingPathComponent("ZZFixture-Gone.app")  // never created
        let entry = InstallJournal.Entry(
            job: UUID().uuidString, appID: app.path, appName: "ZZFixture Gone",
            bundleID: "com.example.zzfixture.gone", appPath: app.path,
            oldVersion: "1.0", oldBuild: nil, oldCDHash: nil,
            targetVersion: "2.0", targetBuild: nil, route: "homebrew",
            backupKey: BackupStore.key(bundleID: "com.example.zzfixture.gone", path: app),
            startedAt: Date(),
            // This pid, but not this process: its start time is not ours.
            owner: InstallJournal.ProcessStamp(pid: getpid(), started: 1))
        try #require(InstallJournal.write(entry, to: journal.appendingPathComponent("\(entry.job).json")))

        var options = Restart.Options()
        options.queries = ["ZZFixture-no-such-app-\(UUID().uuidString)"]
        let lock = ProcessInstallLock(url: dir.appendingPathComponent("install.lock"))
        try await InstallJournal.$rootOverride.withValue(journal) {
            try #require(InstallJournal.interruptedInstalls().isEmpty)
            #expect(await Restart.run(options, lock: lock) == 2)
            #expect(InstallJournal.interruptedInstalls().map(\.damage) == [.missing])
        }
    }

    @Test func theStillRunningReasonNamesThePid() {
        #expect(Install.stillRunningReason(pid: 4242).contains("process 4242"))
    }

    @Test func shellQuotingLeavesPlainPathsAlone() {
        #expect(Backups.shellQuoted("/Applications/Zed.app") == "/Applications/Zed.app")
        #expect(Backups.shellQuoted("/Applications/It's Here.app") == #"'/Applications/It'\''s Here.app'"#)
    }
}
