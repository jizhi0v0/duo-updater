import CryptoKit
import Foundation
import Security

/// Keeps one backup copy of each app's *previous* bundle so an update can be
/// rolled back — the safety net that makes a one-click in-place update feel safe.
///
/// Backups live under Application Support, one directory per app, holding the
/// replaced `.app` and a small JSON sidecar with the version it was. Retention is
/// deliberately **one**: we only ever need "the version before the last update,"
/// and app bundles are large, so a deeper history would balloon disk use for no
/// real benefit. Saving a new backup atomically supersedes the old one.
///
/// This is pure filesystem orchestration (no UI, no preferences): the App layer
/// decides *whether* to keep backups and calls `save`/`restore` accordingly, so
/// the install pipeline in Core stays untouched. The `rootOverride` seam lets
/// tests exercise the retention/path logic against a scratch directory.
public enum BackupStore {

    /// Test seam: when set, backups read/write here instead of Application Support.
    /// Mutated only by tests (single-threaded), hence `nonisolated(unsafe)`.
    nonisolated(unsafe) public static var rootOverride: URL?

    public static var root: URL {
        if let rootOverride { return rootOverride }
        return DuoStateDirectory.base
            .appendingPathComponent("DuoUpdater/Backups", isDirectory: true)
    }

    /// A stored backup: the bundle on disk plus the metadata we show in the UI.
    public struct Backup: Sendable, Equatable {
        public let key: String
        public let version: String?
        public let bundlePath: URL
        public let savedAt: Date
        /// Whether the update this backup was taken for was applied by a `.pkg`
        /// through the system installer.
        ///
        /// It matters at restore time: a pkg can install helpers, daemons and
        /// launch items alongside the `.app`, and we only ever copy the bundle.
        /// Restoring one therefore gives an older app beside newer components,
        /// which is worth saying out loud rather than presenting as a clean
        /// rollback. Nil for backups written before this was recorded.
        public let fromPackageInstall: Bool?
    }

    /// JSON sidecar persisted next to a backed-up bundle.
    private struct Meta: Codable {
        let version: String?
        let bundleID: String?
        let originalPath: String
        let bundleName: String
        let savedAt: Date
        /// Optional so sidecars written before this field decode unchanged —
        /// a stricter decoder would make every existing backup unreadable, and
        /// `backup(forKey:)` returns nil without a readable sidecar.
        var fromPackageInstall: Bool?
    }

    /// A filesystem-safe directory name for one installed copy of an app. It keeps
    /// the bundle id/name as a readable prefix, but scopes the key by resolved path:
    /// two installed copies can share a bundle id (Android Studio channels,
    /// duplicate app bundles), and their rollback points must never overwrite each
    /// other.
    public static func key(bundleID: String?, path: URL) -> String {
        let label = sanitized(bundleID ?? path.deletingPathExtension().lastPathComponent)
        let pathID = shortPathID(path)
        return "\(label)-\(pathID)"
    }

    /// Current key followed by the pre-path-scoped key. Read paths use this so
    /// backups written before the collision fix still appear and can be restored;
    /// new writes always use ``key(bundleID:path:)``.
    public static func keyCandidates(bundleID: String?, path: URL) -> [String] {
        let current = key(bundleID: bundleID, path: path)
        let legacy = legacyKey(bundleID: bundleID, path: path)
        return current == legacy ? [current] : [current, legacy]
    }

    private static func legacyKey(bundleID: String?, path: URL) -> String {
        sanitized(bundleID ?? path.path)
    }

