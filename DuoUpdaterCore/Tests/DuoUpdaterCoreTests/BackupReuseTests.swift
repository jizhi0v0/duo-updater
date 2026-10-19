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

    /// The inode of the stored copy's marker (or of the archive, on the
    /// disk). Unchanged means nothing was copied; a new copy is new files.
    private func storedInode(_ backup: BackupStore.Backup) -> ino_t {
        backup.location == .destination
            ? inode(backup.bundlePath)
            : inode(backup.bundlePath.appendingPathComponent("Contents/marker.txt"))
    }

    // MARK: - Reuse

    /// The cancel-then-retry case: the second attempt finds its own earlier
    /// copy and stores nothing new — same files, re-dated to now — and that
    /// copy still restores through every gate.
    @Test func aRetryOverTheUnchangedBundleReusesTheStoredCopy() async throws {
        try await withStore { apps, outbox, _ in
            let app = try makeApp(in: apps)
            let first = try await save(app)
            let firstInode = storedInode(first)

            let second = try await save(app)
            #expect(storedInode(second) == firstInode)
            #expect(second.fingerprint == first.fingerprint)
            #expect(second.bundlePath == first.bundlePath)
            // Re-dated, so the low-space prune does not take it for old.
            #expect(second.savedAt > first.savedAt)
            #expect(BackupStore.backup(forKey: "foo")?.savedAt == second.savedAt)
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
            let firstInode = storedInode(first)
            let second = try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: "foo", version: "1.0", buildVersion: "100",
                bundleID: "com.example.reuse")
            #expect(storedInode(second) == firstInode)
            #expect(second.purpose == .installRollbackPoint)
            // And it is not taken for the user's backup, which has none.
            let user = try await save(app)
            #expect(user.purpose == .userBackup)
            #expect(storedInode(user) != firstInode)
            #expect(storedInode(try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: "foo", version: "1.0", buildVersion: "100",
                bundleID: "com.example.reuse")) == firstInode)
        }
    }

    /// After the transfer has moved the copy to the backup disk the outbox is
    /// empty, and the disk's copy is the one reused: nothing is written to the
    /// outbox, so nothing is owed to the disk a second time.
    @Test func aCopyAlreadyOnTheDiskIsReusedWithoutAnotherTransfer() async throws {
        try await withStore(disk: true) { apps, outbox, _ in
            let app = try makeApp(in: apps)
            _ = try await save(app)
            #expect(BackupStore.pendingTransferKeys() == ["foo"])
            let moved = try await BackupStore.transferToDestination(forKey: "foo")
            let movedInode = storedInode(moved)
            #expect(!FileManager.default.fileExists(
                atPath: outbox.appendingPathComponent("foo").path))

            let second = try await save(app)
            #expect(second.location == .destination)
            #expect(storedInode(second) == movedInode)
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
            let firstInode = storedInode(first)
            try rewriteKeepingMTime(app.appendingPathComponent("Contents/marker.txt"), with: "v9")

            let second = try await save(app)
            #expect(storedInode(second) != firstInode)
            #expect(second.fingerprint != first.fingerprint)
            #expect(marker(of: second.bundlePath) == "v9")
        }
    }

    @Test func anAddedFileIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let firstInode = storedInode(try await save(app))
            try Data("x".utf8).write(to: app.appendingPathComponent("Contents/new.txt"))
            let second = try await save(app)
            #expect(storedInode(second) != firstInode)
        }
    }

    @Test func aRetargetedSymlinkIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let firstInode = storedInode(try await save(app))
            let link = app.appendingPathComponent("Contents/Frameworks/Current")
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(
                atPath: link.path, withDestinationPath: "B")
            let second = try await save(app)
            #expect(storedInode(second) != firstInode)
        }
    }

    /// Same bytes, new label: the sidecar is what every surface reads the
    /// version from, so a copy recorded under the old one is not reused.
    @Test func aDifferentVersionOrBuildIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let firstInode = storedInode(try await save(app))
            let bumped = try await save(app, version: "1.1")
            let bumpedInode = storedInode(bumped)
            #expect(bumpedInode != firstInode)
            #expect(bumped.version == "1.1")
            let rebuilt = try await save(app, version: "1.1", build: "101")
            #expect(storedInode(rebuilt) != bumpedInode)
            #expect(rebuilt.buildVersion == "101")
        }
    }

    /// The stored copy was changed after it was made (the backed-up app run
    /// from the store, a cleaning tool). A retry used to replace it with a
    /// fresh copy; it still does, rather than keep the damage.
    @Test func aStoredCopyAlteredSinceIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let first = try await save(app)
            let firstInode = storedInode(first)
            try rewriteKeepingMTime(
                first.bundlePath.appendingPathComponent("Contents/marker.txt"), with: "zz")
            let second = try await save(app)
            #expect(storedInode(second) != firstInode)
            #expect(marker(of: second.bundlePath) == "v1")
        }
    }

    /// The same for the archive on the disk, which is checked by its size —
    /// its digest is the restore's to check.
    @Test func aResizedArchiveOnTheDiskIsCopiedAgain() async throws {
        try await withStore(disk: true) { apps, outbox, _ in
            let app = try makeApp(in: apps)
            _ = try await save(app)
            let moved = try await BackupStore.transferToDestination(forKey: "foo")
            let handle = try FileHandle(forWritingTo: moved.bundlePath)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0]))
            try handle.close()

            let second = try await save(app)
            #expect(second.location == .outbox)
            #expect(FileManager.default.fileExists(
                atPath: outbox.appendingPathComponent("foo").path))
        }
    }

    /// An outbox copy that does not match is never passed over for a matching
    /// one on the disk: the outbox copy is the newer generation, and reusing
    /// the disk's would leave it to replace the reuse on the next transfer.
    @Test func aNonMatchingOutboxCopyIsNotPassedOverForTheDisk() async throws {
        try await withStore(disk: true) { apps, _, _ in
            let app = try makeApp(in: apps)
            _ = try await save(app)
            let moved = try await BackupStore.transferToDestination(forKey: "foo")
            let movedInode = storedInode(moved)
            // A different label lands in the outbox; the disk keeps "1.0".
            let other = try await save(app, version: "1.1")
            let otherInode = storedInode(other)

            let again = try await save(app)
            #expect(again.location == .outbox)
            #expect(again.version == "1.0")
            #expect(storedInode(again) != otherInode)
            // The disk's generation is left as it was.
            #expect(inode(moved.bundlePath) == movedInode)
        }
    }

    /// Anything running from the bundle could be changing it through a shared
    /// mapping that moves no timestamp, so a running app is copied again.
    @Test func aRunningAppIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let app = try makeApp(in: apps)
            let firstInode = storedInode(try await save(app))
            let second = try await BackupStore.$runningOverride.withValue({ _ in true }) {
                try await save(app)
            }
            #expect(storedInode(second) != firstInode)
            // And once it has quit, the copy it left is reused.
            let thirdInode = storedInode(second)
            #expect(storedInode(try await save(app)) == thirdInode)
        }
    }

    /// What a process could have been started from: executables and
    /// symlinks, by file name, anywhere in the bundle.
    @Test func executableNamesAreWhatAProcessCouldBeNamedFor() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoExecNames-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let app = try makeApp(in: base)
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let main = macOS.appendingPathComponent("service")
        try Data("x".utf8).write(to: main)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: main.path)
        try FileManager.default.createSymbolicLink(
            atPath: macOS.appendingPathComponent("alias").path, withDestinationPath: "service")
        let names = Set(BackupStore.executableNames(in: app))
        #expect(names.contains("service"))
        #expect(names.contains("alias"))
        #expect(!names.contains("marker.txt"))
        #expect(!names.contains("Info.plist"))

        // A process the kernel cannot place (its bundle replaced under it, as
        // RustDesk's root `service` was) counts when its name is one of these.
        let unplaced = { (names: [String]) in
            BackupStore.mayHaveProcesses(
                insideBundle: app, hasProcesses: { _ in false },
                unplacedNames: { names.map { Array($0.utf8) } })
        }
        #expect(unplaced(["service"]))
        #expect(unplaced(["alias"]))
        #expect(!unplaced(["marker.txt"]))
        #expect(!unplaced([]))
        #expect(BackupStore.mayHaveProcesses(
            insideBundle: app, hasProcesses: { _ in true }, unplacedNames: { [] }))
    }

    @Test func aShortNameMatchesTheExecutableItWasCutFrom() {
        /// The kernel's cut: the first 15 bytes, wherever they end.
        func cut(_ name: String) -> [UInt8] { Array(name.utf8.prefix(15)) }
        // 15 bytes kept: a cut name matches the executable it begins.
        #expect(BackupStore.anyExecutable(["SourceKitService"], isNamed: [cut("SourceKitService")]))
        #expect(BackupStore.anyExecutable(["service", "Foo"], isNamed: [cut("service")]))
        // Cut inside a character: 助手 straddles bytes 13-18, Cyrillic is two
        // bytes a letter. Bytes, not a decoded string, still match.
        #expect(Array("QQ浏览器助手".utf8).count == 17)
        #expect(BackupStore.anyExecutable(["QQ浏览器助手"], isNamed: [cut("QQ浏览器助手")]))
        #expect(BackupStore.anyExecutable(["Приложение"], isNamed: [cut("Приложение")]))
        // Started through another normalization than the file's own: the
        // kernel keeps the bytes of the path it was given.
        let name = "Café-Überwachungsdienst"
        let nfd = name.decomposedStringWithCanonicalMapping
        let nfc = name.precomposedStringWithCanonicalMapping
        #expect(Array(nfd.utf8) != Array(nfc.utf8))
        #expect(BackupStore.anyExecutable([nfd], isNamed: [cut(nfc)]))
        #expect(BackupStore.anyExecutable([nfc], isNamed: [cut(nfd)]))
        #expect(BackupStore.anyExecutable(["Café"].map(\.decomposedStringWithCanonicalMapping),
                                          isNamed: [Array("Café".precomposedStringWithCanonicalMapping.utf8)]))
        // A shorter name is the whole name.
        #expect(!BackupStore.anyExecutable(["service-helper"], isNamed: [cut("service")]))
        #expect(!BackupStore.anyExecutable(["Foo"], isNamed: [cut("Bar")]))
        #expect(!BackupStore.anyExecutable([], isNamed: [cut("Foo")]))
    }

    /// An input method's user-data snapshot is attached to the fresh outbox
    /// generation after the save, so its bundle is always copied.
    @Test func anInputMethodIsCopiedAgain() async throws {
        try await withStore { apps, _, _ in
            let dir = apps.appendingPathComponent("Library/Input Methods", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let app = try makeApp(in: dir)
            #expect(UpdatePolicy.isInputMethod(app))
            let firstInode = storedInode(try await save(app))
            let second = try await save(app)
            #expect(storedInode(second) != firstInode)
        }
    }

    // MARK: - The walk

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

    /// Only APFS keeps the promise the walk relies on; exFAT/FAT let a
    /// rewrite put every time back, HFS+ has `exchangedata`.
    @Test func onlyAPFSIsVouchedFor() {
        #expect(BundleStatIdentity.vouchesFor(fileSystemType: "apfs"))
        for other in ["hfs", "exfat", "msdos", "smbfs", "nfs", "afpfs", ""] {
            #expect(!BundleStatIdentity.vouchesFor(fileSystemType: other))
        }
        #expect(!BundleStatIdentity.vouchesFor(fileSystemType: nil))
        #expect(BundleStatIdentity.fileSystemType(
            of: FileManager.default.temporaryDirectory.path) == "apfs")
    }
}
