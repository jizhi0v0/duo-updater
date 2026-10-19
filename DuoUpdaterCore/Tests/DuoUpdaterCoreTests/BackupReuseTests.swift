import Darwin
import Foundation
import Testing

@testable import DuoUpdaterCore

/// A retried install backing up the bundle the store already holds a copy of:
/// reused when nothing in the bundle has been written since, copied again the
/// moment anything has. See ``BundleStatIdentity``.
///
/// Every seam is task-local, so these run in parallel with everything else.
/// The racy window is bound to zero for the fixtures written a moment ago —
/// except in the test that is about that window.
@Suite struct BackupReuseTests {

    private func withStore(
        disk: Bool = false,
        _ body: (_ apps: URL, _ outbox: URL, _ disk: URL) async throws -> Void
    ) async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("DuoBackupReuse-\(UUID().uuidString)")
        let outbox = base.appendingPathComponent("outbox", isDirectory: true)
        let diskRoot = base.appendingPathComponent("disk", isDirectory: true)
        let apps = base.appendingPathComponent("apps", isDirectory: true)
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
                try await BundleStatIdentity.$racyWindowOverride.withValue(0) {
                    try await body(apps, outbox, diskRoot)
                }
            }
        }
    }

    private func makeApp(in dir: URL, marker: String = "v1") throws -> URL {
        let app = dir.appendingPathComponent("Foo.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>App</string>
          <key>CFBundleIdentifier</key><string>com.example.reuse</string>
          <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("marker.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: contents.appendingPathComponent("Frameworks/Current").path,
            withDestinationPath: "A")
        return app
    }

    private func save(_ app: URL, version: String = "1.0", build: String? = "100") async throws
        -> BackupStore.Backup {
        try await BackupStore.save(
            appPath: app, key: "foo", version: version, buildVersion: build,
            bundleID: "com.example.reuse")
    }

    private func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    private func inode(_ url: URL) -> ino_t {
        var st = stat()
        lstat(url.path, &st)
        return st.st_ino
    }

    /// Rewrite `file` with same-size content and put its modification time
    /// back, so size, inode and mtime all read as before. Only the change
    /// time — which nothing in userland can set — shows the write.
    private func rewriteKeepingMTime(_ file: URL, with content: String) throws {
        var before = stat()
        lstat(file.path, &before)
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data(content.utf8))
        try handle.close()
        var times = [before.st_atimespec, before.st_mtimespec]
        #expect(utimensat(AT_FDCWD, file.path, &times, AT_SYMLINK_NOFOLLOW) == 0)
        var after = stat()
        lstat(file.path, &after)
        #expect(after.st_size == before.st_size)
        #expect(after.st_ino == before.st_ino)
        #expect(after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec)
        #expect(after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec)
    }

    // MARK: - Reuse

    /// The cancel-then-retry case: the second attempt finds its own earlier
    /// copy and stores nothing new — same generation, same files — and that
    /// copy still restores through every gate.
    @Test func aRetryOverTheUnchangedBundleReusesTheStoredCopy() async throws {
        try await withStore { apps, outbox, _ in
            let app = try makeApp(in: apps)
            let first = try await save(app)
            let storedMarker = first.bundlePath.appendingPathComponent("Contents/marker.txt")
            let firstInode = inode(storedMarker)

            let second = try await save(app)
            #expect(second.savedAt == first.savedAt)
            #expect(second.fingerprint == first.fingerprint)
            #expect(second.bundlePath == first.bundlePath)
            #expect(inode(storedMarker) == firstInode)
            // Nothing staged and left behind either.
            let hidden = try FileManager.default.contentsOfDirectory(atPath: outbox.path)
                .filter { $0.hasPrefix(".staging") }
            #expect(hidden.isEmpty)

            // The update lands; the reused copy rolls it back.
            try FileManager.default.removeItem(at: app)
            _ = try makeApp(in: apps, marker: "v2")
            #expect(marker(of: app) == "v2")
            try await BackupStore.restore(forKey: "foo", over: app)
            #expect(marker(of: app) == "v1")
        }
    }

    /// A rollback point is reused under the same rule, in its own store.
    @Test func aRetriedRollbackPointIsReusedToo() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let first = try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: "foo", version: "1.0", buildVersion: "100",
                bundleID: "com.example.reuse")
            let second = try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: "foo", version: "1.0", buildVersion: "100",
                bundleID: "com.example.reuse")
            #expect(second.savedAt == first.savedAt)
            #expect(second.purpose == .installRollbackPoint)
            // And it is not taken for the user's backup, which has none.
            let user = try await save(app)
            #expect(user.purpose == .userBackup)
            #expect(user.savedAt != first.savedAt)
        }
    }

    /// After the transfer has moved the copy to the backup disk the outbox is
    /// empty, and the disk's copy is the one reused: nothing is written to the
    /// outbox, so nothing is owed to the disk a second time.
    @Test func aCopyAlreadyOnTheDiskIsReusedWithoutAnotherTransfer() async throws {
        try await withStore(disk: true) { apps, outbox, _ in
            let app = try makeApp(in: apps)
            let first = try await save(app)
            #expect(BackupStore.pendingTransferKeys() == ["foo"])
            _ = try await BackupStore.transferToDestination(forKey: "foo")
            #expect(!FileManager.default.fileExists(
                atPath: outbox.appendingPathComponent("foo").path))

            let second = try await save(app)
            #expect(second.location == .destination)
            #expect(second.savedAt == first.savedAt)
            #expect(!FileManager.default.fileExists(
                atPath: outbox.appendingPathComponent("foo").path))
            #expect(BackupStore.pendingTransferKeys().isEmpty)

            try FileManager.default.removeItem(at: app)
            _ = try makeApp(in: apps, marker: "v2")
            try await BackupStore.restore(forKey: "foo", over: app)
            #expect(marker(of: app) == "v1")
        }
    }

    /// Reusing is still an answer to a cancelled install: it stops it.
    @Test func aCancelledRetryStillStops() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            _ = try await save(app)
            let retry = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await save(app)
            }
            await #expect(throws: CancellationError.self) { try await retry.value }
        }
    }

    // MARK: - Copied again

    /// A same-size rewrite with the old modification time put back: size,
    /// inode and mtime all match, and the copy is still made again.
    @Test func aRewrittenFileIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let first = try await save(app)
            try rewriteKeepingMTime(app.appendingPathComponent("Contents/marker.txt"), with: "v9")

            let second = try await save(app)
            #expect(second.savedAt != first.savedAt)
            #expect(second.fingerprint != first.fingerprint)
            #expect(marker(of: second.bundlePath) == "v9")
        }
    }

    @Test func anAddedFileIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let first = try await save(app)
            try Data("x".utf8).write(to: app.appendingPathComponent("Contents/new.txt"))
            let second = try await save(app)
            #expect(second.savedAt != first.savedAt)
        }
    }

    @Test func aRetargetedSymlinkIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let first = try await save(app)
            let link = app.appendingPathComponent("Contents/Frameworks/Current")
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(
                atPath: link.path, withDestinationPath: "B")
            let second = try await save(app)
            #expect(second.savedAt != first.savedAt)
        }
    }

    /// Same bytes, new label: the sidecar is what every surface reads the
    /// version from, so a copy recorded under the old one is not reused.
    @Test func aDifferentVersionOrBuildIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let first = try await save(app)
            let bumped = try await save(app, version: "1.1")
            #expect(bumped.savedAt != first.savedAt)
            #expect(bumped.version == "1.1")
            let rebuilt = try await save(app, version: "1.1", build: "101")
            #expect(rebuilt.savedAt != bumped.savedAt)
            #expect(rebuilt.buildVersion == "101")
        }
    }

    /// The default window: a walk within it of the last write cannot vouch
    /// for the tree, and so records nothing a retry could match. Walk times
    /// are given rather than read, so a loaded machine cannot move the answer.
    @Test func aBundleWrittenWithinTheWindowIsNotVouchedFor() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            var st = stat()
            lstat(app.appendingPathComponent("Contents/marker.txt").path, &st)
            let written = Date(timeIntervalSince1970: TimeInterval(st.st_ctimespec.tv_sec)
                + TimeInterval(st.st_ctimespec.tv_nsec) / 1e9)
            BundleStatIdentity.$racyWindowOverride.withValue(nil) {
                #expect(BundleStatIdentity.compute(
                    for: app, now: written.addingTimeInterval(BundleStatIdentity.racyWindow - 0.5))
                        == nil)
                #expect(BundleStatIdentity.compute(
                    for: app, now: written.addingTimeInterval(BundleStatIdentity.racyWindow + 1))
                        != nil)
            }
        }
    }
}
