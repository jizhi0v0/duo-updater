import Foundation

/// Checks whether a directory the user picked can actually serve as the backup
/// store, at the moment they pick it — rather than at the moment they need a
/// rollback.
///
/// It is much smaller than it would have to be if backups were stored as bundles.
/// The hard question there would be "can this filesystem faithfully hold a `.app`,
/// with its extended attributes, symlinks and permissions?" — a question that has
/// a different answer on exFAT, on SMB, and on whatever a given NAS presents, and
/// one that can only be answered by round-tripping a real bundle. Storing an
/// archive removes it: the destination holds one opaque file, and any filesystem
/// can do that. See ``BundleArchive``.
///
/// What is left is four cheap questions about the volume itself.
public enum BackupDestinationProbe {

    public struct Report: Sendable, Codable, Equatable {
        /// Space available for something the user would mind losing.
        public let freeBytes: Int64?
        /// Largest single file this filesystem can hold, or nil when it declares
        /// no representable ceiling.
        ///
        /// Reported as the factual number rather than filtered through some
        /// notion of "large enough not to matter" — the useful question is
        /// whether *this* archive fits, so the caller compares against the size
        /// it actually has, and there is no threshold here to get wrong. On this
        /// machine: FAT32 4 GiB − 1, APFS ~36 PB, HFS+ and exFAT no ceiling.
        ///
        /// The case that matters is FAT32. A very large app can archive past
        /// 4 GiB, and finding out at transfer time would mean discovering it on
        /// the first update after the disk was set up. Read from
        /// `pathconf(_PC_FILESIZEBITS)` rather than inferred from the
        /// filesystem's name, and without writing anything: a probe that tested
        /// the limit by creating a 4 GiB file would, on FAT, actually allocate
        /// 4 GiB, because FAT has no sparse files.
        public let maxFileBytes: Int64?
        /// Measured throughput, for deciding whether to copy in the background
        /// and for telling the user roughly how long an update will take to
        /// stow. Nil when the sample was too quick to time meaningfully — which
        /// is itself the answer "fast enough not to care".
        public let writeBytesPerSecond: Double?
        /// `statfs`'s `f_fstypename`. Descriptive only — nothing here gates on
        /// it, because the archive format is what settles which filesystems can
        /// hold a backup.
        public let filesystem: String?
        public let isRemovable: Bool?
        /// False for a network volume. Worth surfacing because it changes the
        /// character of the failures the user should expect: a share drops
        /// mid-copy far more often than a cable falls out.
        public let isLocal: Bool?
        public let probedAt: Date
    }

    public enum ProbeFailure: LocalizedError {
        case notADirectory(String)
        case notWritable(String)
        case tooSmall(needBytes: Int64, freeBytes: Int64)

        public var errorDescription: String? {
            switch self {
            case .notADirectory(let path):
                return "“\(path)” isn’t a folder."
            case .notWritable(let path):
                return "“\(path)” can’t be written to."
            case .tooSmall(let need, let free):
                let f = ByteCountFormatter()
                f.countStyle = .file
                return "Not enough room: \(f.string(fromByteCount: free)) available, "
                    + "\(f.string(fromByteCount: need)) needed."
            }
        }
    }

    /// Bytes written to measure throughput. Big enough to time a slow share
    /// honestly, small enough that picking a folder does not feel like a task.
    private static let sampleBytes = 4 << 20

    public static func run(at directory: URL, minimumFreeBytes: Int64 = 0) throws -> Report {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProbeFailure.notADirectory(directory.path)
        }

