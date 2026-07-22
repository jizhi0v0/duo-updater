import Testing
import Foundation
@testable import DuoUpdaterCore

/// Rollback backups: key sanitisation, retention=1, and the round-trip of saving
/// the current bundle and restoring it back over an "updated" one.
///
/// Serialized: `BackupStore.rootOverride` is process-global, so these must not run
/// concurrently with each other. Each test still uses its own scratch root.
@Suite(.serialized)
struct BackupStoreTests {

    /// Run `body` with `rootOverride` pointed at a fresh scratch dir, cleaned up
    /// (and the override cleared) afterwards.
    private func withScratchRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdaterBackupTest-\(UUID().uuidString)")
        BackupStore.rootOverride = root
        defer {
            BackupStore.rootOverride = nil
            try? FileManager.default.removeItem(at: root)
        }
        try body(root)
    }

    /// Build a minimal `.app` bundle with a marker file we can check survived a
    /// restore. Includes a real `Info.plist` so the bundle is *structurally valid*
    /// but unsigned: `restore` now hard-fails a backup whose present code signature
    /// won't validate, and only an `Info.plist`-bearing bundle reports the allowed
    /// `errSecCSUnsigned` (a bare directory reports `errSecCSBadBundleFormat`, which
    /// is — correctly — treated as corruption).
    @discardableResult
    private func makeApp(named name: String, in dir: URL, marker: String) throws -> URL {
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try? FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
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
        try plist.data(using: .utf8)!.write(to: contents.appendingPathComponent("Info.plist"))
        try marker.data(using: .utf8)!.write(to: contents.appendingPathComponent("marker.txt"))
        return app
    }

    private func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    // MARK: - Key sanitisation

    @Test func keySanitisesUnsafeCharacters() {
        let k = BackupStore.key(bundleID: "com.foo/bar baz:qux", path: URL(fileURLWithPath: "/x"))
        #expect(!k.contains("/"))
        #expect(!k.contains(" "))
        #expect(!k.contains(":"))
    }

    @Test func keyFallsBackToPathWithoutBundleID() {
        let k = BackupStore.key(bundleID: nil, path: URL(fileURLWithPath: "/Applications/Foo.app"))
        #expect(!k.isEmpty)
        #expect(!k.contains("/"))
    }

    @Test func keyKeepsBundleIDAsReadablePrefix() {
        let k = BackupStore.key(
            bundleID: "com.example.app",
            path: URL(fileURLWithPath: "/Applications/Foo.app"))
        #expect(k.hasPrefix("com.example.app-"))
    }

    @Test func keySeparatesCopiesWithTheSameBundleID() {
        let first = BackupStore.key(
            bundleID: "com.example.app",
            path: URL(fileURLWithPath: "/Applications/Foo.app"))
        let second = BackupStore.key(
            bundleID: "com.example.app",
            path: URL(fileURLWithPath: "/Users/me/Applications/Foo.app"))
        #expect(first != second)
    }

    @Test func keyCandidatesKeepLegacyBundleIDKeyForExistingBackups() {
        let app = URL(fileURLWithPath: "/Applications/Foo.app")
        let candidates = BackupStore.keyCandidates(bundleID: "com.example.app", path: app)

        #expect(candidates.first == BackupStore.key(bundleID: "com.example.app", path: app))
        #expect(candidates.contains("com.example.app"))
    }

    // MARK: - Save / query

    @Test func saveThenQueryReturnsBackup() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }

            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            try BackupStore.save(appPath: app, key: "com.example.foo", version: "1.0", bundleID: "com.example.foo")

            let backup = BackupStore.backup(forKey: "com.example.foo")
            #expect(backup?.version == "1.0")
            #expect(backup.map { FileManager.default.fileExists(atPath: $0.bundlePath.path) } == true)
            #expect(BackupStore.allBackups()["com.example.foo"]?.version == "1.0")
        }
    }

    @Test func retentionIsOne() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }

            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            try BackupStore.save(appPath: app, key: "k", version: "1.0", bundleID: nil)
            try BackupStore.save(appPath: app, key: "k", version: "2.0", bundleID: nil)

            // Only the newest backup survives.
            #expect(BackupStore.backup(forKey: "k")?.version == "2.0")
            let keyDir = BackupStore.root.appendingPathComponent("k")
            let entries = try FileManager.default.contentsOfDirectory(atPath: keyDir.path)
            // Exactly the bundle + the json sidecar.
            #expect(entries.contains("Foo.app"))
            #expect(entries.contains("backup.json"))
            #expect(entries.count == 2)
        }
    }

    @Test func queryReturnsNilWhenNoBackup() throws {
        try withScratchRoot { _ in
            #expect(BackupStore.backup(forKey: "nope") == nil)
            #expect(BackupStore.allBackups().isEmpty)
        }
    }

    /// Data-safety invariant: a re-backup whose copy FAILS (here, a missing source so
    /// `ditto` errors) must NOT destroy the existing rollback point, and must not leak
    /// a staging artifact into the backup listing. Retention=1 builds the new copy in
    /// a hidden staging dir and only swaps it in once complete.
    @Test func failedRebackupKeepsPriorBackup() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }

            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            try BackupStore.save(appPath: app, key: "k", version: "1.0", bundleID: nil)

            // A second save whose source can't be copied must fail without touching
            // the prior backup.
            let missing = apps.appendingPathComponent("Gone.app")
            #expect(throws: (any Error).self) {
                try BackupStore.save(appPath: missing, key: "k", version: "2.0", bundleID: nil)
            }

            let surviving = try #require(BackupStore.backup(forKey: "k"))
            #expect(surviving.version == "1.0")
            #expect(marker(of: surviving.bundlePath) == "v1")
            // No leftover staging dir leaks into the listing.
            #expect(BackupStore.allBackups().count == 1)
        }
    }

    /// A backup written before keys became path-scoped lived under the bare,
    /// sanitised bundle id. Once a canonical path-scoped backup is saved, that
    /// orphan must be dropped so we don't leak a whole stale bundle per migrated
    /// app — while the *first* (legacy-keyed) save must not delete itself.
    @Test func saveDropsOrphanedLegacyBundleIDBackup() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }

            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            let bundleID = "com.example.foo"
            let legacyKey = bundleID  // the pre-path-scoped key was the bare bundle id

            // Pre-fix backup under the legacy key. This save's own cleanup is a
            // no-op (legacy == key), so the backup it just wrote survives.
            try BackupStore.save(appPath: app, key: legacyKey, version: "1.0", bundleID: bundleID)
            #expect(BackupStore.backup(forKey: legacyKey) != nil)

            // The canonical path-scoped save supersedes and removes the orphan.
            let canonical = BackupStore.key(bundleID: bundleID, path: app)
            try BackupStore.save(appPath: app, key: canonical, version: "2.0", bundleID: bundleID)

            #expect(BackupStore.backup(forKey: canonical)?.version == "2.0")
            #expect(BackupStore.backup(forKey: legacyKey) == nil)  // orphan reclaimed
            #expect(BackupStore.allBackups().count == 1)           // exactly one copy on disk
        }
    }

    // MARK: - Restore round-trip

    @Test func restoreSwapsBackupOverUpdatedApp() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }

            // Install v1, back it up.
            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            try BackupStore.save(appPath: app, key: "k", version: "1.0", bundleID: nil)

            // "Update" the app in place to v2.
            try makeApp(named: "Foo.app", in: apps, marker: "v2")
            #expect(marker(of: app) == "v2")

            // Roll back → the bundle on disk is v1 again, backup still present.
            let restored = try BackupStore.restore(forKey: "k", over: app)
            #expect(restored == "1.0")
            #expect(marker(of: app) == "v1")
            #expect(BackupStore.backup(forKey: "k") != nil)
        }
    }

    @Test func restoreThrowsWithoutBackup() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }
            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            #expect(throws: (any Error).self) {
                try BackupStore.restore(forKey: "missing", over: app)
            }
        }
    }

    @Test func removeDropsBackup() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }
            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            try BackupStore.save(appPath: app, key: "k", version: "1.0", bundleID: nil)
            BackupStore.remove(forKey: "k")
            #expect(BackupStore.backup(forKey: "k") == nil)
        }
    }

    // MARK: - Orphan cleanup

    /// A backup whose original app path no longer exists on disk (uninstalled,
    /// or moved to a new path-scoped key) has nothing left to restore onto —
    /// `pruneOrphans` should reclaim it, and leave backups whose app is still
    /// installed untouched.
    @Test func pruneOrphansRemovesBackupsForUninstalledApps() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }

            let stillInstalled = try makeApp(named: "Keep.app", in: apps, marker: "v1")
            let uninstalled = try makeApp(named: "Gone.app", in: apps, marker: "v1")
            try BackupStore.save(appPath: stillInstalled, key: "keep", version: "1.0", bundleID: nil)
            try BackupStore.save(appPath: uninstalled, key: "gone", version: "1.0", bundleID: nil)

            // Simulate the second app having been uninstalled.
            try FileManager.default.removeItem(at: uninstalled)

            let freed = BackupStore.pruneOrphans()
            #expect(freed > 0)
            #expect(BackupStore.backup(forKey: "keep") != nil)
            #expect(BackupStore.backup(forKey: "gone") == nil)
        }
    }

    @Test func pruneOrphansIsNoOpWhenAllAppsStillInstalled() throws {
        try withScratchRoot { _ in
            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }

            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            try BackupStore.save(appPath: app, key: "k", version: "1.0", bundleID: nil)

            #expect(BackupStore.pruneOrphans() == 0)
            #expect(BackupStore.backup(forKey: "k") != nil)
        }
    }

    @Test func totalSizeReflectsStoredBackups() throws {
        try withScratchRoot { _ in
            #expect(BackupStore.totalSize() == 0)

            let apps = FileManager.default.temporaryDirectory
                .appendingPathComponent("apps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: apps) }

            let app = try makeApp(named: "Foo.app", in: apps, marker: "v1")
            try BackupStore.save(appPath: app, key: "k", version: "1.0", bundleID: nil)

            #expect(BackupStore.totalSize() > 0)
        }
    }
}