    private static func sanitized(_ raw: String) -> String {
        let safe = raw.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber || c == "." || c == "-" || c == "_" { return c }
            return "_"
        }
        let joined = String(safe)
        // Guard against an empty or all-dots name that could resolve oddly.
        return joined.isEmpty || joined.allSatisfy { $0 == "." } ? "app" : joined
    }

    private static func shortPathID(_ path: URL) -> String {
        let resolved = path.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(resolved.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Save

    /// The first path inside `appPath` we cannot read, or nil when the whole
    /// bundle is copyable.
    ///
    /// Worth checking before `save` because `ditto` fails *late*: it copies what
    /// it can and only then exits non-zero, so a bundle with one unreadable file
    /// costs a full-size copy that is thrown away. A `.pkg`-installed app is the
    /// common case — those are frequently root-owned and keep runtime state
    /// inside their own bundle (ToDesk writes an mmkv database and log caches
    /// under `Contents/`, root-owned and unreadable by the user), so this is the
    /// difference between "no rollback point, and here is why" and 300 MB of
    /// pointless copying on every install.
    ///
    /// A stat per file, so cheap next to the copy it guards.
    public static func firstUnreadablePath(in appPath: URL) -> String? {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: appPath, includingPropertiesForKeys: [.isRegularFileKey],
            options: [])
        else { return appPath.path }
        for case let url as URL in walker {
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile
            guard isRegular == true else { continue }
            if !fm.isReadableFile(atPath: url.path) { return url.path }
        }
        return nil
    }

    /// Copy the bundle currently at `appPath` into the backup store as the
    /// rollback point for `key`, replacing any previous backup (retention = 1).
    /// Returns the stored backup. Throws if the copy fails — the caller should
    /// treat that as "no rollback point" but must NOT block the update on it.
    @discardableResult
    public static func save(
        appPath: URL, key: String, version: String?, bundleID: String?,
        fromPackageInstall: Bool = false
    ) throws -> Backup {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(key, isDirectory: true)
        // Build the new backup in a hidden staging dir FIRST, then swap it into place
        // atomically. Retention = 1 must not delete the prior rollback point until the
        // new copy is fully written — otherwise a failed/interrupted re-backup (disk
        // full, crash) would leave the user with no backup at all for an app that's
        // about to change versions. The staging name is hidden (`.`-prefixed, so it's
        // skipped by `allBackups`' directory scan) and keyed per app, so it self-cleans
        // across a crashed prior attempt.
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".staging-\(key)", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let name = appPath.lastPathComponent
        let staged = staging.appendingPathComponent(name)
        // `ditto` preserves the bundle's symlinks, xattrs, and (importantly) its
        // code signature exactly — a plain copy can mangle them.
        guard runDitto(from: appPath, to: staged) else {
            try? fm.removeItem(at: staging)
            throw BackupError.copyFailed(appPath.path)
        }

        let savedAt = Date()
        let meta = Meta(
            version: version, bundleID: bundleID,
            originalPath: appPath.path, bundleName: name, savedAt: savedAt,
            fromPackageInstall: fromPackageInstall)
        // The sidecar is what EVERY read path keys off (`backup(forKey:)` returns nil
        // without it), so a backup whose sidecar didn't write is unusable. Fail the
        // save (leaving the prior backup intact) rather than leave an invisible bundle.
        guard let metaData = try? JSONEncoder().encode(meta),
              (try? metaData.write(to: staging.appendingPathComponent("backup.json"),
                                   options: .atomic)) != nil else {
            try? fm.removeItem(at: staging)
            throw BackupError.copyFailed(appPath.path)
        }

        // New backup is complete in `staging`; now replace the old one atomically (a
        // same-volume rename, so the swap window is a single near-instant operation
        // rather than the multi-second copy above).
        do {
            if fm.fileExists(atPath: dir.path) {
                _ = try fm.replaceItemAt(dir, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: dir)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw BackupError.copyFailed(appPath.path)
        }
        let dest = dir.appendingPathComponent(name)
        // Migration cleanup: a copy backed up before keys became path-scoped left
        // a dir under the bare bundle-id legacy key. Now that the canonical,
        // path-scoped backup exists (and `keyCandidates` would only ever fall back
        // to that orphan), drop it so retention stays at one copy on disk instead
        // of leaking a whole stale bundle per migrated app.
        let legacy = legacyKey(bundleID: bundleID, path: appPath)
        if legacy != key { remove(forKey: legacy) }
        return Backup(
            key: key, version: version, bundlePath: dest, savedAt: savedAt,
            fromPackageInstall: fromPackageInstall)
    }

    // MARK: - Query

    /// The current backup for `key`, or nil if none exists.
    public static func backup(forKey key: String) -> Backup? {
        let dir = root.appendingPathComponent(key, isDirectory: true)
        let metaURL = dir.appendingPathComponent("backup.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
        let bundle = dir.appendingPathComponent(meta.bundleName)
        guard FileManager.default.fileExists(atPath: bundle.path) else { return nil }
        return Backup(
            key: key, version: meta.version, bundlePath: bundle, savedAt: meta.savedAt,
            fromPackageInstall: meta.fromPackageInstall)
    }

    // MARK: - Restore

    /// Swap the backed-up bundle for `key` back over `target`, returning the
    /// version restored. Copies the backup to a scratch dir first (so the stored
    /// backup survives the move that `InPlaceSwap` performs), then runs the same
    /// validated, atomic swap an install uses. The backup is left in place — a
    /// rollback shouldn't also destroy the only copy of the version it restored.
    @discardableResult
    public static func restore(forKey key: String, over target: URL) throws -> String? {
        guard let backup = backup(forKey: key) else {
            throw BackupError.noBackup(key)
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("DuoUpdater-rollback-\(key)", isDirectory: true)
        try? fm.removeItem(at: scratch)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        let staged = scratch.appendingPathComponent(backup.bundlePath.lastPathComponent)
        guard runDitto(from: backup.bundlePath, to: staged) else {
            throw BackupError.copyFailed(backup.bundlePath.path)
        }
        // Integrity gate before swapping a backup over the live app: a backup whose
        // present code signature no longer validates has been corrupted or tampered
        // with, and swapping it in would brick the live app with a broken bundle.
        // Hard-fail rather than restore it — a rollback that knowingly installs a
        // damaged bundle is worse than leaving the (working) current app in place,
        // and the failure tells the user the backup is unusable. A genuinely UNSIGNED
        // bundle is still allowed (the helper distinguishes that from a failed
        // present signature) — many legitimate apps ship unsigned. The signed
        // identifier isn't checked against the target — a rollback may legitimately
        // cross an identifier/Team change the forward update introduced.
        guard backupSignatureLooksValid(staged) else {
            Log.install.error(
                "rollback: backup for \(key, privacy: .public) failed signature validation — refusing to restore (it may be corrupted)")
            throw BackupError.backupCorrupted(backup.bundlePath.lastPathComponent)
        }
        try InPlaceSwap.replace(newApp: staged, over: target)
        return backup.version
    }

    /// True if the staged backup either validates cleanly or is simply unsigned;
    /// false only when a present signature fails to validate (corruption/tampering).
    private static func backupSignatureLooksValid(_ bundle: URL) -> Bool {
        do {
            try SignatureVerifier.verifyCodeSignature(appAt: bundle)
            return true
        } catch let SignatureVerifier.VerifyError.codeSignatureInvalid(status)
                    where status == errSecCSUnsigned {
            return true
        } catch {
            return false
        }
    }

    /// Every current backup, keyed by app key — one scan of the backups root.
    /// Lets the UI light up rollback affordances without a stat per app.
    public static func allBackups() -> [String: Backup] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [:] }
        var out: [String: Backup] = [:]
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            if let backup = backup(forKey: dir.lastPathComponent) {
                out[dir.lastPathComponent] = backup
            }
        }
        return out
    }

    /// Drop the backup for `key` (e.g. the user dismissed it).
    public static func remove(forKey key: String) {
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent(key, isDirectory: true))
    }

    // MARK: - Cleanup

    /// Removes backups whose original app no longer exists at the recorded path —
    /// uninstalled, moved, or replaced under a fresh path-scoped key. Retention
    /// per key is already 1 (`save` supersedes the prior backup atomically), so
    /// the only unbounded growth left is these orphans: nothing ever revisits a
    /// key once its app is gone, and a large app bundle backup left behind is
    /// pure disk waste with no path left to restore onto. Returns the bytes freed.
    @discardableResult
    public static func pruneOrphans() -> Int64 {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var freed: Int64 = 0
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let metaURL = dir.appendingPathComponent("backup.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? JSONDecoder().decode(Meta.self, from: data)
            else { continue }
            guard !fm.fileExists(atPath: meta.originalPath) else { continue }
            freed += directorySize(dir)
            try? fm.removeItem(at: dir)
        }
        return freed
    }

    /// Total on-disk size of every stored backup, for display in Settings.
    public static func totalSize() -> Int64 {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return 0 }
        return dirs.reduce(into: 0) { $0 += directorySize($1) }
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey],
            options: [], errorHandler: nil)
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Errors

    public enum BackupError: LocalizedError {
        case copyFailed(String)
        case noBackup(String)
        case backupCorrupted(String)

        public var errorDescription: String? {
            switch self {
            case .copyFailed(let path):
                return "Could not copy the app bundle at “\(path)”."
            case .noBackup(let key):
                return "There is no backup to roll back to for “\(key)”."
            case .backupCorrupted(let name):
                return "The backup for “\(name)” appears corrupted (its code signature no longer validates) and was not restored."
            }
        }
    }

    /// `ditto src dst`, returning true on success. Faithfully duplicates a bundle
    /// including its code signature, unlike `FileManager.copyItem`.
    private static func runDitto(from src: URL, to dst: URL) -> Bool {
        try? FileManager.default.removeItem(at: dst)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [src.path, dst.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