        let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsRemovableKey, .volumeIsLocalKey,
        ])
        // Already `Int64?`; the outer optional is `resourceValues` having failed.
        let free = values?.volumeAvailableCapacityForImportantUsage ?? nil
        if minimumFreeBytes > 0, let free, free < minimumFreeBytes {
            throw ProbeFailure.tooSmall(needBytes: minimumFreeBytes, freeBytes: free)
        }

        // Writability is established by writing, not by asking. `isWritableFile`
        // answers from the permission bits, which say nothing about a read-only
        // mount or a share whose credentials have lapsed.
        let speed = try measureWrite(in: directory)

        return Report(
            freeBytes: free,
            maxFileBytes: maxFileSize(at: directory),
            writeBytesPerSecond: speed,
            filesystem: filesystemName(at: directory),
            isRemovable: values?.volumeIsRemovable,
            isLocal: values?.volumeIsLocal,
            probedAt: Date())
    }

    /// Probe a directory and, if it can serve, mark it as ours and return the
    /// destination to persist.
    ///
    /// An existing marker's identity is **kept**, never regenerated. Re-picking
    /// a folder that already holds backups is the ordinary way someone
    /// reconnects a disk after reinstalling, and minting a fresh identity there
    /// would make every backup already on it read as belonging to a different
    /// disk.
    public static func adopt(
        directory: URL, minimumFreeBytes: Int64 = 0
    ) throws -> (destination: BackupDestination, report: Report) {
        let report = try run(at: directory, minimumFreeBytes: minimumFreeBytes)

        // Our own subdirectory, never the folder the user handed us. See
        // `BackupDestination.storeFolderName` for what rooting the store in
        // someone's Documents folder would have cost.
        //
        // Unless they handed us the store itself — which is the ordinary thing
        // to do, because the settings page shows that path and picking what is
        // shown is how anyone re-selects a disk. Adopting must therefore be
        // idempotent: without this, each re-pick nested another
        // `DuoUpdater Backups` inside the last one, and the newly empty folder
        // became the destination while every existing backup sat one level up,
        // invisible.
        let alreadyOurs = BackupVolumeMarker.read(at: directory) != nil
            || directory.lastPathComponent == BackupDestination.storeFolderName
        let store = alreadyOurs
            ? directory
            : directory.appendingPathComponent(
                BackupDestination.storeFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: store, withIntermediateDirectories: true)
        } catch {
            throw ProbeFailure.notWritable(directory.path)
        }

        let existing = BackupVolumeMarker.read(at: store)
        let volumeName = (try? directory.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
        let marker = BackupVolumeMarker(
            identity: existing?.identity ?? UUID().uuidString,
            createdAt: existing?.createdAt ?? Date(),
            volumeName: volumeName,
            volumeUUID: (try? directory.resourceValues(forKeys: [.volumeUUIDStringKey]))?
                .volumeUUIDString,
            filesystem: report.filesystem)
        try marker.write(to: store)

        return (
            BackupDestination(
                kind: .external, path: store.standardizedFileURL.path,
                identity: marker.identity, volumeName: volumeName),
            report
        )
    }

    /// Whether two paths sit on the same mounted volume right now.
    ///
    /// The point of moving the store is to get the bytes off this Mac's disk,
    /// and a folder picker cannot express that on its own — `~/Documents/Backups`
    /// is a perfectly valid folder that defeats the entire purpose. Comparing
    /// volumes is what tells the two apart.
    ///
    /// Compared by mount point rather than by `volumeIdentifierKey`. Both answer
    /// the question, and the identifier is an opaque existential that reads
    /// worse at the call site; neither is suitable to **store**, which is why
    /// ``BackupVolumeMarker`` identifies a disk with a UUID of our own — a mount
    /// token changes when the disk is replugged, so a persisted copy would
    /// report a mismatch every time.
    public static func isOnSameVolume(_ one: URL, as other: URL) -> Bool {
        func mountPoint(_ url: URL) -> URL? {
            (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume
        }
        guard let a = mountPoint(one), let b = mountPoint(other) else { return false }
        return a.standardizedFileURL == b.standardizedFileURL
    }

    // MARK: - Pieces

    /// Writes and deletes a sample, returning bytes per second.
    ///
    /// The payload is random rather than zeroes: a run of zeroes can be stored
    /// as a hole on a filesystem that supports them, which would time the
    /// bookkeeping instead of the disk and report a share as faster than the
    /// cable it runs over.
    private static func measureWrite(in directory: URL) throws -> Double? {
        let file = directory.appendingPathComponent(".duo-write-check-\(UUID().uuidString)")
        var payload = Data(count: sampleBytes)
        payload.withUnsafeMutableBytes { buffer in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return }
            arc4random_buf(base, buffer.count)
        }

        let started = DispatchTime.now().uptimeNanoseconds
        do {
            // `.atomic` would write to a neighbouring temporary and rename, which
            // is a different — and on a network share, much slower — operation
            // than the streaming write a transfer actually performs.
            try payload.write(to: file)
        } catch {
            throw ProbeFailure.notWritable(directory.path)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        try? FileManager.default.removeItem(at: file)

        guard elapsed > 1_000_000 else { return nil }  // under a millisecond: unmeasurable
        return Double(sampleBytes) / (Double(elapsed) / 1_000_000_000)
    }

    /// Max regular-file size, from `pathconf`.
    ///
    /// POSIX defines `_PC_FILESIZEBITS` as the minimum number of bits needed to
    /// represent the maximum file size **as a signed integer**, so the limit is
    /// `2^(bits-1) - 1`: FAT32 reports 33, giving 4 GiB − 1, which is exactly its
    /// documented cap. Measured on this machine: msdos 33, HFS+ 64, APFS 56.
    /// Anything at or above 63 is reported as no limit — there is nothing useful
    /// to say about a ceiling of 4 exabytes.
    private static func maxFileSize(at directory: URL) -> Int64? {
        let bits = pathconf(directory.path, _PC_FILESIZEBITS)
        guard bits > 0, bits < 63 else { return nil }
        return (Int64(1) << (Int64(bits) - 1)) - 1
    }

    private static func filesystemName(at directory: URL) -> String? {
        var buffer = statfs()
        guard statfs(directory.path, &buffer) == 0 else { return nil }
        return withUnsafePointer(to: buffer.f_fstypename) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self, capacity: Int(MFSTYPENAMELEN)
            ) { String(cString: $0) }
        }
    }
}
