import CryptoKit
import Foundation

/// Packs an app bundle into a single Apple Archive (`.aar`) and back out again.
///
/// It exists so a backup can be stored somewhere that is **not** a Mac-native
/// filesystem. A `.app` is a directory whose meaning lives as much in its metadata
/// as in its bytes — extended attributes, symlinks, permissions, hard links — and
/// an exFAT stick or an SMB share stores those approximately at best. Writing the
/// tree there and reading it back is not the same tree, which matters twice over:
/// the restored app's code signature breaks, and `BackupManifest` (computed on the
/// stored copy, rechecked on the way out) sees a different tree and refuses the
/// rollback. Both failures surface on the day the user actually needs the backup.
///
/// An archive moves that problem out of the destination filesystem's hands: the
/// metadata is encoded *inside* the byte stream, so the destination only has to
/// hold one opaque file, which even FAT can do. It is also the right shape for
/// this payload — we write a backup once and read it back whole, so none of the
/// random-write machinery of a disk image (`hdiutil` sparse bundles, band files,
/// the `F_FULLFSYNC` caveat on network servers) buys us anything.
///
/// Measured on Claude.app — 802 MB across 3421 files:
///
/// | algorithm | archive | time |
/// |---|---|---|
/// | `lzfse` (default) | 330 MB (41%) | 1.8 s |
/// | `lzma` | 242 MB (30%) | 22 s |
/// | extract (`lzfse`) | — | 1.1 s |
///
/// Two things that table understates. Compression is nearly free next to the
/// transfer it feeds, so the default costs essentially nothing. And 3421 files
/// becoming one is the larger win on a network share, where per-file round trips —
/// not bandwidth — are usually what makes a NAS backup slow.
///
/// Round-tripping is verified to preserve the vendor code signature, not merely
/// the file contents: AppCleaner, TestFlight, Pearcleaner and Claude all come back
/// `codesign --verify --deep --strict` clean. That check is separate from a
/// manifest comparison on purpose — `BackupManifest` does not hash extended
/// attributes, so a tree can match byte-for-byte and still restore an app whose
/// seal is broken.
public enum BundleArchive {

    /// Which way to trade time for size.
    ///
    /// `fast` is `lzfse`, Apple's own default, and is what a background transfer
    /// should use: on the measurement above it costs under two seconds for a
    /// 2.4× reduction. `smallest` is `lzma`, which buys a further 27% for twelve
    /// times the CPU — worth offering for a slow or small destination, not worth
    /// making the default.
    public enum Compression: String, Sendable, CaseIterable, Codable {
        case fast, smallest

        var algorithm: String {
            switch self {
            case .fast:     return "lzfse"
            case .smallest: return "lzma"
            }
        }
    }

