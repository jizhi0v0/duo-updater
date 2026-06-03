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
    /// restore.
    @discardableResult
    private func makeApp(named name: String, in dir: URL, marker: String) throws -> URL {
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try? FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
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

    @Test func keyPrefersBundleID() {
        let k = BackupStore.key(bundleID: "com.example.app", path: URL(fileURLWithPath: "/Applications/Foo.app"))
        #expect(k == "com.example.app")
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
}
