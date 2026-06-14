import CryptoKit
import Foundation

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
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DuoUpdater/Backups", isDirectory: true)
    }

    /// A stored backup: the bundle on disk plus the metadata we show in the UI.
    public struct Backup: Sendable, Equatable {
        public let key: String
        public let version: String?
        public let bundlePath: URL
        public let savedAt: Date
    }

    /// JSON sidecar persisted next to a backed-up bundle.
    private struct Meta: Codable {
        let version: String?
        let bundleID: String?
        let originalPath: String
        let bundleName: String
        let savedAt: Date
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

    /// Copy the bundle currently at `appPath` into the backup store as the
    /// rollback point for `key`, replacing any previous backup (retention = 1).
    /// Returns the stored backup. Throws if the copy fails — the caller should
    /// treat that as "no rollback point" but must NOT block the update on it.
    @discardableResult
    public static func save(
        appPath: URL, key: String, version: String?, bundleID: String?
    ) throws -> Backup {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(key, isDirectory: true)
        // Retention = 1: drop any prior backup wholesale before writing the new one.
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let name = appPath.lastPathComponent
        let dest = dir.appendingPathComponent(name)
        // `ditto` preserves the bundle's symlinks, xattrs, and (importantly) its
        // code signature exactly — a plain copy can mangle them.
        guard runDitto(from: appPath, to: dest) else {
            try? fm.removeItem(at: dir)
            throw BackupError.copyFailed(appPath.path)
        }

        let savedAt = Date()
        let meta = Meta(
            version: version, bundleID: bundleID,
            originalPath: appPath.path, bundleName: name, savedAt: savedAt)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: dir.appendingPathComponent("backup.json"))
        }
        // Migration cleanup: a copy backed up before keys became path-scoped left
        // a dir under the bare bundle-id legacy key. Now that the canonical,
        // path-scoped backup exists (and `keyCandidates` would only ever fall back
        // to that orphan), drop it so retention stays at one copy on disk instead
        // of leaking a whole stale bundle per migrated app.
        let legacy = legacyKey(bundleID: bundleID, path: appPath)
        if legacy != key { remove(forKey: legacy) }
        return Backup(key: key, version: version, bundlePath: dest, savedAt: savedAt)
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
        return Backup(key: key, version: meta.version, bundlePath: bundle, savedAt: meta.savedAt)
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
        try InPlaceSwap.replace(newApp: staged, over: target)
        return backup.version
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

    // MARK: - Errors

    public enum BackupError: LocalizedError {
        case copyFailed(String)
        case noBackup(String)

        public var errorDescription: String? {
            switch self {
            case .copyFailed(let path):
                return "Could not copy the app bundle at “\(path)”."
            case .noBackup(let key):
                return "There is no backup to roll back to for “\(key)”."
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
