import Foundation
import Testing

@testable import DuoUpdaterCore

/// ``BackupStore`` when more than one backup disk is plugged in.
///
/// The feature these cover is switching disks. Backups are written to exactly
/// one disk, but a disk that has been written to in the past keeps its copies
/// forever — retention only ever supersedes a backup *within* one store — so a
/// read that saw only the disk currently being written to would make a full set
/// of rollback points vanish from every surface while they sat on a disk the
/// user had plugged in at that very moment.
///
/// The counterweight is the prune test below: reading widely is safe, deleting
/// widely is not.
@Suite struct BackupStoreMultipleDisksTests {

    // MARK: - Fixtures

    /// The outbox, the disk being written to, and a disk that is known and
    /// mounted but is not the destination — the shape left behind by switching.
    private func withTwoDisks(
        _ body: (_ outbox: URL, _ active: URL, _ retired: URL) async throws -> Void
    ) async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("DuoBackupDisks-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }

        // `isDirectory: true` throughout: `BackupDestination.directory` spells a
        // path that way, URL equality is on the string, and a missing trailing
        // slash makes an identical path unequal.
        let outbox = base.appendingPathComponent("outbox", isDirectory: true)
        let active = base.appendingPathComponent("active", isDirectory: true)
        let retired = base.appendingPathComponent("retired", isDirectory: true)
        for dir in [outbox, active, retired] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try BackupVolumeMarker(identity: "active-id", volumeName: "ActiveDisk")
            .write(to: active)
        try BackupVolumeMarker(identity: "retired-id", volumeName: "RetiredDisk")
            .write(to: retired)

        let activeDisk = BackupDestination(
            kind: .external, path: active.path, identity: "active-id",
            volumeName: "ActiveDisk")
        let retiredDisk = BackupDestination(
            kind: .external, path: retired.path, identity: "retired-id",
            volumeName: "RetiredDisk")

        try await BackupStore.$rootOverride.withValue(outbox) {
            try await BackupStore.$destinationOverride.withValue(activeDisk) {
                try await BackupStore.$knownDisksOverride.withValue([activeDisk, retiredDisk]) {
                    try await body(outbox, active, retired)
                }
            }
        }
    }

