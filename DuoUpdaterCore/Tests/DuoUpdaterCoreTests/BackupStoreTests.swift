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

    /// Write a `_CodeSignature/CodeResources` naming `sealing` (paths relative to
    /// `Contents/`), so the payload/droppings classification has a seal to read.
    /// Not a real signature — only the resource list is consulted.
    private func sealFixture(_ app: URL, sealing: [String]) throws {
        let dir = app.appendingPathComponent("Contents/_CodeSignature")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files2 = Dictionary(uniqueKeysWithValues: sealing.map { ($0, ["hash2": Data()]) })
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["files2": files2], format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("CodeResources"))
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

    // MARK: - Package provenance

    /// `.pkg` installs take a rollback point too (they had none until
    /// 2026-08-09), but restoring one only puts the app bundle back — a package
    /// can lay down helpers and daemons beside it. The store records which kind
    /// it was so the restore path can say so.
    @Test func aPackageBackupRemembersHowItWasInstalled() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.testapp", path: app)
            try BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: "com.example.testapp",
                fromPackageInstall: true)
            #expect(BackupStore.backup(forKey: key)?.fromPackageInstall == true)
        }
    }

    @Test func anInPlaceBackupIsNotMarkedAsAPackage() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "v1")
            let key = BackupStore.key(bundleID: "com.example.testapp", path: app)
            try BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: "com.example.testapp")
            #expect(BackupStore.backup(forKey: key)?.fromPackageInstall == false)
        }
    }

    /// Sidecars written before the field existed must still decode. A backup whose
    /// sidecar cannot be read is treated as absent, so a stricter decoder would
    /// have made every pre-existing rollback point silently vanish.
    @Test func aSidecarWithoutTheFieldStillReads() throws {
        try withScratchRoot { root in
            let key = "com.example.legacy-0000"
            let dir = root.appendingPathComponent(key, isDirectory: true)
            try makeApp(named: "Legacy.app", in: dir, marker: "old")
            let sidecar = """
            {"version":"1.0","bundleID":"com.example.legacy",\
            "originalPath":"/Applications/Legacy.app","bundleName":"Legacy.app",\
            "savedAt":\(Date().timeIntervalSinceReferenceDate)}
            """
            try Data(sidecar.utf8).write(to: dir.appendingPathComponent("backup.json"))

            let backup = BackupStore.backup(forKey: key)
            #expect(backup != nil, "an older sidecar must still be readable")
            #expect(backup?.fromPackageInstall == nil, "unknown, not false")
        }
    }

    /// `ditto` fails *late* — it copies what it can and only then exits
    /// non-zero — so a bundle with one unreadable file costs a full-size copy
    /// that is thrown away, and (when the unreadable files are root-owned) the
    /// staging cleanup cannot remove its own leftovers either. The pre-check is
    /// what keeps a `.pkg` app from paying that on every install.
    @Test func anUnreadableFileIsFoundBeforeAnythingIsCopied() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "v1")
            #expect(BackupStore.firstUnreadablePath(in: app) == nil)

            let secret = app.appendingPathComponent("Contents/secret.db")
            try Data("x".utf8).write(to: secret)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: secret.path)
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: secret.path)
            }
            // Compared through `resolvingSymlinksInPath`: the enumerator hands
            // back resolved URLs, and the scratch root lives under /tmp, which is
            // a symlink to /private/tmp. Identical for a real /Applications path.
            let found = BackupStore.firstUnreadablePath(in: app).map {
                URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
            }
            #expect(found == secret.resolvingSymlinksInPath().path)
        }
    }

    // MARK: - Self-verifying backups

    /// The gate that matters: a backup is restorable when it is byte-for-byte
    /// what we stored, regardless of whether the vendor's seal still validates.
    /// Several real apps (ToDesk, EasyConnect) break their own signature by
    /// writing state inside their bundle, and the old gate refused a perfect
    /// copy of what the user was running.
    @Test func aBackupWithABrokenVendorSealStillRestores() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "old")
            // Stand in for a vendor that dirties its own bundle: an unsigned
            // fixture with an extra file is exactly the shape that fails
            // `codesign` on a signed app.
            try Data("runtime state".utf8).write(
                to: app.appendingPathComponent("Contents/state.json"))
            let key = BackupStore.key(bundleID: "com.example.testapp", path: app)
            try BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: "com.example.testapp")

            try makeApp(named: "Fixture.app", in: root, marker: "new")
            #expect(try BackupStore.restore(forKey: key, over: app) == "1.0")
            let restored = try String(
                contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
            #expect(restored == "old")
        }
    }

    /// And the gate still bites: editing the stored copy behind our back must
    /// stop the restore, which is the whole reason a gate is there.
    @Test func tamperingWithTheStoredCopyIsRefused() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "old")
            let key = BackupStore.key(bundleID: "com.example.testapp", path: app)
            let saved = try BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: "com.example.testapp")

            try Data("tampered".utf8).write(
                to: saved.bundlePath.appendingPathComponent("Contents/marker.txt"))

            #expect(throws: BackupStore.BackupError.self) {
                try BackupStore.restore(forKey: key, over: app)
            }
        }
    }

    /// Adding a file to the stored copy is as much a change as editing one —
    /// a manifest keyed only on the files it knew about would miss it.
    @Test func anExtraFileInTheStoredCopyIsRefused() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "old")
            let key = BackupStore.key(bundleID: "com.example.testapp", path: app)
            let saved = try BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: "com.example.testapp")

            try Data("smuggled".utf8).write(
                to: saved.bundlePath.appendingPathComponent("Contents/extra.dylib"))

            #expect(throws: BackupStore.BackupError.self) {
                try BackupStore.restore(forKey: key, over: app)
            }
        }
    }

    @Test func theManifestIsStableAcrossRecomputation() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "x")
            let first = BackupManifest.compute(for: app)
            let second = BackupManifest.compute(for: app)
            #expect(first != nil)
            #expect(first == second)
        }
    }

    // MARK: - Apps that write inside their own bundle

    /// An unreadable file the signature does NOT cover is the app's own runtime
    /// state (ToDesk keeps an mmkv database and log caches under Contents/).
    /// Skipping it still yields a bundle that runs, so the backup proceeds.
    @Test func runtimeStateIsSkippedAndTheBackupStillRestores() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "old")
            // A seal is what makes the payload/droppings distinction possible, so
            // this fixture needs one — an unsigned bundle is deliberately treated
            // as all-payload (see the test below).
            try sealFixture(app, sealing: ["marker.txt", "Info.plist"])
            let dropping = app.appendingPathComponent("Contents/mmkv.default")
            try Data("state".utf8).write(to: dropping)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: dropping.path)
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: dropping.path)
            }

            let classified = BackupManifest.unreadableFiles(in: app)
            #expect(classified.sealed.isEmpty)
            #expect(classified.unsealed == ["Contents/mmkv.default"])

            let key = BackupStore.key(bundleID: "com.example.testapp", path: app)
            let saved = try BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: "com.example.testapp")
            #expect(!FileManager.default.fileExists(
                atPath: saved.bundlePath.appendingPathComponent("Contents/mmkv.default").path),
                "the unreadable dropping must not be in the stored copy")

            try makeApp(named: "Fixture.app", in: root, marker: "new")
            #expect(try BackupStore.restore(forKey: key, over: app) == "1.0")
            #expect(try String(
                contentsOf: app.appendingPathComponent("Contents/marker.txt"),
                encoding: .utf8) == "old")
        }
    }

    /// Without a `_CodeSignature` to consult we cannot tell payload from
    /// droppings, so everything unreadable counts as payload and the backup is
    /// refused rather than silently partial.
    @Test func withoutASealEveryUnreadableFileCountsAsPayload() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "old")
            let file = app.appendingPathComponent("Contents/opaque.bin")
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: file.path)
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: file.path)
            }
            #expect(BackupManifest.unreadableFiles(in: app).sealed == ["Contents/opaque.bin"])

            let key = BackupStore.key(bundleID: "com.example.testapp", path: app)
            #expect(throws: BackupStore.BackupError.self) {
                try BackupStore.save(
                    appPath: app, key: key, version: "1.0", bundleID: "com.example.testapp")
            }
        }
    }

    /// The copy must be rejected when it lost something we meant to keep — a
    /// single exit status cannot distinguish "skipped the droppings" from "ran
    /// out of disk".
    @Test func anUnexpectedOmissionIsDetected() throws {
        try withScratchRoot { root in
            let app = try makeApp(named: "Fixture.app", in: root, marker: "old")
            let copy = root.appendingPathComponent("Copy.app")
            try FileManager.default.copyItem(at: app, to: copy)
            try FileManager.default.removeItem(
                at: copy.appendingPathComponent("Contents/marker.txt"))

            let missed = BackupManifest.unexpectedOmissions(
                source: app, copy: copy, expected: [])
            #expect(missed == ["Contents/marker.txt"])
            #expect(BackupManifest.unexpectedOmissions(
                source: app, copy: copy, expected: ["Contents/marker.txt"]).isEmpty)
        }
    }
}
