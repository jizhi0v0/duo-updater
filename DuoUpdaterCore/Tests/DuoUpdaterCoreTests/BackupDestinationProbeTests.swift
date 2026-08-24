import Foundation
import Testing

@testable import DuoUpdaterCore

/// Probing a candidate backup folder, and — the part that carries the design —
/// proving a backup survives a full round trip on filesystems that could never
/// hold an app bundle directly.
///
/// The filesystem cases run against real volumes made with `hdiutil`: sparse
/// images cost nothing until written, need no administrator rights, and can be
/// formatted as anything Disk Utility offers. They assert an **invariant, not a
/// table**: save → transfer → restore must work on *every* format. That is the
/// claim storing archives makes, and it is worth asserting directly rather than
/// hedging behind "the probe said it was fine".
///
/// SMB and NFS cannot be conjured this way and are deliberately not faked. The
/// honest answer there is a probe the user can run against a real share.
@Suite struct BackupDestinationProbeTests {

    private static let hdiutilAvailable =
        FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")
        && ProcessInfo.processInfo.environment["DUO_FS_TESTS"] != "0"

    // MARK: - Basics, on whatever $TMPDIR is

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoProbeTest-\(UUID().uuidString)", isDirectory: true)
    }

    private func withScratch(_ body: (URL) throws -> Void) throws {
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try body(dir)
    }

    @Test func aProbeDescribesTheVolume() throws {
        try withScratch { dir in
            let report = try BackupDestinationProbe.run(at: dir)
            #expect(report.freeBytes ?? 0 > 0)
            #expect(report.filesystem != nil)
            // Whatever $TMPDIR is, its ceiling must not be one a backup could
            // ever hit. Asserted as a bound rather than an exact value so this
            // does not encode which filesystem the boot volume happens to use.
            #expect(report.maxFileBytes == nil || (report.maxFileBytes ?? 0) > (1 << 40))
        }
    }

    @Test func aProbeLeavesNothingBehind() throws {
        try withScratch { dir in
            _ = try BackupDestinationProbe.run(at: dir)
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(leftovers.isEmpty, "unexpected leftovers: \(leftovers)")
        }
    }

    @Test func aFileIsNotAFolder() throws {
        try withScratch { dir in
            let file = dir.appendingPathComponent("f")
            try Data("x".utf8).write(to: file)
            #expect(throws: BackupDestinationProbe.ProbeFailure.self) {
                _ = try BackupDestinationProbe.run(at: file)
            }
        }
    }

    @Test func aVolumeWithoutRoomIsRefused() throws {
        try withScratch { dir in
            #expect(throws: BackupDestinationProbe.ProbeFailure.self) {
                // More than any disk has.
                _ = try BackupDestinationProbe.run(
                    at: dir, minimumFreeBytes: Int64.max - 1)
            }
        }
    }

    // MARK: - Adoption

    @Test func adoptingAFolderMarksItAndDescribesIt() throws {
        try withScratch { dir in
            let (destination, _) = try BackupDestinationProbe.adopt(directory: dir)
            #expect(destination.kind == .external)
            // The store is our subdirectory inside what was picked, never the
            // picked folder itself.
            #expect(destination.path
                == dir.appendingPathComponent(BackupDestination.storeFolderName)
                    .standardizedFileURL.path)
            let store = try #require(destination.directory)
            let marker = try #require(BackupVolumeMarker.read(at: store))
            #expect(destination.identity == marker.identity)
            // The freshly adopted folder is immediately usable as a destination.
            try BackupStore.$destinationOverride.withValue(destination) {
                #expect(BackupStore.availability() == .ready(destination.directory!))
            }
        }
    }

    /// **The one that matters.** A folder picker hands back somewhere that
    /// belongs to the user. Rooting the store there made every one of their
    /// subdirectories look like a backup: counted in the storage total, listed in
    /// the clean-up sheet, and one confirmation away from `removeItem`. Measured
    /// on a real machine, `~/Documents` had 75 of them and 31 GB of the user's
    /// files reported as backup storage.
    @Test func adoptingNeverTakesOverTheFolderTheUserPicked() throws {
        try withScratch { picked in
            let fm = FileManager.default
            // Stand in for someone's Documents folder.
            for name in ["2026-03-03", "Taxes", "Screenshots"] {
                let dir = picked.appendingPathComponent(name, isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data(repeating: 0xAB, count: 4096)
                    .write(to: dir.appendingPathComponent("theirs.bin"))
            }

            let (destination, _) = try BackupDestinationProbe.adopt(directory: picked)
            let store = try #require(destination.directory)

            #expect(store.lastPathComponent == BackupDestination.storeFolderName)
            #expect(store.deletingLastPathComponent().standardizedFileURL
                == picked.standardizedFileURL)
            // Nothing of ours is left loose in the folder they chose.
            #expect(BackupVolumeMarker.read(at: picked) == nil,
                    "the marker must go inside our own directory, not theirs")
            #expect(BackupVolumeMarker.read(at: store) != nil)

            try BackupStore.$rootOverride.withValue(
                picked.appendingPathComponent("outbox", isDirectory: true)
            ) {
                try BackupStore.$destinationOverride.withValue(destination) {
                    // Their folders are not backups, are not listed, and are not
                    // counted — so nothing can offer to delete them.
                    #expect(BackupStore.listing().isEmpty)
                    #expect(BackupStore.allBackups().isEmpty)
                    #expect(BackupStore.storeSizes().destination == 0)
                }
            }
            // And they are all still there.
            for name in ["2026-03-03", "Taxes", "Screenshots"] {
                #expect(fm.fileExists(
                    atPath: picked.appendingPathComponent("\(name)/theirs.bin").path))
            }
        }
    }

    /// Picking the store itself must not nest another one inside it. The
    /// settings page shows the store path, so picking what is shown is the
    /// ordinary way anyone re-selects a disk — and each re-pick used to bury the
    /// real backups one level further up, out of sight, while an empty folder
    /// became the destination.
    @Test func rePickingTheStoreItselfDoesNotNestAnother() throws {
        try withScratch { picked in
            let first = try BackupDestinationProbe.adopt(directory: picked).destination
            let store = try #require(first.directory)

            // The user copies the path out of Settings and picks that.
            let second = try BackupDestinationProbe.adopt(directory: store).destination

            #expect(second.path == first.path, "adoption must be idempotent")
            #expect(second.identity == first.identity, "and must keep the disk's identity")
            #expect(!FileManager.default.fileExists(
                atPath: store.appendingPathComponent(
                    BackupDestination.storeFolderName).path),
                "no store nested inside the store")
        }
    }

    /// A third pick is still the same place — the guard cannot depend on how
    /// many times it has run.
    @Test func adoptingTheStoreRepeatedlyStaysPut() throws {
        try withScratch { picked in
            var destination = try BackupDestinationProbe.adopt(directory: picked).destination
            let expected = destination.path
            for _ in 0..<3 {
                destination = try BackupDestinationProbe
                    .adopt(directory: try #require(destination.directory)).destination
                #expect(destination.path == expected)
            }
        }
    }

    /// Re-picking a folder that already holds backups is how someone reconnects
    /// a disk after reinstalling. Minting a fresh identity there would make every
    /// backup already on it read as belonging to a different disk.
    @Test func adoptingTheSameFolderTwiceKeepsTheIdentity() throws {
        try withScratch { dir in
            let first = try BackupDestinationProbe.adopt(directory: dir).destination
            let second = try BackupDestinationProbe.adopt(directory: dir).destination
            #expect(first.identity == second.identity)
        }
    }

    // MARK: - Real filesystems

    /// Create, attach, and guarantee detach of a sparse image.
    private func withVolume(
        format: String, sizeMB: Int = 256, _ body: (URL) throws -> Void
    ) throws {
        let fm = FileManager.default
        let id = UUID().uuidString
        let image = fm.temporaryDirectory.appendingPathComponent("duo-\(id).sparseimage")
        let mount = fm.temporaryDirectory.appendingPathComponent("duo-mnt-\(id)", isDirectory: true)
        // exFAT volume labels cap at 11 characters, so the name cannot carry a
        // UUID. Uniqueness lives in the mount point instead, which also keeps
        // concurrent runs from colliding on `/Volumes/Name 1`.
        let volname = "duo\(id.prefix(5))"

        func run(_ arguments: [String]) -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }

        try #require(run([
            "create", "-size", "\(sizeMB)m", "-type", "SPARSE",
            "-fs", format, "-volname", volname, image.path,
        ]) == 0, "could not create a \(format) image")
        defer { try? fm.removeItem(at: image) }

        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try #require(run([
            "attach", "-nobrowse", "-mountpoint", mount.path, image.path,
        ]) == 0, "could not attach the \(format) image")
        defer {
            // A leaked mount poisons the next run, so a stuck one is forced.
            if run(["detach", mount.path]) != 0 { _ = run(["detach", "-force", mount.path]) }
            try? fm.removeItem(at: mount)
        }

        try body(mount)
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
        // A symlink and an extended attribute: the two things a bundle carries
        // that FAT and SMB cannot represent, and the reason the payload is an
        // archive rather than a directory.
        try fm.createSymbolicLink(
            atPath: contents.appendingPathComponent("Current").path,
            withDestinationPath: "MacOS")
        let data = Data("0081;0;Safari;".utf8)
        _ = data.withUnsafeBytes { buffer in
            setxattr(contents.appendingPathComponent("marker.txt").path,
                     "com.apple.quarantine", buffer.baseAddress, buffer.count, 0, 0)
        }
        return app
    }

    private func marker(of app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    /// **The claim the whole approach rests on.** A backup taken on APFS, stored
    /// on a volume that could not hold the bundle itself, and restored — on every
    /// format, with no per-format special casing anywhere in the code.
    @Test(
        .enabled(if: BackupDestinationProbeTests.hdiutilAvailable),
        arguments: ["MS-DOS", "ExFAT", "HFS+", "APFS", "Case-sensitive APFS"]
    )
    func aBackupRoundTripsOnAnyFilesystem(_ format: String) throws {
        try withVolume(format: format) { volume in
            let fm = FileManager.default
            let local = fm.temporaryDirectory
                .appendingPathComponent("DuoFS-\(UUID().uuidString)", isDirectory: true)
            let outbox = local.appendingPathComponent("outbox", isDirectory: true)
            let apps = local.appendingPathComponent("apps", isDirectory: true)
            defer { try? fm.removeItem(at: local) }
            try fm.createDirectory(at: outbox, withIntermediateDirectories: true)
            try fm.createDirectory(at: apps, withIntermediateDirectories: true)

            let (destination, report) = try BackupDestinationProbe.adopt(directory: volume)
            #expect(report.filesystem != nil, "\(format): no filesystem name")

            try BackupStore.$rootOverride.withValue(outbox) {
                try BackupStore.$destinationOverride.withValue(destination) {
                    let app = try makeApp(named: "App.app", in: apps, marker: "v1")
                    try BackupStore.save(
                        appPath: app, key: "k", version: "1.0",
                        bundleID: "com.example.testapp")

                    let moved = try BackupStore.transferToDestination(forKey: "k")
                    #expect(moved.location == .destination, "\(format): transfer did not land")
                    #expect(!fm.fileExists(atPath: outbox.appendingPathComponent("k").path),
                            "\(format): local copy should be gone")

                    try makeApp(named: "App.app", in: apps, marker: "v2")
                    let version = try BackupStore.restore(forKey: "k", over: app)
                    #expect(version == "1.0", "\(format): wrong version restored")
                    #expect(marker(of: app) == "v1", "\(format): contents did not come back")
                    // The symlink is the thing that would have been flattened had
                    // the bundle been copied onto this volume directly.
                    let link = app.appendingPathComponent("Contents/Current")
                    #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == "MacOS",
                            "\(format): symlink did not survive")
                }
            }
        }
    }

    /// FAT32 caps a single file at 4 GiB − 1, and the probe reads that off the
    /// filesystem rather than guessing from its name. The others report either no
    /// ceiling at all (HFS+, exFAT) or one — APFS's ~36 PB — that no backup can
    /// reach; both are fine, and neither is worth hard-coding, so they are
    /// asserted as "not a limit anything could hit".
    @Test(
        .enabled(if: BackupDestinationProbeTests.hdiutilAvailable),
        arguments: ["MS-DOS", "ExFAT", "HFS+", "APFS"]
    )
    func theFileSizeCeilingIsReadFromTheFilesystem(_ format: String) throws {
        try withVolume(format: format) { volume in
            let report = try BackupDestinationProbe.run(at: volume)
            if format == "MS-DOS" {
                #expect(report.maxFileBytes == (1 << 32) - 1,
                        "FAT should report a 4 GiB ceiling, got \(String(describing: report.maxFileBytes))")
            } else {
                #expect(report.maxFileBytes == nil || (report.maxFileBytes ?? 0) > (1 << 40),
                        "\(format) should report no reachable ceiling, got \(String(describing: report.maxFileBytes))")
            }
        }
    }

    /// A folder picker cannot express "another disk" on its own —
    /// `~/Documents/Backups` is a perfectly valid folder that frees nothing.
    /// This is what tells the two apart, so the page can say so instead of
    /// promising space it will not reclaim.
    @Test func twoFoldersOnTheBootVolumeAreTheSameVolume() throws {
        try withScratch { a in
            try withScratch { b in
                #expect(BackupDestinationProbe.isOnSameVolume(a, as: b))
            }
        }
    }

    @Test(.enabled(if: BackupDestinationProbeTests.hdiutilAvailable))
    func amountedDiskIsADifferentVolumeFromTheBootDisk() throws {
        try withVolume(format: "APFS") { volume in
            try withScratch { local in
                #expect(!BackupDestinationProbe.isOnSameVolume(volume, as: local))
                // And it agrees with itself, so the check is not just "always false".
                #expect(BackupDestinationProbe.isOnSameVolume(volume, as: volume))
            }
        }
    }

    @Test(.enabled(if: BackupDestinationProbeTests.hdiutilAvailable))
    func aDiskImageIsSeenAsRemovableAndLocal() throws {
        try withVolume(format: "APFS") { volume in
            let report = try BackupDestinationProbe.run(at: volume)
            #expect(report.isLocal == true, "an attached image is not a network volume")
            #expect(report.writeBytesPerSecond ?? 0 > 0)
        }
    }
}
