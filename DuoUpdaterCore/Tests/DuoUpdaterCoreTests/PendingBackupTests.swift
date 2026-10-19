import Darwin
import Foundation
import Testing

@testable import DuoUpdaterCore

/// An install's backup waits in the pending slot and becomes the user's backup
/// only once the app is no longer the bundle it was copied from — so an
/// install cancelled or failed after its backup keeps the way back to the
/// version before. See ``BackupStore/pendingBackupsRoot``.
///
/// The fixture walks the whole sequence the bug report describes: the app at
/// N with a backup of N-1 (`BackupStore.save`, the slot as a previous install
/// left it), then an N→N+1 attempt that backs up N (`InstallCoordinator.backUp`).
///
/// Every seam is task-local, so these run in parallel with everything else.
@Suite struct PendingBackupTests {

    private static let bundleID = "com.example.zzfixture.pending"

    private func withStore(
        disk: Bool = false,
        _ body: (_ apps: URL, _ outbox: URL, _ disk: URL) async throws -> Void
    ) async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("ZZFixture-pending-\(UUID().uuidString)")
        let outbox = base.appendingPathComponent("outbox", isDirectory: true)
        let diskRoot = base.appendingPathComponent("disk", isDirectory: true)
        let apps = base.appendingPathComponent("apps", isDirectory: true)
        let facts = base.appendingPathComponent("facts", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        for dir in [outbox, diskRoot, apps] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var destination = BackupDestination.local
        if disk {
            let identity = UUID().uuidString
            try BackupVolumeMarker(identity: identity, volumeName: "TestDisk").write(to: diskRoot)
            destination = BackupDestination(
                kind: .external, path: diskRoot.path, identity: identity, volumeName: "TestDisk")
        }
        try await BackupStore.$rootOverride.withValue(outbox) {
            try await BackupStore.$destinationOverride.withValue(destination) {
                try await BackupFactsLibrary.$rootOverride.withValue(facts) {
                    try await BackupStore.$runningOverride.withValue({ _ in false }) {
                        try await BundleStatIdentity.$racyWindowOverride.withValue(0) {
                            try await body(apps, outbox, diskRoot)
                        }
                    }
                }
            }
        }
    }

    /// `Foo.app` at `version` (marketing) / `build`, replacing whatever was
    /// there — a new bundle, as an update's swap leaves it.
    @discardableResult
    private func install(
        in dir: URL, version: String, build: String = "1", marker: String? = nil
    ) throws -> URL {
        let app = dir.appendingPathComponent("Foo.app")
        try? FileManager.default.removeItem(at: app)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>App</string>
          <key>CFBundleIdentifier</key><string>\(Self.bundleID)</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleShortVersionString</key><string>\(version)</string>
          <key>CFBundleVersion</key><string>\(build)</string>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        try Data((marker ?? version).utf8).write(to: contents.appendingPathComponent("marker.txt"))
        return app
    }

    private func installed(_ app: URL, version: String, build: String = "1") -> InstalledApp {
        InstalledApp(
            name: "Foo", bundleID: Self.bundleID, shortVersion: version, buildVersion: build,
            path: app, isMASApp: false, sparkleFeedURL: nil)
    }

    private func key(_ app: URL) -> String { BackupStore.key(bundleID: Self.bundleID, path: app) }

    /// The slot as the install of N-1 → N left it: a backup of N-1, and the
    /// app at N.
    private func appAtNWithBackupOfNMinus1(in apps: URL) async throws -> URL {
        let app = try install(in: apps, version: "1.0")
        try await BackupStore.save(
            appPath: app, key: key(app), version: "1.0", buildVersion: "1",
            bundleID: Self.bundleID)
        return try install(in: apps, version: "2.0")
    }

    private func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    private func inode(_ url: URL) -> ino_t {
        var st = stat()
        lstat(url.path, &st)
        return st.st_ino
    }

    private func pendingDir(_ app: URL) -> URL {
        BackupStore.pendingBackupsRoot.appendingPathComponent(key(app), isDirectory: true)
    }

    private func pendingMarkerInode(_ app: URL) -> ino_t {
        inode(pendingDir(app).appendingPathComponent("Foo.app/Contents/marker.txt"))
    }