    @discardableResult
    private func makeApp(named name: String, in dir: URL, marker: String) throws -> URL {
        let fm = FileManager.default
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try? fm.removeItem(at: app)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>App</string>
          <key>CFBundleIdentifier</key><string>com.example.testapp</string>
          <key>CFBundleName</key><string>App</string>
          <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("marker.txt"))
        return app
    }

    private func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    /// Stand in for a transfer onto `disk`: archive the outbox copy and write the
    /// sidecar it would carry. Built by hand rather than through
    /// `transferToDestination`, which only ever writes to the *active* disk —
    /// these tests need a copy on the one it will not write to.
    private func promote(
        key: String, from outbox: URL, to disk: URL, dropOutboxCopy: Bool = true
    ) async throws {
        let fm = FileManager.default
        let source = outbox.appendingPathComponent(key, isDirectory: true)
        let target = disk.appendingPathComponent(key, isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)

        let entries = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        let bundle = try #require(entries.first { $0.pathExtension == "app" })
        let archiveName = bundle.deletingPathExtension().lastPathComponent + ".aar"
        let archive = target.appendingPathComponent(archiveName)
        try await BundleArchive.archive(bundle: bundle, to: archive)

        let decoded = try JSONSerialization.jsonObject(
            with: Data(contentsOf: source.appendingPathComponent("backup.json")))
        var sidecar = try #require(decoded as? [String: Any])
        sidecar["archiveName"] = archiveName
        sidecar["archiveSHA256"] = try BundleArchive.sha256(of: archive)
        sidecar["pendingTransfer"] = false
        try JSONSerialization.data(withJSONObject: sidecar)
            .write(to: target.appendingPathComponent("backup.json"))

        if dropOutboxCopy { try fm.removeItem(at: source) }
    }

    /// One backup parked on the retired disk, its app still installed.
    @discardableResult
    private func backupOnRetiredDisk(
        key: String, outbox: URL, retired: URL, apps: URL, marker: String = "v1"
    ) async throws -> URL {
        let app = try makeApp(named: "\(key).app", in: apps, marker: marker)
        try await BackupStore.save(
            appPath: app, key: key, version: "1.0", bundleID: "com.example.\(key)")
        try await promote(key: key, from: outbox, to: retired)
        return app
    }

    private func appsDirectory(beside outbox: URL) throws -> URL {
        let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        return apps
    }

    // MARK: - Reading

    @Test func aDiskWeNoLongerWriteToIsStillRead() async throws {
        try await withTwoDisks { outbox, _, retired in
            let apps = try appsDirectory(beside: outbox)
            try await backupOnRetiredDisk(key: "old", outbox: outbox, retired: retired, apps: apps)

            let found = try #require(BackupStore.backup(forKey: "old"))
            #expect(found.store.volumeName == "RetiredDisk")
            #expect(found.store.isActive == false)
            #expect(found.location == .destination)
            #expect(BackupStore.allBackups()["old"] != nil)
            #expect(BackupStore.listing().contains { $0.key == "old" })
        }
    }

    @Test func everyReachableDiskIsListedWithTheActiveOneFirst() async throws {
        try await withTwoDisks { _, active, retired in
            let disks = BackupStore.reachableDisks()
            #expect(disks.map(\.volumeName) == ["ActiveDisk", "RetiredDisk"])
            #expect(disks.map(\.isActive) == [true, false])
            #expect(disks.map(\.root.path) == [active.path, retired.path])
            // The outbox leads the full list, so a first-hit read prefers it.
            #expect(BackupStore.reachableStores().first?.location == .outbox)
        }
    }

    @Test func aBackupOnADiskWeNoLongerWriteToStillRestores() async throws {
        try await withTwoDisks { outbox, _, retired in
            let apps = try appsDirectory(beside: outbox)
            let app = try await backupOnRetiredDisk(
                key: "old", outbox: outbox, retired: retired, apps: apps)

            try makeApp(named: "old.app", in: apps, marker: "v2")
            #expect(marker(of: app) == "v2")

            let version = try await BackupStore.restore(forKey: "old", over: app)
            #expect(version == "1.0")
            #expect(marker(of: app) == "v1")
        }
    }

    /// The disk is mounted and the path is right, but the marker says it is some
    /// other disk. Reads must skip it for the same reason writes are refused:
    /// the copies on it are not the ones we recorded.
    @Test func aDiskWhoseMarkerDoesNotMatchIsNotRead() async throws {
        try await withTwoDisks { outbox, _, retired in
            let apps = try appsDirectory(beside: outbox)
            try await backupOnRetiredDisk(key: "old", outbox: outbox, retired: retired, apps: apps)

            let impostor = BackupDestination(
                kind: .external, path: retired.path, identity: "not-this-one",
                volumeName: "RetiredDisk")
            try await BackupStore.$knownDisksOverride.withValue([impostor]) {
                #expect(BackupStore.reachableDisks().isEmpty)
                #expect(BackupStore.backup(forKey: "old") == nil)
            }
        }
    }

    @Test func theOutboxCopyWinsOverEveryDisk() async throws {
        try await withTwoDisks { outbox, _, retired in
            let apps = try appsDirectory(beside: outbox)
            let app = try makeApp(named: "both.app", in: apps, marker: "local")
            try await BackupStore.save(
                appPath: app, key: "both", version: "1.0", bundleID: "com.example.both")
            try await promote(key: "both", from: outbox, to: retired, dropOutboxCopy: false)

            let found = try #require(BackupStore.backup(forKey: "both"))
            #expect(found.location == .outbox)
            #expect(found.store.identity == nil)
            // The clean-up sheet must still show both copies: each is really
            // occupying its own disk, and merging them hides half of what
            // deleting would free.
            #expect(BackupStore.listing().filter { $0.key == "both" }.count == 2)
        }
    }

    // MARK: - Writing, and what must not cross onto another disk

    /// The invariant the whole design rests on. A disk that is merely readable
    /// may be another Mac's, and "orphan" is decided by whether the app is
    /// installed *here* — so an automatic prune would identify every backup on it
    /// as an orphan, correctly, and empty it.
    @Test func pruningNeverReachesADiskWeDoNotWriteTo() async throws {
        try await withTwoDisks { outbox, active, retired in
            let apps = try appsDirectory(beside: outbox)

            for (key, disk) in [("gone-active", active), ("gone-retired", retired)] {
                let app = try makeApp(named: "\(key).app", in: apps, marker: key)
                try await BackupStore.save(
                    appPath: app, key: key, version: "1.0", bundleID: "com.example.\(key)")
                try await promote(key: key, from: outbox, to: disk)
                // Uninstall it: both backups are now orphans by the same rule.
                try FileManager.default.removeItem(at: app)
            }

            BackupStore.pruneOrphans()

            let fm = FileManager.default
            #expect(!fm.fileExists(atPath: active.appendingPathComponent("gone-active").path))
            #expect(fm.fileExists(atPath: retired.appendingPathComponent("gone-retired").path))
            #expect(BackupStore.backup(forKey: "gone-retired") != nil)
        }
    }

    /// Deleting is allowed to cross, because someone pressed a button naming
    /// this backup — the opposite of the prune above, which nobody asked for.
    @Test func deletingABackupClearsTheCopyOnEveryDisk() async throws {
        try await withTwoDisks { outbox, _, retired in
            let apps = try appsDirectory(beside: outbox)
            let app = try makeApp(named: "both.app", in: apps, marker: "local")
            try await BackupStore.save(
                appPath: app, key: "both", version: "1.0", bundleID: "com.example.both")
            try await promote(key: "both", from: outbox, to: retired, dropOutboxCopy: false)

            BackupStore.remove(forKey: "both")

            let fm = FileManager.default
            #expect(!fm.fileExists(atPath: outbox.appendingPathComponent("both").path))
            #expect(!fm.fileExists(atPath: retired.appendingPathComponent("both").path))
            #expect(BackupStore.backup(forKey: "both") == nil)
        }
    }

    /// A transfer drains the outbox onto the destination and nowhere else, even
    /// while another disk is sitting there mounted and readable.
    @Test func aTransferOnlyEverWritesToTheActiveDisk() async throws {
        try await withTwoDisks { outbox, active, retired in
            let apps = try appsDirectory(beside: outbox)
            let app = try makeApp(named: "new.app", in: apps, marker: "v1")
            try await BackupStore.save(
                appPath: app, key: "new", version: "1.0", bundleID: "com.example.new")

            try await BackupStore.transferToDestination(forKey: "new")

            let fm = FileManager.default
            #expect(fm.fileExists(atPath: active.appendingPathComponent("new").path))
            #expect(!fm.fileExists(atPath: retired.appendingPathComponent("new").path))
            #expect(BackupStore.backup(forKey: "new")?.store.isActive == true)
        }
    }

    // MARK: - Sizes

    @Test func sizesAreReportedPerStore() async throws {
        try await withTwoDisks { outbox, _, retired in
            let apps = try appsDirectory(beside: outbox)
            try await backupOnRetiredDisk(key: "old", outbox: outbox, retired: retired, apps: apps)

            let sizes = BackupStore.sizesByStore()
            #expect(sizes.map(\.store.volumeName) == [nil, "ActiveDisk", "RetiredDisk"])
            #expect(try #require(sizes.last).bytes > 0)
            // `storeSizes()` answers about the active disk only, so the copy on
            // the retired one must not be counted into it.
            #expect(BackupStore.storeSizes().destination == 0)
        }
    }
}
