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
        format: String, sizeMB: Int = 256, _ body: (URL) async throws -> Void
    ) async throws {
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

        try await body(mount)
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
    func aBackupRoundTripsOnAnyFilesystem(_ format: String) async throws {
        try await withVolume(format: format) { volume in
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

            try await BackupStore.$rootOverride.withValue(outbox) {
                try await BackupStore.$destinationOverride.withValue(destination) {
                    let app = try makeApp(named: "App.app", in: apps, marker: "v1")
                    try await BackupStore.save(
                        appPath: app, key: "k", version: "1.0",
                        bundleID: "com.example.testapp")

                    let moved = try await BackupStore.transferToDestination(forKey: "k")
                    #expect(moved.location == .destination, "\(format): transfer did not land")
                    #expect(!fm.fileExists(atPath: outbox.appendingPathComponent("k").path),
                            "\(format): local copy should be gone")

                    try makeApp(named: "App.app", in: apps, marker: "v2")
                    let version = try await BackupStore.restore(forKey: "k", over: app)
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
    func theFileSizeCeilingIsReadFromTheFilesystem(_ format: String) async throws {
        try await withVolume(format: format) { volume in
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
    func amountedDiskIsADifferentVolumeFromTheBootDisk() async throws {
        try await withVolume(format: "APFS") { volume in
            try withScratch { local in
                #expect(!BackupDestinationProbe.isOnSameVolume(volume, as: local))
                // And it agrees with itself, so the check is not just "always false".
                #expect(BackupDestinationProbe.isOnSameVolume(volume, as: volume))
            }
        }
    }

    @Test(.enabled(if: BackupDestinationProbeTests.hdiutilAvailable))
    func aDiskImageIsSeenAsRemovableAndLocal() async throws {
        try await withVolume(format: "APFS") { volume in
            let report = try BackupDestinationProbe.run(at: volume)
            #expect(report.isLocal == true, "an attached image is not a network volume")
            #expect(report.writeBytesPerSecond ?? 0 > 0)
        }
    }

    // MARK: - Which free-space figure to believe

    /// The case that sent this looking: an external APFS disk with 360 GB free
    /// reports zero for important usage. Answering zero there draws the disk as
    /// full and, with any floor above zero, refuses it as too small.
    ///
    /// Mutation: `if let important, important > 0` → `if let important`.
    @Test func aVolumeThatWillNotNameItsImportantSpaceFallsBackToTheRawFigure() {
        #expect(BackupDestinationProbe.preferredFree(important: 0, plain: 359_929_303_040)
            == 359_929_303_040)
    }

    /// The boot volume, where the important figure is the *larger* one because it
    /// counts what macOS would purge. Preferring the raw figure would report 12 GB
    /// less than Finder does and refuse writes that succeed.
    ///
    /// Mutation: return `plain ?? important` unconditionally.
    @Test func theImportantFigureWinsWhenItIsOfferedAtAll() {
        #expect(BackupDestinationProbe.preferredFree(
            important: 52_396_931_094, plain: 39_707_287_552) == 52_396_931_094)
    }

    /// A full disk answers zero to both, and zero is then the true answer — the
    /// fallback must not turn "no room" into "would not say".
    @Test func aFullDiskStillReportsNothingFree() {
        #expect(BackupDestinationProbe.preferredFree(important: 0, plain: 0) == 0)
        #expect(BackupDestinationProbe.preferredFree(important: 0, plain: nil) == 0)
    }

    /// Nothing known stays nothing known: a disk that is not plugged in must read
    /// as "no figure", which is what callers draw as blank rather than as empty.
    @Test func aVolumeThatCannotBeAskedHasNoFigure() {
        #expect(BackupDestinationProbe.preferredFree(important: nil, plain: nil) == nil)
        #expect(BackupDestinationProbe.preferredFree(important: nil, plain: 42) == 42)
    }

    /// And through the real API, on the volume this test is running from. Not a
    /// number this can assert — it is whatever the machine has — but it pins that
    /// the boot volume answers at all, which is the one volume every machine
    /// running this has.
    ///
    /// The two readings are deliberately **not** compared for equality. They were
    /// at first, and it failed by 11 MB: free space moves between two live reads
    /// while the rest of the suite is writing temporary directories.
    @Test func theBootVolumeReportsSomeFreeSpace() throws {
        let scratch = FileManager.default.temporaryDirectory
        #expect(try #require(BackupDestinationProbe.freeBytes(at: scratch)) > 0)
        let space = try #require(BackupDestinationProbe.volumeSpace(at: scratch))
        #expect(space.free > 0)
        #expect(space.total > space.free)
    }

    // MARK: - Time Machine volumes

    /// A disk `backupd` owns is refused before anything is written to it, and the
    /// refusal names the remedy Apple gives: a second APFS volume on the same
    /// disk. The marker check runs against a directory of this test's own, since
    /// no test can make a Time Machine volume.
    ///
    /// Mutation: drop either name from `timeMachineMarkers`.
    @Test func aTimeMachineDiskIsRecognisedByWhatBackupdLeavesOnIt() throws {
        for marker in [
            "com.apple.timemachine.private.structure.metadata",
            "com.apple.backupd.HostUUID",
        ] {
            try withScratch { dir in
                #expect(!BackupDestinationProbe.carriesTimeMachineMarkers(at: dir))
                let value = Data("x".utf8)
                let set = value.withUnsafeBytes {
                    setxattr(dir.path, marker, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW)
                }
                try #require(set == 0, "could not set \(marker)")
                #expect(BackupDestinationProbe.carriesTimeMachineMarkers(at: dir))
            }
        }
    }

    /// An ordinary folder carries none of them, which is what keeps every other
    /// disk out of this branch.
    @Test func anOrdinaryFolderIsNotATimeMachineVolume() throws {
        try withScratch { dir in
            #expect(!BackupDestinationProbe.carriesTimeMachineMarkers(at: dir))
            #expect(BackupDestinationProbe.timeMachineVolumeName(holding: dir) == nil)
        }
    }

    /// The wording is load-bearing: "can't be written to" sends someone looking at
    /// permissions, which are not the problem — the disk this came from is
    /// `drwxrwxr-x` and owned by the user.
    @Test func theRefusalSaysWhatToDoAboutIt() {
        let message = BackupDestinationProbe.ProbeFailure
            .reservedForTimeMachine("Samsung T7").errorDescription ?? ""
        #expect(message.contains("Samsung T7"))
        #expect(message.contains("Time Machine"))
        #expect(message.contains("Disk Utility"))
    }

    // MARK: - May a file be created here at all

    /// The question the picker asks of every disk someone has plugged in. It has
    /// to be asked by writing: the two volumes that prompted it both say yes
    /// through their permission bits and then refuse every write.
    ///
    /// Mutation: `return true` from `canWrite`.
    @Test func aFolderThatRefusesWritesIsNotWritable() throws {
        try withScratch { dir in
            #expect(BackupDestinationProbe.canWrite(at: dir))
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500], ofItemAtPath: dir.path)
            defer { try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: dir.path) }
            #expect(!BackupDestinationProbe.canWrite(at: dir))
        }
    }

    /// And it leaves nothing behind on a disk the user has merely attached.
    ///
    /// Mutation: drop the `removeItem` in `canWrite`.
    @Test func askingWhetherAFolderTakesFilesLeavesNoneInIt() throws {
        try withScratch { dir in
            #expect(BackupDestinationProbe.canWrite(at: dir))
            let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(left.isEmpty, "left behind: \(left)")
        }
    }

    /// A reserved disk is refused without being touched. The one thing not to do
    /// to somebody's Time Machine disk is write to it to find out.
    ///
    /// The fixture is writable — the assertion above it says so — so the refusal
    /// can only come from that branch, and the empty directory afterwards is the
    /// "without being touched" half.
    ///
    /// Mutation: drop the `if reserved` line.
    @Test func aReservedFolderIsRefusedWithoutBeingWrittenTo() throws {
        try withScratch { dir in
            #expect(BackupDestinationProbe.canWrite(at: dir, reserved: false),
                    "fixture must be writable for this to prove anything")
            #expect(!BackupDestinationProbe.canWrite(at: dir, reserved: true))
            let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(left.isEmpty, "left behind: \(left)")
        }
    }
}