    public enum ArchiveError: LocalizedError {
        case toolMissing
        case archiveFailed(code: Int32, message: String)
        case extractFailed(code: Int32, message: String)
        case producedNothing
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .toolMissing:
                return "The system archive tool (/usr/bin/aa) is missing."
            case .archiveFailed(let code, let message):
                let detail = message.isEmpty ? "" : " — \(message)"
                return "Could not pack the app into a backup archive (exit \(code))\(detail)."
            case .extractFailed(let code, let message):
                let detail = message.isEmpty ? "" : " — \(message)"
                return "Could not unpack the backup archive (exit \(code))\(detail)."
            case .producedNothing:
                return "Packing the app produced no archive."
            case .unreadable(let path):
                return "Could not read “\(path)”."
            }
        }
    }

    /// Apple Archive ships with the OS; there is no fallback and no vendored copy.
    static let tool = URL(fileURLWithPath: "/usr/bin/aa")

    public static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: tool.path)
    }

    /// The fields we require the archive to carry.
    ///
    /// `aa`'s default set already includes these — the round-trip tests pass
    /// without the flag — but naming them makes the dependency explicit rather
    /// than inherited from an undocumented default that a future macOS is free to
    /// change. `attr` is `aa`'s own alias for `uid,gid,mod,flg,mtm,btm,ctm`.
    /// Adding to the field set is additive, so this cannot subtract anything.
    private static let requiredFields = "xat,acl,attr"

    // MARK: - Pack

    /// Pack `bundle` into a single archive at `file`.
    ///
    /// Writes to a sibling temporary name and renames into place, so an
    /// interrupted run (drive yanked, share dropped) can leave a `.partial`
    /// behind but never a truncated file under the real name. The caller sweeps
    /// those; a half-written archive that looked complete would be a backup that
    /// fails only at restore time.
    public static func archive(
        bundle: URL, to file: URL, compression: Compression = .fast
    ) throws {
        guard isAvailable else { throw ArchiveError.toolMissing }
        guard FileManager.default.fileExists(atPath: bundle.path) else {
            throw ArchiveError.unreadable(bundle.path)
        }

        let partial = file.deletingLastPathComponent()
            .appendingPathComponent(".\(file.lastPathComponent).partial")
        try? FileManager.default.removeItem(at: partial)

        // `-d bundle` archives the bundle's *contents*; the directory's own name is
        // not recorded. That is deliberate — the app's name lives in the sidecar
        // (`Meta.bundleName`), which every read path already requires, and keeping
        // it out of the archive means renaming a backup can never disagree with it.
        let result = run([
            "archive",
            "-d", bundle.path,
            "-o", partial.path,
            "-a", compression.algorithm,
            "-include-field", requiredFields,
            "-no-ignore-eperm",
        ])

        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: partial)
            throw ArchiveError.archiveFailed(code: result.status, message: result.message)
        }
        guard FileManager.default.fileExists(atPath: partial.path) else {
            throw ArchiveError.producedNothing
        }

        try? FileManager.default.removeItem(at: file)
        do {
            try FileManager.default.moveItem(at: partial, to: file)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    // MARK: - Unpack

    /// Unpack `archive` into `directory`, which becomes the restored bundle.
    ///
    /// `directory` must already exist and should be empty; `aa` writes the
    /// bundle's contents directly into it.
    ///
    /// Runs with `-no-ignore-eperm`, which is **not** `aa`'s default. Left at the
    /// default, a failure to set an attribute is swallowed and the extract still
    /// reports success — and a bundle whose extended attributes did not come back
    /// is a bundle whose code signature is broken, restored silently. That is
    /// precisely the failure this whole path exists to prevent, so it is worth
    /// the stricter reading: the cost is that a bundle carrying files this user
    /// cannot chown (a `.pkg` install that left root-owned payload) now refuses to
    /// unpack rather than unpacking wrong.
    public static func extract(archive: URL, into directory: URL) throws {
        guard isAvailable else { throw ArchiveError.toolMissing }
        guard FileManager.default.fileExists(atPath: archive.path) else {
            throw ArchiveError.unreadable(archive.path)
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let result = run([
            "extract",
            "-i", archive.path,
            "-d", directory.path,
            "-no-ignore-eperm",
        ])
        guard result.status == 0 else {
            throw ArchiveError.extractFailed(code: result.status, message: result.message)
        }
    }

    // MARK: - Digest

    /// SHA-256 of a single file, streamed.
    ///
    /// This is the integrity gate for the copy that lives on the destination: one
    /// digest over one file, which no filesystem can disagree about. It replaces —
    /// for that copy — the tree-walking comparison `BackupManifest` has to do,
    /// and it is the reason the destination's filesystem stops mattering.
    ///
    /// Chunked for the same reason `BackupManifest.compute` is: an app archive
    /// runs to hundreds of megabytes, and reading one whole into memory to hash it
    /// is how a backup of a large app turns into a memory spike.
    public static func sha256(of file: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            throw ArchiveError.unreadable(file.path)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Process

    /// The subprocess running right now, so a quitting app can stop it instead of
    /// orphaning it.
    ///
    /// `aa` is a child process, and macOS does not take it down when we exit — an
    /// orphan would keep writing, finish, and rename a complete archive into
    /// place that nothing then records in a sidecar. The bytes would be invisible
    /// to every read path and swept by none of them, because the sweeper looks
    /// for `.partial` and this is not one.
    private nonisolated(unsafe) static var inFlight: Process?
    private static let inFlightLock = NSLock()

    /// Stop the running archive/extract, if any. Safe to call when nothing runs.
    public static func terminateInFlight() {
        inFlightLock.lock()
        let process = inFlight
        inFlightLock.unlock()
        process?.terminate()
    }

    private static func run(_ arguments: [String]) -> (status: Int32, message: String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let errPipe = Pipe()
        let outPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = outPipe

        do { try process.run() } catch {
            return (-1, error.localizedDescription)
        }
        inFlightLock.lock(); inFlight = process; inFlightLock.unlock()
        defer { inFlightLock.lock(); inFlight = nil; inFlightLock.unlock() }
        // Drained before `waitUntilExit` so a verbose failure cannot fill the pipe
        // buffer and deadlock the tool against a reader that never runs.
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        _ = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let message = String(decoding: errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").last.map(String.init) ?? ""
        return (process.terminationStatus, message)
    }
}
