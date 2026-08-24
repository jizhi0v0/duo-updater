import Foundation
import Testing

@testable import DuoUpdaterCore

/// ``BackupStore`` once an external destination is configured: what it reports
/// when the disk is not there, which store a read comes out of, and that a
/// backup parked on the destination can still be restored.
///
/// Both seams are task-local, so these run in parallel with everything else
/// without either store leaking into another suite.
@Suite struct BackupStoreDestinationTests {

    // MARK: - Fixtures

    private func withStores(
        destinationIdentity: String? = nil,
        markerIdentity: String?? = .some(nil),
        _ body: (_ outbox: URL, _ destination: URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("DuoBackupStoreDest-\(UUID().uuidString)")
        let outbox = base.appendingPathComponent("outbox", isDirectory: true)
        // `isDirectory: true` so this URL is spelled the same way
        // `BackupDestination.directory` spells it — URL equality is on the
        // string, and a missing trailing slash makes an identical path unequal.
        let destination = base.appendingPathComponent("disk", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: outbox, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        // `markerIdentity` is doubly optional on purpose: `.some(nil)` writes a
        // marker with a fresh identity, `.none` writes none at all.
        let identity: String?
        switch markerIdentity {
        case .none:
            identity = nil
        case .some(let explicit):
            let value = explicit ?? destinationIdentity ?? UUID().uuidString
            try BackupVolumeMarker(identity: value, volumeName: "TestDisk")
                .write(to: destination)
            identity = value
        }

        let configured = BackupDestination(
            kind: .external, path: destination.path,
            identity: destinationIdentity ?? (markerIdentity == nil ? nil : identity),
            volumeName: "TestDisk")

        try BackupStore.$rootOverride.withValue(outbox) {
            try BackupStore.$destinationOverride.withValue(configured) {
                try body(outbox, destination)
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

    /// Stand in for the transfer that step 4 will perform: archive the outbox
    /// copy onto the destination and write the sidecar it will carry. Built by
    /// hand rather than by calling production code so these tests exercise the
    /// *read* side against a realistic on-disk shape.
    private func promoteToDestination(
        key: String, outbox: URL, destination: URL, dropOutboxCopy: Bool
    ) throws {
        let fm = FileManager.default
        let source = outbox.appendingPathComponent(key, isDirectory: true)
        let target = destination.appendingPathComponent(key, isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)

        let entries = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        let bundle = try #require(entries.first { $0.pathExtension == "app" })
        let archiveName = bundle.deletingPathExtension().lastPathComponent + ".aar"
        let archive = target.appendingPathComponent(archiveName)
        try BundleArchive.archive(bundle: bundle, to: archive)

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

    // MARK: - Verification

    /// Fixture: one backup in each store, from two different apps.
    private func twoStores(_ outbox: URL, _ destination: URL) throws -> URL {
        let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let local = try makeApp(named: "Local.app", in: apps, marker: "local")
        try BackupStore.save(
            appPath: local, key: "local", version: "1.0", bundleID: "com.example.local")
        let moved = try makeApp(named: "Moved.app", in: apps, marker: "moved")
        try BackupStore.save(
            appPath: moved, key: "moved", version: "2.0", bundleID: "com.example.moved")
        try promoteToDestination(
            key: "moved", outbox: outbox, destination: destination, dropOutboxCopy: true)
        return apps
    }

    private func result(
        _ outcomes: [BackupStore.VerifyOutcome], _ key: String
    ) throws -> BackupStore.VerifyOutcome.Result {
        try #require(outcomes.first { $0.key == key }).result
    }

    @Test func verifyPassesForUntouchedBackupsInBothStores() throws {
        try withStores { outbox, destination in
            _ = try twoStores(outbox, destination)
            let outcomes = BackupStore.verify()
            #expect(outcomes.count == 2)
            #expect(try result(outcomes, "local") == .ok)
            #expect(try result(outcomes, "moved") == .ok)
        }
    }

    /// The point of recording a digest at transfer time: a byte that changed on
    /// a foreign filesystem is caught by asking, not by attempting a rollback and
    /// watching it fail.
    @Test func verifyCatchesATamperedArchive() throws {
        try withStores { outbox, destination in
            _ = try twoStores(outbox, destination)
            let archive = destination.appendingPathComponent("moved/Moved.aar")
            var bytes = try Data(contentsOf: archive)
            bytes[bytes.count - 1] ^= 0xFF
            try bytes.write(to: archive)

            let outcome = try result(BackupStore.verify(), "moved")
            #expect(outcome.isFailure)
            if case .mismatch = outcome {} else { Issue.record("expected a mismatch, got \(outcome)") }
        }
    }

    @Test func verifyCatchesAChangedBundleInTheOutbox() throws {
        try withStores { outbox, destination in
            _ = try twoStores(outbox, destination)
            try Data("tampered".utf8).write(
                to: outbox.appendingPathComponent("local/Local.app/Contents/marker.txt"))

            let outcome = try result(BackupStore.verify(), "local")
            #expect(outcome.isFailure)
        }
    }

    /// A backup written before fingerprints existed is not evidence of a
    /// problem. Reporting it as damaged would be a false alarm; reporting it as
    /// fine would be a reassurance nobody earned — so it gets its own answer,
    /// and does not fail the run.
    @Test func aBackupWithNothingRecordedIsNeitherPassNorFail() throws {
        try withStores { outbox, destination in
            _ = try twoStores(outbox, destination)
            let sidecar = outbox.appendingPathComponent("local/backup.json")
            var decoded = try #require(try JSONSerialization.jsonObject(
                with: Data(contentsOf: sidecar)) as? [String: Any])
            decoded["manifest"] = nil
            try JSONSerialization.data(withJSONObject: decoded).write(to: sidecar)

            let outcome = try result(BackupStore.verify(), "local")
            #expect(!outcome.isFailure)
            if case .unverifiable = outcome {} else {
                Issue.record("expected unverifiable, got \(outcome)")
            }
        }
    }

    /// Why `--deep` is worth offering. The digest only ever proves the archive
    /// is the one whose digest was recorded — swap both together and the shallow
    /// check is satisfied by an archive holding the wrong app entirely. Only
    /// unpacking it and comparing the manifest recorded at save time notices.
    @Test func deepVerificationCatchesWhatTheDigestCannot() throws {
        try withStores { outbox, destination in
            let apps = try twoStores(outbox, destination)
            let impostor = try makeApp(named: "Moved.app", in: apps, marker: "not the same app")
            let archive = destination.appendingPathComponent("moved/Moved.aar")
            try BundleArchive.archive(bundle: impostor, to: archive)

            let sidecar = destination.appendingPathComponent("moved/backup.json")
            var decoded = try #require(try JSONSerialization.jsonObject(
                with: Data(contentsOf: sidecar)) as? [String: Any])
            decoded["archiveSHA256"] = try BundleArchive.sha256(of: archive)
            try JSONSerialization.data(withJSONObject: decoded).write(to: sidecar)

            #expect(try result(BackupStore.verify(), "moved") == .ok,
                    "the digest agrees, because it was recomputed over the swap")
            let deep = try result(BackupStore.verify(deep: true), "moved")
            #expect(deep.isFailure, "unpacking it is what notices")
        }
    }

    /// A remnant with no sidecar is not a damaged backup, and must not appear in
    /// a report whose every other row is something to act on. The sweeper owns
    /// those.
    @Test func verifyIgnoresDirectoriesThatAreNotBackups() throws {
        try withStores { outbox, destination in
            _ = try twoStores(outbox, destination)
            try FileManager.default.createDirectory(
                at: outbox.appendingPathComponent("remnant", isDirectory: true),
                withIntermediateDirectories: true)
            #expect(BackupStore.verify().count == 2)
        }
    }

    // MARK: - Availability

    @Test func withoutADestinationTheStoreIsLocalOnly() throws {
        let outbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoLocalOnly-\(UUID().uuidString)")
        try BackupStore.$rootOverride.withValue(outbox) {
            try BackupStore.$destinationOverride.withValue(.local) {
                #expect(BackupStore.availability() == .localOnly(outbox))
                let resolved = try BackupStore.destinationRoot()
                #expect(resolved == nil)
            }
        }
    }

    @Test func aMountedDirectoryWithAMatchingMarkerIsReady() throws {
        try withStores { _, destination in
            #expect(BackupStore.availability() == .ready(destination))
            let resolved = try BackupStore.destinationRoot()
            #expect(resolved == destination)
        }
    }

    /// **The regression that matters most.** `save` used to reach the store via
    /// `createDirectory(withIntermediateDirectories: true)`, which on a detached
    /// disk quietly builds the whole path on the boot volume — and that directory
    /// then squats the mount point, so the real disk arrives as `Archive 1` and
    /// the backups split across two places that each look right.
    @Test func anUnmountedDestinationIsRefusedAndNothingIsCreated() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoNeverMounted-\(UUID().uuidString)")
            .appendingPathComponent("Backups")
        let configured = BackupDestination(
            kind: .external, path: path.path, identity: "X", volumeName: "Archive")

        try BackupStore.$destinationOverride.withValue(configured) {
            #expect(BackupStore.availability()
                == .volumeNotMounted(volumeName: "Archive", path: path.path))
            #expect(throws: BackupStore.BackupError.self) {
                _ = try BackupStore.destinationRoot()
            }
            #expect(BackupStore.reachableDestinationRoot == nil)
        }
        #expect(!FileManager.default.fileExists(atPath: path.path),
                "resolving an unreachable destination must not create it")
    }

    /// An empty directory where the disk should be is the *usual* shape of "not
    /// mounted" — something made the mount point — so it must not read as a
    /// perfectly good, if empty, backup store.
    @Test func aDirectoryWithoutOurMarkerIsNotOurDisk() throws {
        try withStores(destinationIdentity: "expected", markerIdentity: .none) { _, destination in
            guard case .volumeNotMounted = BackupStore.availability() else {
                Issue.record("expected .volumeNotMounted, got \(BackupStore.availability())")
                return
            }
            #expect(BackupStore.reachableDestinationRoot == nil)
            _ = destination
        }
    }

    @Test func anotherDiskAtTheSamePathIsReportedAsAMismatch() throws {
        try withStores(destinationIdentity: "expected", markerIdentity: .some("actual")) { _, _ in
            guard case .identityMismatch(let expected, let found, _)
                = BackupStore.availability() else {
                Issue.record("expected .identityMismatch, got \(BackupStore.availability())")
                return
            }
            #expect(expected == "expected")
            #expect(found == "actual")
        }
    }

    // MARK: - Save degrades to the outbox

    /// The agreed policy: an absent disk delays the copy, it does not cost the
    /// rollback point.
    @Test func saveStillSucceedsIntoTheOutboxWhenTheDiskIsMissing() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoSaveNoDisk-\(UUID().uuidString)")
        let outbox = base.appendingPathComponent("outbox")
        let apps = base.appendingPathComponent("apps")
        let missing = base.appendingPathComponent("disk/Backups")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)

        let configured = BackupDestination(
            kind: .external, path: missing.path, identity: "X", volumeName: "Archive")
        try BackupStore.$rootOverride.withValue(outbox) {
            try BackupStore.$destinationOverride.withValue(configured) {
                let app = try makeApp(named: "App.app", in: apps, marker: "v1")
                let saved = try BackupStore.save(
                    appPath: app, key: "k", version: "1.0", bundleID: "com.example.testapp")

                #expect(saved.location == .outbox)
                #expect(marker(of: saved.bundlePath) == "v1")
                #expect(BackupStore.backup(forKey: "k") != nil)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path),
                "a save must never conjure the destination directory")
    }

    // MARK: - Reads span both stores

    @Test func aBackupOnTheDestinationIsFound() throws {
        try withStores { outbox, destination in
            let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let app = try makeApp(named: "App.app", in: apps, marker: "v1")
            try BackupStore.save(
                appPath: app, key: "k", version: "1.0", bundleID: "com.example.testapp")
            try promoteToDestination(
                key: "k", outbox: outbox, destination: destination, dropOutboxCopy: true)

            let found = try #require(BackupStore.backup(forKey: "k"))
            #expect(found.location == .destination)
            #expect(found.version == "1.0")
            #expect(found.bundlePath.pathExtension == "aar")
            #expect(BackupStore.allBackups()["k"]?.location == .destination)
        }
    }

    /// A key in both stores resolves to the outbox: it is the newer copy by
    /// construction, and restoring from it does not go over the cable.
    @Test func theOutboxWinsWhenACopyExistsInBothStores() throws {
        try withStores { outbox, destination in
            let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let app = try makeApp(named: "App.app", in: apps, marker: "v1")
            try BackupStore.save(
                appPath: app, key: "k", version: "1.0", bundleID: "com.example.testapp")
            try promoteToDestination(
                key: "k", outbox: outbox, destination: destination, dropOutboxCopy: false)

            #expect(BackupStore.backup(forKey: "k")?.location == .outbox)
            #expect(BackupStore.allBackups()["k"]?.location == .outbox)
            // Both copies are listed: mid-transfer the backup really is occupying
            // both disks, and merging the rows would hide half of what deleting
            // it would free.
            let rows = BackupStore.listing().filter { $0.key == "k" }
            #expect(rows.count == 2)
            #expect(Set(rows.map(\.location)) == [.outbox, .destination])
        }
    }

    @Test func removingABackupDropsBothCopies() throws {
        try withStores { outbox, destination in
            let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let app = try makeApp(named: "App.app", in: apps, marker: "v1")
            try BackupStore.save(
                appPath: app, key: "k", version: "1.0", bundleID: "com.example.testapp")
            try promoteToDestination(
                key: "k", outbox: outbox, destination: destination, dropOutboxCopy: false)

            BackupStore.remove(forKey: "k")
            #expect(BackupStore.backup(forKey: "k") == nil)
            #expect(BackupStore.listing().filter { $0.key == "k" }.isEmpty)
        }
    }

    /// A detached disk must read as "showing what's on this Mac", never as an
    /// empty store — the difference is whether the user thinks their backups are
    /// gone.
    @Test func anUnreachableDestinationStillListsTheOutbox() throws {
        try withStores { outbox, destination in
            let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let app = try makeApp(named: "App.app", in: apps, marker: "v1")
            try BackupStore.save(
                appPath: app, key: "k", version: "1.0", bundleID: "com.example.testapp")

            // Simulate the disk going away by removing the marker.
            try FileManager.default.removeItem(
                at: destination.appendingPathComponent(BackupVolumeMarker.fileName))
            #expect(BackupStore.backup(forKey: "k")?.location == .outbox)
            #expect(BackupStore.allBackups().count == 1)
        }
    }

    // MARK: - Restore from the destination

    @Test func aBackupIsRestoredFromTheDestinationArchive() throws {
        try withStores { outbox, destination in
            let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let app = try makeApp(named: "App.app", in: apps, marker: "v1")
            try BackupStore.save(
                appPath: app, key: "k", version: "1.0", bundleID: "com.example.testapp")
            try promoteToDestination(
                key: "k", outbox: outbox, destination: destination, dropOutboxCopy: true)

            // The app moves on to v2, then rolls back.
            try makeApp(named: "App.app", in: apps, marker: "v2")
            #expect(marker(of: app) == "v2")

            let version = try BackupStore.restore(forKey: "k", over: app)
            #expect(version == "1.0")
            #expect(marker(of: app) == "v1")
        }
    }

    /// The archive digest is the only integrity question that can be asked of
    /// bytes sitting on a foreign filesystem, and it has to be fatal: restoring a
    /// truncated transfer over a working app is worse than not rolling back.
    @Test func aTamperedDestinationArchiveIsRefused() throws {
        try withStores { outbox, destination in
            let apps = outbox.deletingLastPathComponent().appendingPathComponent("apps")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let app = try makeApp(named: "App.app", in: apps, marker: "v1")
            try BackupStore.save(
                appPath: app, key: "k", version: "1.0", bundleID: "com.example.testapp")
            try promoteToDestination(
                key: "k", outbox: outbox, destination: destination, dropOutboxCopy: true)

            let archive = destination.appendingPathComponent("k/App.aar")
            var bytes = try Data(contentsOf: archive)
            bytes[bytes.count - 1] ^= 0xFF
            try bytes.write(to: archive)

            try makeApp(named: "App.app", in: apps, marker: "v2")
            #expect(throws: BackupStore.BackupError.self) {
                _ = try BackupStore.restore(forKey: "k", over: app)
            }
            #expect(marker(of: app) == "v2", "a refused rollback must leave the app alone")
        }
    }
}
