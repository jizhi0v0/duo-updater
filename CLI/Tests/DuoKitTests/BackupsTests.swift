import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

private func app(_ name: String, _ bundleID: String?, _ path: String) -> InstalledApp {
    InstalledApp(
        name: name, bundleID: bundleID, shortVersion: "2.0", buildVersion: "2",
        path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
}

@Suite struct BackupsResolveTargetTests {

    private let installed = [
        app("Cursor", "com.todesktop.230313mzl4w4u92", "/Applications/Cursor.app"),
        app("HBuilderX", "com.dcloud.HBuilderX", "/Applications/HBuilderX.app"),
        app("HBuilderX-Alpha", "com.dcloud.HBuilderX", "/Applications/HBuilderX-Alpha.app"),
    ]

    @Test func anExactNameResolvesToOneApp() throws {
        let result = Backups.resolveTarget(query: "Cursor", installed: installed)
        #expect(try result.get().name == "Cursor")
    }

    @Test func anExactPathResolvesToOneApp() throws {
        let result = Backups.resolveTarget(
            query: "/Applications/HBuilderX-Alpha.app", installed: installed)
        #expect(try result.get().name == "HBuilderX-Alpha")
    }

    /// `Inventory.select` legitimately returns both HBuilderX copies for their
    /// shared bundle id — the right answer for `install`, but a restore needs
    /// exactly one bundle to overwrite, so this must be refused rather than
    /// guessing which copy the caller meant.
    @Test func aSharedBundleIDIsRefusedRatherThanPickingOne() {
        let result = Backups.resolveTarget(
            query: "com.dcloud.HBuilderX", installed: installed)
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("HBuilderX.app"))
        #expect(failure.description.contains("HBuilderX-Alpha.app"))
    }

    @Test func anUnknownNameIsRefused() {
        let result = Backups.resolveTarget(query: "nope", installed: installed)
        guard case .failure = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
    }
}

/// `Backups.rows` (which backup belongs to which app) and `Backups.resolveKey`
/// (which key a restore should act on) both key off real `BackupStore.Backup`
/// values, and `Backup`'s initializer is internal to Core — so, like
/// `BackupStoreTests` in Core, these go through the real store with
/// `rootOverride` pointed at a scratch directory rather than hand-building
/// fixtures. None of this touches a real installed app.
@Suite(.serialized) struct BackupsStoreBackedTests {

    private func withScratchRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoKitBackupsTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try BackupStore.$rootOverride.withValue(root) {
            try body(root)
        }
    }

    @discardableResult
    private func makeApp(named name: String, in dir: URL) throws -> URL {
        let bundle = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: bundle)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try "marker".data(using: .utf8)!.write(
            to: bundle.appendingPathComponent("Contents/marker.txt"))
        return bundle
    }

    // MARK: - rows

    /// An installed app's backup is shown under the app's own name, not the
    /// hashed key — that's the whole point of joining against the inventory.
    @Test func aMatchedBackupIsLabelledWithTheAppName() throws {
        try withScratchRoot { _ in
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let bundle = try makeApp(named: "Cursor.app", in: scratch)
            let cursor = app("Cursor", "com.todesktop.230313mzl4w4u92", bundle.path)
            let key = BackupStore.key(bundleID: cursor.bundleID, path: cursor.path)
            try BackupStore.save(appPath: bundle, key: key, version: "1.0", bundleID: cursor.bundleID)

            let rows = Backups.rows(installed: [cursor], backups: BackupStore.allBackups())
            #expect(rows.count == 1)
            #expect(rows[0].app == "Cursor")
            #expect(rows[0].bundleID == cursor.bundleID)
            #expect(rows[0].path == cursor.path.path)
            #expect(rows[0].version == "1.0")
        }
    }

    /// A backup can outlive the app it was taken from (uninstalled, moved).
    /// `BackupStore.Backup` carries no name or bundle id, so the only honest
    /// label left is the key itself — dropping the row would hide real disk
    /// usage the user might want to reclaim.
    @Test func anOrphanedBackupIsListedUnderItsRawKey() throws {
        try withScratchRoot { _ in
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let bundle = try makeApp(named: "Gone.app", in: scratch)
            try BackupStore.save(appPath: bundle, key: "orphan-key", version: "9.0", bundleID: nil)

            let rows = Backups.rows(installed: [], backups: BackupStore.allBackups())
            #expect(rows.count == 1)
            #expect(rows[0].app == "orphan-key")
            #expect(rows[0].bundleID == nil)
            #expect(rows[0].path == nil)
        }
    }

    @Test func rowsAreSortedByAppNameCaseInsensitively() throws {
        try withScratchRoot { _ in
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let bananaBundle = try makeApp(named: "banana.app", in: scratch)
            let appleBundle = try makeApp(named: "Apple.app", in: scratch)
            let banana = app("banana", nil, bananaBundle.path)
            let apple = app("Apple", nil, appleBundle.path)
            try BackupStore.save(
                appPath: bananaBundle, key: BackupStore.key(bundleID: nil, path: banana.path),
                version: "1.0", bundleID: nil)
            try BackupStore.save(
                appPath: appleBundle, key: BackupStore.key(bundleID: nil, path: apple.path),
                version: "1.0", bundleID: nil)

            let rows = Backups.rows(installed: [banana, apple], backups: BackupStore.allBackups())
            #expect(rows.map(\.app) == ["Apple", "banana"])
        }
    }

    @Test func backupSizeReflectsWhatWasStored() throws {
        try withScratchRoot { _ in
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let bundle = try makeApp(named: "Foo.app", in: scratch)
            try BackupStore.save(appPath: bundle, key: "k", version: "1.0", bundleID: nil)

            let backup = try #require(BackupStore.backup(forKey: "k"))
            #expect(Backups.backupSize(backup) > 0)
        }
    }

    // MARK: - resolveKey

    @Test func resolvesToTheCanonicalKeyWhenABackupExists() throws {
        try withScratchRoot { _ in
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let bundle = try makeApp(named: "Foo.app", in: scratch)
            let target = app("Foo", "com.example.foo", bundle.path)
            let key = BackupStore.key(bundleID: target.bundleID, path: target.path)
            try BackupStore.save(appPath: bundle, key: key, version: "1.0", bundleID: target.bundleID)

            #expect(Backups.resolveKey(for: target) == key)
        }
    }

    /// A backup saved before keys became path-scoped lives under the bare
    /// bundle id. `AppListModel.rollback` still finds it via `keyCandidates`,
    /// and this must too — otherwise upgrading to path-scoped keys would have
    /// silently orphaned every pre-existing rollback point from the CLI's view.
    @Test func fallsBackToTheLegacyKeyWhenOnlyItHasABackup() throws {
        try withScratchRoot { _ in
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let bundle = try makeApp(named: "Foo.app", in: scratch)
            let target = app("Foo", "com.example.foo", bundle.path)
            let legacyKey = "com.example.foo"
            try BackupStore.save(appPath: bundle, key: legacyKey, version: "1.0", bundleID: target.bundleID)

            #expect(Backups.resolveKey(for: target) == legacyKey)
        }
    }

    @Test func returnsNilRatherThanAKeyWithNoBackup() throws {
        try withScratchRoot { _ in
            let target = app("Nope", "com.example.nope", "/Applications/Nope.app")
            #expect(Backups.resolveKey(for: target) == nil)
        }
    }
}