    private func testLock(_ base: URL) -> ProcessInstallLock {
        ProcessInstallLock(url: base.appendingPathComponent("install-\(UUID().uuidString).lock"))
    }

    // MARK: - Cancel and retry

    /// The bug: backing up N for the N→N+1 install replaced the backup of N-1
    /// at once, so a cancel left N installed, the backup of N restoring
    /// nothing, and no way back to N-1. Now the backup of N-1 is still the
    /// backup — distinct from what is installed, so the Rollback row stays —
    /// and it restores.
    /// Mutation: `savePending` writing into the user's slot (`store` ignoring
    /// `pending` in `write`) → the backup reads 2.0, red.
    @Test func aCancelAfterTheBackupKeepsTheEarlierBackupRestorable() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            // The install is cancelled before its swap: nothing changed.
            #expect(await InstallCoordinator.settlePendingBackup(for: atN) == .kept)

            let backup = try #require(BackupStore.backup(forKey: key(app)))
            #expect(backup.version == "1.0")
            #expect(BackupStore.rollbackIsDistinct(installed: atN.versionSide, backup: backup.versionSide))
            #expect(BackupStore.allBackups()[key(app)]?.version == "1.0")
            // The copy of N waits, unlisted.
            #expect(FileManager.default.fileExists(atPath: pendingDir(app).path))
            #expect(BackupStore.listing().map(\.version) == ["1.0"])

            try await BackupStore.restore(forKey: key(app), over: app)
            #expect(marker(of: app) == "1.0")
        }
    }

    /// The retry backs up the same unchanged N: the pending copy is reused —
    /// nothing copied — and the backup of N-1 is still the backup.
    /// Mutation: drop the pending slot from `reusableBackup`'s lookup (always
    /// the user's slot) → a fresh copy, new inode, red.
    @Test func aRetryReusesThePendingCopy() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            await InstallCoordinator.settlePendingBackup(for: atN)
            let first = pendingMarkerInode(app)

            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            #expect(pendingMarkerInode(app) == first)
            #expect(BackupStore.backup(forKey: key(app))?.version == "1.0")
            await InstallCoordinator.settlePendingBackup(for: atN)
        }
    }

    // MARK: - Commit

    /// The install lands: N+1 is installed, and the copy of N is the backup
    /// now — it restores N — with nothing left pending.
    @Test func aLandedInstallPromotesThePendingCopy() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            try install(in: apps, version: "3.0")
            #expect(await InstallCoordinator.settlePendingBackup(for: atN) == .promoted)

            let backup = try #require(BackupStore.backup(forKey: key(app)))
            #expect(backup.version == "2.0")
            #expect(!FileManager.default.fileExists(atPath: pendingDir(app).path))
            #expect(BackupStore.listing().count == 1)
            try await BackupStore.restore(forKey: key(app), over: app)
            #expect(marker(of: app) == "2.0")
        }
    }

    /// A swap cut off with the app gone (brew removed it and did not put it
    /// back): the copy of N is the way back, so it is the backup now, whatever
    /// the install said. Mutation: the readable-bundle guard in
    /// `pendingIsSuperseded` returning false (missing counts as unchanged) →
    /// kept, red.
    @Test func anAppLeftMissingPromotesTheCopyAsTheWayBack() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .homebrew) == .saved)
            try FileManager.default.removeItem(at: app)
            #expect(await InstallCoordinator.settlePendingBackup(for: atN) == .promoted)
            #expect(BackupStore.backup(forKey: key(app))?.version == "2.0")
        }
    }

    /// The process died between the swap and the settle. The launch sweep
    /// finds the app changed since the copy and promotes it; a pending copy
    /// whose app is unchanged (a cancelled leftover) stays pending, and the
    /// earlier backup stays the backup.
    /// Mutations: `pendingIsSuperseded` without the version comparison → the
    /// crashed one is kept, red; the sweep promoting without that test → the
    /// leftover replaces 1.0, red.
    @Test func theLaunchSweepPromotesAfterACrashAndKeepsACancelledLeftover() async throws {
        try await withStore { apps, outbox, _ in
            // Crashed after its swap: no settle ran.
            let crashedDir = apps.appendingPathComponent("crashed", isDirectory: true)
            let crashed = try await appAtNWithBackupOfNMinus1(in: crashedDir)
            try await BackupStore.savePending(
                appPath: crashed, key: key(crashed), version: "2.0", buildVersion: "1",
                bundleID: Self.bundleID)
            try install(in: crashedDir, version: "3.0")
            // Cancelled: its app is still N.
            let cancelledDir = apps.appendingPathComponent("cancelled", isDirectory: true)
            let cancelled = try await appAtNWithBackupOfNMinus1(in: cancelledDir)
            try await BackupStore.savePending(
                appPath: cancelled, key: key(cancelled), version: "2.0", buildVersion: "1",
                bundleID: Self.bundleID)

            #expect(await InstallCoordinator.sweepPendingBackups(lock: testLock(outbox)) == 1)
            #expect(BackupStore.backup(forKey: key(crashed))?.version == "2.0")
            #expect(!FileManager.default.fileExists(atPath: pendingDir(crashed).path))
            #expect(BackupStore.backup(forKey: key(cancelled))?.version == "1.0")
            #expect(FileManager.default.fileExists(atPath: pendingDir(cancelled).path))
        }
    }

    /// A key an install in this process is holding is not the sweep's to
    /// decide, even with its app already changed: the install settles it.
    /// Mutation: drop the `beginSweeping` guard in `sweepPendingBackups` →
    /// promoted under the install, red.
    @Test func theLaunchSweepLeavesAKeyAnInstallHolds() async throws {
        try await withStore { apps, outbox, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            // `backUp` claims the key until the settle.
            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            try install(in: apps, version: "3.0")
            #expect(await InstallCoordinator.sweepPendingBackups(lock: testLock(outbox)) == 0)
            #expect(BackupStore.backup(forKey: key(app))?.version == "1.0")
            #expect(await InstallCoordinator.settlePendingBackup(for: atN) == .promoted)
        }
    }

    /// A pending copy of N left by a cancelled attempt, then the app updated
    /// itself to N+1: the next install's backup first makes that copy the
    /// backup (the version before the last update), then waits as N+1's own.
    /// Mutation: drop the `settlePending` call at the top of `write` → the
    /// copy of N is replaced unseen and the backup stays 1.0, red.
    @Test func aStalePendingCopyIsPromotedBeforeTheNextCopy() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            await InstallCoordinator.settlePendingBackup(for: atN)
            try install(in: apps, version: "3.0")
            let atNPlus1 = installed(app, version: "3.0")

            #expect(await InstallCoordinator.backUp(atNPlus1, route: .sparkle) == .saved)
            #expect(BackupStore.backup(forKey: key(app))?.version == "2.0")
            #expect(marker(of: pendingDir(app).appendingPathComponent("Foo.app")) == "3.0")
            await InstallCoordinator.settlePendingBackup(for: atNPlus1)
        }
    }

    // MARK: - What counts as changed

    /// An app that writes into its own bundle while it runs changes on disk
    /// without changing version: an install that did not land must not spend
    /// the rollback point on it.
    @Test func filesWrittenInsideTheBundleDoNotPromoteAFailedInstall() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            try Data("state".utf8).write(to: app.appendingPathComponent("Contents/runtime.db"))
            #expect(await InstallCoordinator.settlePendingBackup(for: atN) == .kept)
            #expect(BackupStore.backup(forKey: key(app))?.version == "1.0")
        }
    }

    /// A swap that put the same version back — the download was not the one
    /// the feed advertised, which the host reports as "applied nothing" after
    /// the coordinator said `applied` — changed the bundle's files but not
    /// the app: the earlier backup stays the way back.
    /// Mutation: promote whenever the walk differs (the dropped
    /// `succeeded`-gated branch, unconditional) → 2.0 replaces 1.0, red.
    @Test func aSwapThatLeftTheSameVersionKeepsTheEarlierBackup() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .vendor) == .saved)
            try install(in: apps, version: "2.0", marker: "2.0-again")
            #expect(await InstallCoordinator.settlePendingBackup(for: atN) == .kept)
            #expect(BackupStore.backup(forKey: key(app))?.version == "1.0")
        }
    }

    /// An app in a scan folder on a disk that is not mounted is unreachable,
    /// not changed: a sweep then must not spend the earlier backup on it.
    /// Mutation: drop the folder test in `pendingIsSuperseded` (missing app
    /// always promotes) → 2.0 replaces 1.0, red.
    @Test func anAppOnAVolumeThatIsNotMountedIsNotChanged() async throws {
        try await withStore { apps, outbox, _ in
            let volume = apps.appendingPathComponent("Volume", isDirectory: true)
            let app = try await appAtNWithBackupOfNMinus1(in: volume)
            try await BackupStore.savePending(
                appPath: app, key: key(app), version: "2.0", buildVersion: "1",
                bundleID: Self.bundleID)
            try FileManager.default.removeItem(at: volume)
            #expect(await InstallCoordinator.sweepPendingBackups(lock: testLock(outbox)) == 0)
            #expect(BackupStore.backup(forKey: key(app))?.version == "1.0")
            #expect(FileManager.default.fileExists(atPath: pendingDir(app).path))
        }
    }

    /// The app's launch drops a cancelled attempt's leftover whose app is
    /// unchanged — nothing lists it, so nothing else could remove it — and
    /// still promotes one whose app changed. Other sweeps keep the leftover.
    /// Mutation: ignore `droppingUnchanged` → the leftover stays, red.
    @Test func theLaunchDropsAnUnchangedLeftover() async throws {
        try await withStore { apps, outbox, _ in
            let app = try install(in: apps, version: "2.0")
            try await BackupStore.savePending(
                appPath: app, key: key(app), version: "2.0", buildVersion: "1",
                bundleID: Self.bundleID)
            #expect(await InstallCoordinator.sweepPendingBackups(lock: testLock(outbox)) == 0)
            #expect(FileManager.default.fileExists(atPath: pendingDir(app).path))
            #expect(await InstallCoordinator.sweepPendingBackups(
                lock: testLock(outbox), droppingUnchanged: true) == 0)
            #expect(!FileManager.default.fileExists(atPath: pendingDir(app).path))
            #expect(BackupStore.backup(forKey: key(app)) == nil)
        }
    }

    // MARK: - Out of every other path's way

    /// With a backup disk, the copy is owed to it only once it is the backup:
    /// never while pending.
    /// Mutation: a non-hidden pending root (`pending` instead of `.pending`)
    /// → the key is listed as owed and the transfer ships it, red.
    @Test func theTransferNeverShipsAPendingCopy() async throws {
        try await withStore(disk: true) { apps, _, _ in
            let app = try install(in: apps, version: "2.0")
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            #expect(BackupStore.pendingTransferKeys().isEmpty)
            await #expect(throws: BackupStore.BackupError.self) {
                try await BackupStore.transferToDestination(forKey: key(app))
            }
            #expect(BackupStore.allBackups().isEmpty)

            try install(in: apps, version: "3.0")
            #expect(await InstallCoordinator.settlePendingBackup(for: atN) == .promoted)
            #expect(BackupStore.pendingTransferKeys() == [key(app)])
            let moved = try await BackupStore.transferToDestination(forKey: key(app))
            #expect(moved.location == .destination)
            #expect(moved.version == "2.0")
        }
    }

    /// Not an orphan while its app is gone, not listed, not a victim of the
    /// low-space prune — but counted in this Mac's total.
    @Test func noSweepOrListingTouchesAPendingCopy() async throws {
        try await withStore { apps, outbox, _ in
            let app = try install(in: apps, version: "2.0")
            try await BackupStore.savePending(
                appPath: app, key: key(app), version: "2.0", buildVersion: "1",
                bundleID: Self.bundleID)
            try FileManager.default.removeItem(at: app)

            #expect(BackupStore.listing().isEmpty)
            #expect(BackupStore.pruneOrphans() == 0)
            BackupStore.sweepStaleScratch(olderThan: 0)
            // Nothing it may delete: false, and the pending copy untouched.
            let reclaimed = await BackupStore.$freeBytesOverride.withValue({ 0 }) {
                await BackupStore.reclaimFreeSpace(sparing: "someone-else")
            }
            #expect(!reclaimed)
            #expect(FileManager.default.fileExists(
                atPath: pendingDir(app).appendingPathComponent("backup.json").path))
            #expect(BackupStore.storeSize(of: outbox) > 0)
        }
    }

    /// Deleting the app's backup takes its pending copy with it: nothing on
    /// screen could reach it afterwards. Mutation: drop `discardPending` from
    /// `remove(forKey:)` → the copy stays, red.
    @Test func removingTheBackupRemovesThePendingCopyToo() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            try await BackupStore.savePending(
                appPath: app, key: key(app), version: "2.0", buildVersion: "1",
                bundleID: Self.bundleID)
            BackupStore.remove(forKey: key(app))
            #expect(BackupStore.backup(forKey: key(app)) == nil)
            #expect(!FileManager.default.fileExists(atPath: pendingDir(app).path))
        }
    }

    /// A Relaunch that stands down because the app quit mid-copy discards the
    /// copy it took — the pending one — and only that: the backup before it
    /// is the way back. It used to remove the key's backup outright.
    @Test func aRelaunchStandDownDiscardsOnlyThePendingCopy() async throws {
        try await withStore { apps, _, _ in
            let app = try await appAtNWithBackupOfNMinus1(in: apps)
            let atN = installed(app, version: "2.0")
            #expect(await InstallCoordinator.backUp(atN, route: .sparkle) == .saved)
            await StagedRelaunchBackup.System.live(for: atN, backUp: { .failed }).remove()
            #expect(!FileManager.default.fileExists(atPath: pendingDir(app).path))
            #expect(BackupStore.backup(forKey: key(app))?.version == "1.0")
            #expect(await InstallCoordinator.settlePendingBackup(for: atN) == .none)
        }
    }

    /// `backUp` for an input method snapshots its user data into the pending
    /// copy's directory, never beside the earlier backup: that one keeps the
    /// data it was taken with. Mutation: drop `in:` from the
    /// `InputMethodDataBackup.save` call in `backUp` → the snapshot of N lands
    /// beside the backup of N-1, red.
    @Test func backUpSnapshotsAnInputMethodIntoThePendingCopy() async throws {
        try await withStore { apps, _, _ in
            let home = apps.appendingPathComponent("home", isDirectory: true)
            let data = home.appendingPathComponent("Library/Application Support/Foo", isDirectory: true)
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            try Data("dictionary".utf8).write(to: data.appendingPathComponent("user.dict"))
            // An input method is told by its folder (`UpdatePolicy.isInputMethod`).
            let folder = apps.appendingPathComponent("Library/Input Methods", isDirectory: true)
            let app = try await appAtNWithBackupOfNMinus1(in: folder)
            let atN = installed(app, version: "2.0")
            let outcome = await InputMethodDataBackup.$homeOverride.withValue(home) {
                await InstallCoordinator.backUp(atN, route: .vendor)
            }
            #expect(outcome == .saved)
            #expect(InputMethodDataBackup.snapshotExists(
                in: InputMethodDataBackup.snapshotDirectory(
                    forKey: key(app), in: BackupStore.pendingBackupsRoot)))
            #expect(!InputMethodDataBackup.snapshotExists(
                in: InputMethodDataBackup.snapshotDirectory(forKey: key(app))))
            await InstallCoordinator.settlePendingBackup(for: atN)
        }
    }

    /// An input method's user-data snapshot is taken into the pending copy's
    /// directory and travels with it when it is promoted. Mutation:
    /// `InputMethodDataBackup.save` ignoring `root` (the outbox as before) →
    /// no generation there to attach to, nothing snapshotted, red.
    @Test func anInputMethodSnapshotMovesWithThePromotedCopy() async throws {
        try await withStore { apps, _, _ in
            let home = apps.appendingPathComponent("home", isDirectory: true)
            let data = home.appendingPathComponent("Library/Application Support/Foo", isDirectory: true)
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            try Data("dictionary".utf8).write(to: data.appendingPathComponent("user.dict"))
            let app = try install(in: apps, version: "2.0")
            try await BackupStore.savePending(
                appPath: app, key: key(app), version: "2.0", buildVersion: "1",
                bundleID: Self.bundleID)
            let captured = await InputMethodDataBackup.$homeOverride.withValue(home) {
                await InputMethodDataBackup.save(
                    bundleName: "Foo", bundleID: Self.bundleID, key: key(app),
                    in: BackupStore.pendingBackupsRoot)
            }
            #expect(!captured.isEmpty)
            try install(in: apps, version: "3.0")
            #expect(await BackupStore.settlePending(forKey: key(app)) == .promoted)
            #expect(InputMethodDataBackup.snapshotExists(
                in: InputMethodDataBackup.snapshotDirectory(forKey: key(app))))
        }
    }
}
