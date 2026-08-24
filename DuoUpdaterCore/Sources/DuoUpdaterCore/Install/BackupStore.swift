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

    /// Test seam: when bound, backups read/write here instead of Application Support.
    ///
    /// Task-local rather than a plain global. It used to be
    /// `nonisolated(unsafe) static var`, justified as "mutated only by tests
    /// (single-threaded)" — but Swift Testing runs *suites* in parallel, and
    /// `.serialized` only orders tests within one suite, never across them. So
    /// `BackupStoreTests` could be holding its scratch root at the moment another
    /// suite read `root`, which is exactly how `DuoStateDirectoryTests` failed
    /// intermittently (~1 run in 5).
    ///
    /// Binding it to the task instead makes the override invisible outside the test
    /// that set it, so the two suites cannot see each other's value no matter how
    /// they interleave. Production never binds it and always gets nil.
    @TaskLocal public static var rootOverride: URL?

    /// Test seam for the *destination*, bound the same way and for the same
    /// reason as `rootOverride`. Production never binds it and reads
    /// ``configure(_:)``'s value instead.
    @TaskLocal public static var destinationOverride: BackupDestination?

    /// Where backups are written first, always on the boot volume.
    ///
    /// This is the store as it has always been — the name changed, the meaning
    /// did not. When no external destination is configured it is also where they
    /// stay; when one is configured it is the staging area a transfer drains.
    /// Keeping it as the first stop is what lets an unreachable disk degrade to
    /// "the rollback point is on this Mac for now" rather than "there is no
    /// rollback point", and it keeps every existing backup exactly where it is.
    public static var outboxRoot: URL {
        if let rootOverride { return rootOverride }
        return DuoStateDirectory.base
            .appendingPathComponent("DuoUpdater/Backups", isDirectory: true)
    }

    /// Former name of ``outboxRoot``, kept so existing callers and tests read
    /// unchanged.
    public static var root: URL { outboxRoot }

    // MARK: - Destination

    private nonisolated(unsafe) static var configuredDestination: BackupDestination = .local
    private static let destinationLock = NSLock()

    /// Point the store at a destination. Called once per process — the app at
    /// launch, `duo` in `main` — so no command can forget and silently use a
    /// different store than the one the user configured.
    public static func configure(_ destination: BackupDestination) {
        destinationLock.lock()
        defer { destinationLock.unlock() }
        configuredDestination = destination
    }

    public static var destination: BackupDestination {
        if let destinationOverride { return destinationOverride }
        destinationLock.lock()
        defer { destinationLock.unlock() }
        return configuredDestination
    }

    /// Whether the configured destination can be written to right now.
    ///
    /// Every case is reported rather than collapsed into a bool because the
    /// difference matters to the user: a disk that is merely unplugged will come
    /// back on its own, one holding a different volume needs a decision, and a
    /// read-only mount needs a different fix again. Collapsing them is how a UI
    /// ends up saying "no backups" when the truthful answer is "your backup disk
    /// isn't connected".
    public enum Availability: Sendable, Equatable {
        /// No external destination configured; the outbox is the store.
        case localOnly(URL)
        case ready(URL)
        case volumeNotMounted(volumeName: String?, path: String)
        case identityMismatch(expected: String?, found: String?, path: String)
        case notWritable(path: String)

        /// The disk's name when its copies cannot be read right now, else nil.
        ///
        /// One accessor for all three unreachable cases on purpose. They differ
        /// in what the user has to do about it — which the Backups settings page
        /// spells out — but they are identical in the fact a list somewhere else
        /// is now shorter than the store, and that is the only thing the rollback
        /// surface needs to say.
        public var unreachableDiskName: String? {
            switch self {
            case .localOnly, .ready:
                return nil
            case .volumeNotMounted(let name, let path):
                return name ?? Self.diskName(fromPath: path)
            case .identityMismatch(_, _, let path), .notWritable(let path):
                return Self.diskName(fromPath: path)
            }
        }

        /// "Archive" out of "/Volumes/Archive/DuoUpdater Backups". Falls back to
        /// the whole path rather than inventing a name, since a destination need
        /// not live under `/Volumes` at all.
        private static func diskName(fromPath path: String) -> String {
            let parts = URL(fileURLWithPath: path).pathComponents
            guard let volumes = parts.firstIndex(of: "Volumes"),
                  parts.indices.contains(volumes + 1) else { return path }
            return parts[volumes + 1]
        }
    }

    /// Resolve the destination's state **without creating anything**.
    ///
    /// The order is deliberate: existence is checked before any thought of
    /// writing. `save` used to reach the destination through
    /// `createDirectory(withIntermediateDirectories: true)`, which on a detached
    /// disk does not fail — it happily builds the whole path on the boot volume.
    /// That is worse than losing the backup: the directory now squats the mount
    /// point, so when the real disk is plugged in macOS mounts it beside the
    /// decoy as `Archive 1`, and the user's backups are split across two places
    /// that each look correct.
    public static func availability(
        _ destination: BackupDestination = BackupStore.destination
    ) -> Availability {
        guard let directory = destination.directory else {
            return .localOnly(outboxRoot)
        }
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .volumeNotMounted(
                volumeName: destination.volumeName, path: directory.path)
        }

        // A marker we cannot read means this is not the place we configured —
        // most often nothing is mounted and something else made the directory.
        // Treating that as "not mounted" rather than "corrupt" is the reading
        // that matches what the user has to do about it: plug the disk in.
        let marker = BackupVolumeMarker.read(at: directory)
        if let expected = destination.identity {
            guard let marker else {
                return .volumeNotMounted(
                    volumeName: destination.volumeName, path: directory.path)
            }
            guard marker.identity == expected else {
                return .identityMismatch(
                    expected: expected, found: marker.identity, path: directory.path)
            }
        }

        guard fm.isWritableFile(atPath: directory.path) else {
            return .notWritable(path: directory.path)
        }
        return .ready(directory)
    }

    /// The destination directory, or nil when backups are local-only.
    /// Throws when one is configured but unreachable — never a URL that merely
    /// looks usable.
    static func destinationRoot() throws -> URL? {
        switch availability() {
        case .localOnly:
            return nil
        case .ready(let url):
            return url
        case .volumeNotMounted(let name, let path):
            throw BackupError.destinationUnavailable(name ?? path)
        case .identityMismatch(_, _, let path):
            throw BackupError.destinationIsADifferentDisk(path)
        case .notWritable(let path):
            throw BackupError.destinationNotWritable(path)
        }
    }

    /// The destination directory when it happens to be reachable, else nil.
    /// For read paths, which must degrade to "show what is on this Mac" rather
    /// than fail.
    static var reachableDestinationRoot: URL? {
        if case .ready(let url) = availability() { return url }
        return nil
    }

    /// A stored backup: what is on disk plus the metadata we show in the UI.
    public struct Backup: Sendable, Equatable {
        /// Which of the two stores this copy came out of.
        public enum Location: Sendable, Equatable {
            /// A plain `.app` directory on the boot volume.
            case outbox
            /// A `.aar` archive on the configured external destination.
            case destination
        }

        public let key: String
        public let version: String?
        /// Where the stored copy lives: the `.app` directory for an outbox
        /// backup, the archive file for one on the destination. Read `location`
        /// before assuming which — a destination copy is a single file, so
        /// walking it as a directory yields nothing rather than failing.
        public let bundlePath: URL
        public let location: Location
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

        public init(
            key: String, version: String?, bundlePath: URL,
            location: Location = .outbox, savedAt: Date, fromPackageInstall: Bool?
        ) {
            self.key = key
            self.version = version
            self.bundlePath = bundlePath
            self.location = location
            self.savedAt = savedAt
            self.fromPackageInstall = fromPackageInstall
        }
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
        /// Files deliberately left out of the copy: unreadable, and not covered
        /// by the code signature, so they are the app's own runtime state rather
        /// than shipped payload. Restoring without them is fine — the app writes
        /// them again — but the user is told, because it means losing whatever
        /// state lived there.
        var omittedFiles: [String]?
        /// What the stored copy hashed to when we wrote it. Optional for the
        /// same reason; a backup without one falls back to the old
        /// vendor-signature gate at restore, which is the best that can be said
        /// about a copy we never fingerprinted.
        var manifest: BackupManifest?
        /// Name of the archive holding this backup at the destination, e.g.
        /// `Slack-4.35.121.aar`. Optional for the same reason as the fields
        /// above — an outbox-only backup has none, and neither does one written
        /// before there were destinations.
        var archiveName: String?
        /// SHA-256 of that archive as written.
        ///
        /// This is the integrity gate for the copy on the destination, and it is
        /// deliberately a different question from `manifest`. One digest over one
        /// file is something no filesystem can disagree about, which is the whole
        /// reason a backup can live on a volume that could never hold the bundle
        /// itself. `manifest` still guards the restore, but it is computed on the
        /// unpacked tree — on APFS, both times.
        var archiveSHA256: String?
        /// Size of the archive on disk, so the UI can show what the move bought.
        var archiveBytes: Int64?
        /// True while a copy still exists only in the outbox and is waiting to be
        /// moved to the destination. Absent means "not waiting", which is the
        /// right reading for every backup written before transfers existed.
        var pendingTransfer: Bool?
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
        // Always the outbox, never the destination — even when one is configured.
        // Writing here first is what makes an unplugged disk a delay rather than a
        // missing rollback point, and it keeps the manifest recorded below computed
        // on APFS, which is what lets the same manifest gate a restore later.
        let dir = outboxRoot.appendingPathComponent(key, isDirectory: true)
        // Build the new backup in a hidden staging dir FIRST, then swap it into place
        // atomically. Retention = 1 must not delete the prior rollback point until the
        // new copy is fully written — otherwise a failed/interrupted re-backup (disk
        // full, crash) would leave the user with no backup at all for an app that's
        // about to change versions. The staging name is hidden (`.`-prefixed, so it's
        // skipped by `allBackups`' directory scan) and keyed per app, so it self-cleans
        // across a crashed prior attempt.
        try fm.createDirectory(at: outboxRoot, withIntermediateDirectories: true)
        let staging = outboxRoot.appendingPathComponent(".staging-\(key)", isDirectory: true)
        forceRemove(staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let name = appPath.lastPathComponent
        let staged = staging.appendingPathComponent(name)

        // An app that keeps runtime state inside its own bundle (ToDesk writes an
        // mmkv database and log caches under Contents/, root-owned) leaves files
        // we cannot read. Those are not payload — the seal never covered them and
        // the app rewrites them — so the copy may skip them. A file the seal DOES
        // cover is payload, and a bundle without it is broken, so there is
        // nothing worth storing.
        let unreadable = BackupManifest.unreadableFiles(in: appPath)
        guard unreadable.sealed.isEmpty else {
            forceRemove(staging)
            throw BackupError.payloadUnreadable(unreadable.sealed.first ?? appPath.path)
        }

        // `ditto` preserves the bundle's symlinks, xattrs, and (importantly) its
        // code signature exactly — a plain copy can mangle them. It reports one
        // status for the whole run, so a non-zero exit is only acceptable once we
        // have confirmed the ONLY things it dropped are the ones we meant to drop.
        if !runDitto(from: appPath, to: staged) {
            // No expected omissions means the copy failed for some other reason
            // (a missing source, a full disk) and there is nothing to forgive.
            // Without this, a source that does not exist produced an empty copy
            // that passed the omission check and got stored as a backup.
            guard !unreadable.unsealed.isEmpty else {
                forceRemove(staging)
                throw BackupError.copyFailed(appPath.path)
            }
            let unexpected = BackupManifest.unexpectedOmissions(
                source: appPath, copy: staged, expected: unreadable.unsealed)
            guard unexpected.isEmpty else {
                Log.install.error(
                    "backup: copy of \(name, privacy: .public) lost \(unexpected.count, privacy: .public) file(s) it should have kept")
                forceRemove(staging)
                throw BackupError.copyFailed(appPath.path)
            }
        }

        let savedAt = Date()
        // Fingerprinted from the staged copy, not the source: what restore has
        // to be able to trust is that the bytes in the store are the ones that
        // came out of this copy, and hashing the source would certify something
        // we did not keep.
        let manifest = BackupManifest.compute(for: staged)
        if manifest == nil {
            Log.install.error(
                "backup: could not fingerprint \(name, privacy: .public) — restoring it will fall back to the signature gate")
        }
        let meta = Meta(
            version: version, bundleID: bundleID,
            originalPath: appPath.path, bundleName: name, savedAt: savedAt,
            fromPackageInstall: fromPackageInstall,
            omittedFiles: unreadable.unsealed.isEmpty ? nil : unreadable.unsealed,
            manifest: manifest,
            // Marked from the destination *setting*, not from whether the disk
            // happens to be plugged in: the copy is owed either way, and a backup
            // taken while the disk was out would otherwise never be picked up when
            // it came back.
            pendingTransfer: destination.kind == .external ? true : nil)
        // The sidecar is what EVERY read path keys off (`backup(forKey:)` returns nil
        // without it), so a backup whose sidecar didn't write is unusable. Fail the
        // save (leaving the prior backup intact) rather than leave an invisible bundle.
        guard let metaData = try? JSONEncoder().encode(meta),
              (try? metaData.write(to: staging.appendingPathComponent("backup.json"),
                                   options: .atomic)) != nil else {
            forceRemove(staging)
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
            forceRemove(staging)
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

    // MARK: - Transfer

    /// Keys whose backup is still sitting in the outbox owing a copy to the
    /// destination — what a drain works through.
    ///
    /// **Everything in the outbox**, once a destination is configured, not only
    /// what was saved since. The outbox is a staging area by definition, so
    /// anything left in it is owed. Filtering on the `pendingTransfer` flag
    /// written at save time looked tidier and was wrong in the case that matters:
    /// backups taken before the disk was ever chosen would never move, which on a
    /// real machine meant the 23.87 GB the user was trying to reclaim was exactly
    /// the part that stayed put. The flag remains in the sidecar of the copy on
    /// the disk, where it records that the move is settled.
    ///
    /// A directory only counts when it is actually a backup — a readable sidecar
    /// and the bundle it names. Skipping that check to save the reads was a false
    /// economy: `save` leaves a directory behind when it refuses a bundle it
    /// cannot fully read (ToDesk and VSCodium both do this, keeping root-owned
    /// state inside their own bundles), and those remnants went into the queue as
    /// work that could never succeed.
    public static func pendingTransferKeys() -> [String] {
        guard destination.kind == .external else { return [] }
        return storedKeys(in: outboxRoot).filter { key in
            let dir = outboxRoot.appendingPathComponent(key, isDirectory: true)
            guard let meta = readMeta(in: dir) else { return false }
            return FileManager.default.fileExists(
                atPath: dir.appendingPathComponent(meta.bundleName).path)
        }
    }

    /// The app's name for a key, for a progress line someone can read.
    /// `com.pais.handy-1551b69e…` is an identity, not a name.
    public static func displayName(forKey key: String) -> String? {
        for root in [outboxRoot, reachableDestinationRoot].compactMap({ $0 }) {
            if let meta = readMeta(in: root.appendingPathComponent(key, isDirectory: true)) {
                return (meta.bundleName as NSString).deletingPathExtension
            }
        }
        return nil
    }

    /// Archive the outbox copy of `key` onto the destination and drop the local
    /// one. Throws — without touching either copy — when the disk is not there.
    ///
    /// The order is the whole of the safety argument, so it is worth stating
    /// plainly: the archive lands, then its digest is read back **from the
    /// destination**, then the sidecar is written, and only then is the local
    /// copy removed. At every point before that last step there is a complete,
    /// restorable backup somewhere. Reversing any two of them would open a
    /// window where a yanked cable leaves the user with no rollback point for an
    /// app that has just been updated — which is the one outcome this whole
    /// feature exists to avoid.
    ///
    /// The digest is deliberately computed by reading the file back off the
    /// destination rather than from the bytes we just had in hand. It costs one
    /// sequential read and it is the only thing here that actually proves the
    /// write arrived; hashing the source would certify something we did not
    /// store, which is the same mistake `save` explicitly avoids.
    @discardableResult
    public static func transferToDestination(
        forKey key: String,
        compression: BundleArchive.Compression = UpdateSettings.backupCompressionDefault
    ) throws -> Backup {
        guard let root = try destinationRoot() else {
            throw BackupError.destinationUnavailable(destination.volumeName ?? "backup disk")
        }
        let fm = FileManager.default
        let outboxDir = outboxRoot.appendingPathComponent(key, isDirectory: true)
        guard let meta = readMeta(in: outboxDir) else { throw BackupError.noBackup(key) }
        let bundle = outboxDir.appendingPathComponent(meta.bundleName)
        guard fm.fileExists(atPath: bundle.path) else { throw BackupError.noBackup(key) }

        // Safe to create: `destinationRoot()` has already established that the
        // root exists and carries our marker, so this cannot conjure a path on
        // the boot volume.
        let targetDir = root.appendingPathComponent(key, isDirectory: true)
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let archiveName = (meta.bundleName as NSString).deletingPathExtension + ".aar"
        let archive = targetDir.appendingPathComponent(archiveName)
        // Straight to the destination rather than via a local staging file:
        // `BundleArchive` already writes a `.partial` beside the target and
        // renames it, so the atomicity is the same, and streaming the compressed
        // output over means a transfer never needs a second bundle-sized hole on
        // the boot volume — which is usually the reason the store was moved.
        try BundleArchive.archive(bundle: bundle, to: archive, compression: compression)

        let digest = try BundleArchive.sha256(of: archive)
        let bytes = (try? fm.attributesOfItem(atPath: archive.path)[.size] as? Int64) ?? nil

        var moved = meta
        moved.archiveName = archiveName
        moved.archiveSHA256 = digest
        moved.archiveBytes = bytes
        moved.pendingTransfer = false
        guard let data = try? JSONEncoder().encode(moved),
              (try? data.write(to: targetDir.appendingPathComponent("backup.json"),
                               options: .atomic)) != nil else {
            // No sidecar means no readable backup, so leave nothing half-made.
            forceRemove(targetDir)
            throw BackupError.copyFailed(archive.path)
        }

        forceRemove(outboxDir)
        Log.install.info(
            "backup: moved \(key, privacy: .public) to the backup disk (\(bytes ?? 0, privacy: .public) bytes)")
        return Backup(
            key: key, version: meta.version, bundlePath: archive, location: .destination,
            savedAt: meta.savedAt, fromPackageInstall: meta.fromPackageInstall)
    }

    // MARK: - Cleanup of interrupted work

    /// Remove scratch left behind by a transfer that was cut off — a yanked
    /// disk, a crash, a sleep the copy did not survive.
    ///
    /// Age is the only usable signal across processes, but a network volume's
    /// timestamps come from the server's clock and can be skewed, so this is the
    /// backstop and not the guard: `excluding` carries the keys a queue knows
    /// are in flight right now, and those are skipped regardless of what their
    /// mtime claims.
    public static func sweepStaleScratch(
        olderThan age: TimeInterval = 24 * 60 * 60, excluding inFlight: Set<String> = []
    ) {
        sweepStaleScratch(in: outboxRoot, age: age, inFlight: inFlight)
        if let destination = reachableDestinationRoot {
            sweepStaleScratch(in: destination, age: age, inFlight: inFlight)
        }
    }

    private static func sweepStaleScratch(in root: URL, age: TimeInterval, inFlight: Set<String>) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-age)
        let keys: [URLResourceKey] = [.contentModificationDateKey]

        func isStale(_ url: URL) -> Bool {
            guard let modified = (try? url.resourceValues(forKeys: Set(keys)))?
                .contentModificationDate else { return false }
            return modified < cutoff
        }

        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: []) else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            // A save that never finished: `.staging-<key>` at the store root.
            if name.hasPrefix(".staging-") {
                let key = String(name.dropFirst(".staging-".count))
                if !inFlight.contains(key), isStale(entry) { forceRemove(entry) }
                continue
            }
            // A transfer that never finished: the archive's `.partial` lives one
            // level down, inside the key's own directory, because that is where
            // it has to be for the rename into place to stay on one volume.
            guard !name.hasPrefix("."), !inFlight.contains(name) else { continue }
            guard let inner = try? fm.contentsOfDirectory(
                at: entry, includingPropertiesForKeys: keys, options: []) else { continue }
            for file in inner where file.lastPathComponent.hasSuffix(".partial") {
                if isStale(file) { forceRemove(file) }
            }
            // A key directory with no sidecar is not a backup — no read path can
            // see it and no other sweep would ever remove it. It is what an
            // interrupted transfer leaves when the archive landed but the sidecar
            // never did: dead bytes that would sit on the disk forever. Only ever
            // true inside our own store root, which is why the store owns a
            // subdirectory rather than the folder the user picked.
            if readMeta(in: entry) == nil, isStale(entry) {
                forceRemove(entry)
            }
        }
    }

    // MARK: - Query

    private static func readMeta(in dir: URL) -> Meta? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("backup.json"))
        else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    /// The backup for `key` held under a specific root.
    private static func backup(
        forKey key: String, in root: URL, location: Backup.Location
    ) -> Backup? {
        let dir = root.appendingPathComponent(key, isDirectory: true)
        guard let meta = readMeta(in: dir) else { return nil }
        let payload: URL
        switch location {
        case .outbox:
            payload = dir.appendingPathComponent(meta.bundleName)
        case .destination:
            // No archive name means the sidecar was copied but the archive was
            // not — nothing to restore from, so this is not a backup.
            guard let archiveName = meta.archiveName else { return nil }
            payload = dir.appendingPathComponent(archiveName)
        }
        guard FileManager.default.fileExists(atPath: payload.path) else { return nil }
        return Backup(
            key: key, version: meta.version, bundlePath: payload, location: location,
            savedAt: meta.savedAt, fromPackageInstall: meta.fromPackageInstall)
    }

    /// The current backup for `key`, or nil if none exists.
    ///
    /// The outbox wins when a key exists in both. It is the newer copy by
    /// construction — a transfer only clears it after the destination copy is
    /// complete — and restoring from it is a local directory copy rather than
    /// unpacking an archive across a cable.
    public static func backup(forKey key: String) -> Backup? {
        if let local = backup(forKey: key, in: outboxRoot, location: .outbox) { return local }
        guard let destination = reachableDestinationRoot else { return nil }
        return backup(forKey: key, in: destination, location: .destination)
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
        // Per-invocation, not per-key. Keying the scratch directory on the app
        // alone meant two restores of the same key shared one working directory,
        // and since each one deletes it on the way in and again on the way out,
        // the second would pull the tree out from under the first mid-copy. The
        // `defer` below then removes only this run's directory, so a concurrent
        // restore is no longer able to destroy it.
        let scratch = fm.temporaryDirectory
            .appendingPathComponent(
                "DuoUpdater-rollback-\(key)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { forceRemove(scratch) }

        let staged: URL
        switch backup.location {
        case .outbox:
            staged = scratch.appendingPathComponent(backup.bundlePath.lastPathComponent)
            guard runDitto(from: backup.bundlePath, to: staged) else {
                throw BackupError.copyFailed(backup.bundlePath.path)
            }
        case .destination:
            staged = try unpackFromDestination(backup, key: key, into: scratch)
        }
        // Integrity gate before swapping a backup over the live app: a stored copy
        // that has changed since we wrote it has been corrupted or tampered with,
        // and swapping it in would brick the live app. Hard-fail rather than
        // restore it — a rollback that knowingly installs a damaged bundle is worse
        // than leaving the (working) current app in place. See `integrityHolds` for
        // why this asks about our own copy rather than the vendor's signature.
        let metaRoot = backup.location == .outbox
            ? outboxRoot : backup.bundlePath.deletingLastPathComponent().deletingLastPathComponent()
        guard integrityHolds(for: key, in: metaRoot, staged: staged) else {
            throw BackupError.backupCorrupted(backup.bundlePath.lastPathComponent)
        }
        try InPlaceSwap.replace(newApp: staged, over: target)
        return backup.version
    }

    /// Unpack a destination archive into `scratch`, returning the bundle.
    ///
    /// The digest is checked **before** unpacking rather than after. It is the
    /// only integrity question that can be asked about bytes sitting on a
    /// foreign filesystem, it costs one sequential read of a file we are about
    /// to read anyway, and failing here means the manifest gate downstream never
    /// has to explain a difference that a truncated transfer already accounts for.
    private static func unpackFromDestination(
        _ backup: Backup, key: String, into scratch: URL
    ) throws -> URL {
        let dir = backup.bundlePath.deletingLastPathComponent()
        guard let meta = readMeta(in: dir) else { throw BackupError.noBackup(key) }

        if let expected = meta.archiveSHA256 {
            let actual = try BundleArchive.sha256(of: backup.bundlePath)
            guard actual == expected else {
                Log.install.error(
                    "rollback: the archive for \(key, privacy: .public) on the backup disk does not match what was written — refusing to restore")
                throw BackupError.backupCorrupted(backup.bundlePath.lastPathComponent)
            }
        }

        let staged = scratch.appendingPathComponent(meta.bundleName)
        try BundleArchive.extract(archive: backup.bundlePath, into: staged)
        return staged
    }

    // MARK: - Verification

    /// What a stored backup would do if it were needed right now.
    ///
    /// The distinction between the cases is the whole point. "Not verifiable" is
    /// not a pass and not a failure — a backup written before fingerprints were
    /// recorded genuinely cannot be checked, and reporting it as fine would be a
    /// reassurance nobody earned. Only ``mismatch`` means the bytes changed.
    public struct VerifyOutcome: Sendable, Equatable {
        public enum Result: Sendable, Equatable {
            case ok
            /// The stored copy is not what was stored.
            case mismatch(String)
            /// Nothing to compare against.
            case unverifiable(String)
            /// The copy could not be read at all.
            case unreadable(String)

            public var isFailure: Bool {
                if case .mismatch = self { return true }
                if case .unreadable = self { return true }
                return false
            }
        }
        public let key: String
        public let name: String
        public let version: String?
        public let location: Backup.Location
        public let result: Result
    }

    /// Check every stored backup without restoring anything.
    ///
    /// Each store is asked the strongest question that is cheap there. An outbox
    /// copy is a bundle on APFS, so its recorded manifest is recomputed in place —
    /// the same comparison a rollback would make, at the same fidelity, for the
    /// cost of a tree walk. A destination copy is one archive on a filesystem we
    /// deliberately assume nothing about, so the digest recorded when it was
    /// written is recomputed: that proves the bytes on the disk are the bytes we
    /// sent, which is the only question those bytes can answer without unpacking.
    ///
    /// `deep` closes the remaining gap on the destination by extracting the
    /// archive to a scratch directory and comparing the manifest — exactly what a
    /// restore does, without the swap. It needs room for a full bundle and takes
    /// as long as a rollback would, which is why it is not the default.
    public static func verify(deep: Bool = false) -> [VerifyOutcome] {
        var out = verify(in: outboxRoot, location: .outbox, deep: deep)
        if let destination = reachableDestinationRoot {
            out += verify(in: destination, location: .destination, deep: deep)
        }
        return out
    }

    private static func verify(
        in root: URL, location: Backup.Location, deep: Bool
    ) -> [VerifyOutcome] {
        let fm = FileManager.default
        return storedKeys(in: root).compactMap { key -> VerifyOutcome? in
            let dir = root.appendingPathComponent(key, isDirectory: true)
            // No sidecar is not a damaged backup, it is not a backup — the sweeper
            // deals with those, and reporting them here would put remnants in a
            // list whose every other row is something the user can act on.
            guard let meta = readMeta(in: dir) else { return nil }
            func outcome(_ result: VerifyOutcome.Result) -> VerifyOutcome {
                VerifyOutcome(
                    key: key, name: (meta.bundleName as NSString).deletingPathExtension,
                    version: meta.version, location: location, result: result)
            }

            switch location {
            case .outbox:
                let bundle = dir.appendingPathComponent(meta.bundleName)
                guard fm.fileExists(atPath: bundle.path) else {
                    return outcome(.unreadable("the stored bundle is gone"))
                }
                guard let recorded = meta.manifest else {
                    return outcome(.unverifiable("taken before fingerprints were recorded"))
                }
                guard let current = BackupManifest.compute(for: bundle) else {
                    return outcome(.unreadable("the stored bundle could not be fingerprinted"))
                }
                guard current == recorded else {
                    return outcome(.mismatch(
                        "\(current.fileCount) files now, \(recorded.fileCount) when it was stored"))
                }
                return outcome(.ok)

            case .destination:
                guard let archiveName = meta.archiveName else {
                    return outcome(.unreadable("the sidecar names no archive"))
                }
                let archive = dir.appendingPathComponent(archiveName)
                guard fm.fileExists(atPath: archive.path) else {
                    return outcome(.unreadable("the archive is gone"))
                }
                guard let expected = meta.archiveSHA256 else {
                    return outcome(.unverifiable("moved before digests were recorded"))
                }
                guard let actual = try? BundleArchive.sha256(of: archive) else {
                    return outcome(.unreadable("the archive could not be read"))
                }
                guard actual == expected else {
                    return outcome(.mismatch("the archive is not the one that was written"))
                }
                guard deep else { return outcome(.ok) }
                return outcome(deepCheck(archive: archive, meta: meta))
            }
        }
    }

    private static func deepCheck(archive: URL, meta: Meta) -> VerifyOutcome.Result {
        guard let recorded = meta.manifest else {
            return .unverifiable("taken before fingerprints were recorded")
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent(
            "DuoUpdater-verify-\(UUID().uuidString)", isDirectory: true)
        defer { forceRemove(scratch) }
        let staged = scratch.appendingPathComponent(meta.bundleName)
        do {
            try BundleArchive.extract(archive: archive, into: staged)
        } catch {
            return .unreadable("the archive would not unpack — "
                + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
        }
        guard let current = BackupManifest.compute(for: staged) else {
            return .unreadable("the unpacked bundle could not be fingerprinted")
        }
        guard current == recorded else {
            return .mismatch(
                "\(current.fileCount) files unpacked, \(recorded.fileCount) when it was stored")
        }
        return .ok
    }

    /// Whether the staged copy is still what we stored.
    ///
    /// Prefers the manifest recorded at save time, which asks the question a
    /// gate on a *backup* should ask. Falls back to the vendor code signature
    /// only for backups written before manifests existed — that gate refuses
    /// apps which break their own seal by writing state inside their bundle
    /// (ToDesk, EasyConnect), so a faithful copy of what the user was running
    /// was rejected as "corrupted".
    /// `root` is whichever store the backup came out of. The recorded manifest
    /// and the recomputation are both taken on APFS — the sidecar's was computed
    /// on the outbox copy, and `staged` is in the temporary directory — so this
    /// comparison never straddles two filesystems no matter where the bytes were
    /// parked in between. That is what keeps a backup on an exFAT stick or an SMB
    /// share restorable rather than only apparently stored.
    private static func integrityHolds(for key: String, in root: URL, staged: URL) -> Bool {
        let recorded = readMeta(in: root.appendingPathComponent(key, isDirectory: true))?.manifest

        if let recorded {
            guard let current = BackupManifest.compute(for: staged) else {
                Log.install.error(
                    "rollback: could not fingerprint the staged backup for \(key, privacy: .public) — refusing to restore")
                return false
            }
            guard current == recorded else {
                Log.install.error(
                    "rollback: backup for \(key, privacy: .public) does not match what was stored (\(current.fileCount, privacy: .public) files now, \(recorded.fileCount, privacy: .public) then) — refusing to restore")
                return false
            }
            return true
        }

        guard backupSignatureLooksValid(staged) else {
            Log.install.error(
                "rollback: backup for \(key, privacy: .public) has no stored fingerprint and failed signature validation — refusing to restore")
            return false
        }
        return true
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

    /// Keys that have a directory under `root`, hidden entries skipped so the
    /// `.staging-` scratch and the volume marker never read as backups.
    private static func storedKeys(in root: URL) -> [String] {
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return dirs.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }.map(\.lastPathComponent)
    }

    /// Every current backup, keyed by app key — one scan of each store.
    /// Lets the UI light up rollback affordances without a stat per app.
    ///
    /// The union matters more than it looks. A read path that saw only the
    /// destination would report "no backups" whenever the disk was detached,
    /// which is indistinguishable, on screen, from having none — and the copies
    /// waiting in the outbox to be transferred would be invisible precisely
    /// while they were the only ones present.
    public static func allBackups() -> [String: Backup] {
        var out: [String: Backup] = [:]
        if let destination = reachableDestinationRoot {
            for key in storedKeys(in: destination) {
                out[key] = backup(forKey: key, in: destination, location: .destination)
            }
        }
        // Outbox second so it wins a collision: it is the newer copy, and
        // restoring from it does not go over the cable.
        for key in storedKeys(in: outboxRoot) {
            if let local = backup(forKey: key, in: outboxRoot, location: .outbox) {
                out[key] = local
            }
        }
        return out.compactMapValues { $0 }
    }

    /// Drop the backup for `key` (e.g. the user dismissed it).
    ///
    /// Removes it from both stores. Dropping only one would leave the other to
    /// reappear at the next refresh, which reads as the deletion having silently
    /// failed.
    public static func remove(forKey key: String) {
        let fm = FileManager.default
        forceRemove(outboxRoot.appendingPathComponent(key, isDirectory: true))
        if let destination = reachableDestinationRoot {
            forceRemove(destination.appendingPathComponent(key, isDirectory: true))
        }
    }

    /// One stored backup, described for a UI that has to let someone choose which
    /// ones to delete: what app it belongs to, when it was taken, how much disk it
    /// is holding, and whether it can still do its job.
    public struct Listing: Sendable, Identifiable, Equatable {
        public let key: String
        public var id: String { key }
        public let name: String
        /// What the backup would restore — the version that was replaced.
        public let version: String?
        /// What is installed at that path right now, so the row can show the update
        /// this backup undoes (`2.0.11 → 2.0.14`). Nil when the app is gone, or when
        /// its plist can't be read. Deciding whether a rollback point still matters
        /// is mostly a question of how far behind it now is.
        public let currentVersion: String?
        public let savedAt: Date?
        public let sizeBytes: Int64
        /// The backed-up bundle itself, for an icon. Present even when the original
        /// app is long gone, which is exactly when a name alone identifies least.
        public let bundlePath: URL?
        /// False when the original app is gone — nothing left to restore onto.
        public let appStillInstalled: Bool
        /// False when the sidecar is missing or unreadable: without it `restore`
        /// has no target path, so the bytes are unusable. Listing these anyway is
        /// the point — they are invisible to every other surface, which is how one
        /// grew to 272 MB unnoticed, counted in the total but impossible to remove.
        public let isRestorable: Bool
        /// Which store this row came out of, so a sheet about reclaiming space
        /// can say *whose* space — the boot volume's or the backup disk's.
        public let location: Backup.Location

        public init(
            key: String, name: String, version: String?, currentVersion: String?,
            savedAt: Date?, sizeBytes: Int64, bundlePath: URL?, appStillInstalled: Bool,
            isRestorable: Bool, location: Backup.Location = .outbox
        ) {
            self.key = key
            self.name = name
            self.version = version
            self.currentVersion = currentVersion
            self.savedAt = savedAt
            self.sizeBytes = sizeBytes
            self.bundlePath = bundlePath
            self.appStillInstalled = appStillInstalled
            self.isRestorable = isRestorable
            self.location = location
        }
    }

    /// `CFBundleShortVersionString` of the app currently at `path`, or nil if it
    /// isn't there or has no readable plist.
    private static func installedShortVersion(atPath path: String) -> String? {
        let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    /// Every stored backup with its size, newest first. Walks each directory to
    /// measure it, so call it off the main thread.
    ///
    /// Both stores are listed, and a key present in both appears **twice** — one
    /// row per copy. That is deliberate for a sheet whose job is reclaiming
    /// space: a backup mid-transfer really is occupying both disks, and merging
    /// the rows would hide half of what deleting it would free.
    public static func listing() -> [Listing] {
        var out = listing(in: outboxRoot, location: .outbox)
        if let destination = reachableDestinationRoot {
            out += listing(in: destination, location: .destination)
        }
        // Undated (sidecar-less) entries sort last: they are the ones to clear out,
        // not the ones to reason about.
        return out.sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
    }

    private static func listing(in root: URL, location: Backup.Location) -> [Listing] {
        let fm = FileManager.default
        var out: [Listing] = []
        for key in storedKeys(in: root) {
            let dir = root.appendingPathComponent(key, isDirectory: true)
            let meta = readMeta(in: dir)
            // The payload is a directory in the outbox and a single file on the
            // destination, so what stands in for "the bundle" differs; on the
            // destination there is no `.app` to take an icon from.
            let payload: URL? = location == .outbox
                ? (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                    .first { $0.pathExtension == "app" }
                : meta?.archiveName.map { dir.appendingPathComponent($0) }
            out.append(Listing(
                key: key,
                name: meta?.bundleName ?? payload?.lastPathComponent ?? key,
                version: meta?.version,
                currentVersion: meta.flatMap { installedShortVersion(atPath: $0.originalPath) },
                savedAt: meta?.savedAt,
                sizeBytes: directorySize(dir),
                bundlePath: payload,
                appStillInstalled: meta.map { fm.fileExists(atPath: $0.originalPath) } ?? false,
                isRestorable: meta != nil,
                location: location))
        }
        return out
    }

    // MARK: - Cleanup

    /// Removes backups whose original app no longer exists at the recorded path —
    /// uninstalled, moved, or replaced under a fresh path-scoped key. Retention
    /// per key is already 1 (`save` supersedes the prior backup atomically), so
    /// the only unbounded growth left is these orphans: nothing ever revisits a
    /// key once its app is gone, and a large app bundle backup left behind is
    /// pure disk waste with no path left to restore onto. Returns the bytes freed.
    /// Prunes both stores, and simply skips the destination when the disk is not
    /// connected — a detached disk is not an orphan, and deleting on the strength
    /// of "I could not see it" is how a backup disk gets emptied by being left at
    /// the office.
    ///
    /// Note that "nothing to prune" and "could not look at the destination" both
    /// return zero. Nothing distinguishes them today because nothing asks; the
    /// caller discards this value entirely. Give this a richer return type when
    /// a surface exists that would say something different about the two.
    @discardableResult
    public static func pruneOrphans() -> Int64 {
        var freed = pruneOrphans(in: outboxRoot)
        if let destination = reachableDestinationRoot {
            freed += pruneOrphans(in: destination)
        }
        return freed
    }

    private static func pruneOrphans(in root: URL) -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        for key in storedKeys(in: root) {
            let dir = root.appendingPathComponent(key, isDirectory: true)
            guard let meta = readMeta(in: dir) else { continue }
            guard !fm.fileExists(atPath: meta.originalPath) else { continue }
            freed += directorySize(dir)
            forceRemove(dir)
        }
        return freed
    }

    /// Total on-disk size of every stored backup, for display in Settings.
    ///
    /// Both stores together. Settings shows them apart — the point of moving the
    /// store is to watch one number shrink — but the sum is what the existing
    /// callers ask for, so ``storeSizes()`` answers the split question.
    public static func totalSize() -> Int64 {
        let sizes = storeSizes()
        return sizes.outbox + sizes.destination
    }

    /// On-disk size of each store separately. `destination` is zero when the
    /// disk is not connected, which is indistinguishable from "empty" and should
    /// be presented alongside ``availability()`` rather than on its own.
    public static func storeSizes() -> (outbox: Int64, destination: Int64) {
        (storeSize(of: outboxRoot),
         reachableDestinationRoot.map(storeSize(of:)) ?? 0)
    }

    private static func storeSize(of root: URL) -> Int64 {
        guard let dirs = try? FileManager.default.contentsOfDirectory(
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
        case payloadUnreadable(String)
        case destinationUnavailable(String)
        case destinationIsADifferentDisk(String)
        case destinationNotWritable(String)

        public var errorDescription: String? {
            switch self {
            case .destinationUnavailable(let name):
                return "The backup disk “\(name)” isn’t connected."
            case .destinationIsADifferentDisk(let path):
                return "A different disk is mounted at “\(path)”, so it was left alone."
            case .destinationNotWritable(let path):
                return "“\(path)” can’t be written to."
            case .copyFailed(let path):
                return "Could not copy the app bundle at “\(path)”."
            case .noBackup(let key):
                return "There is no backup to roll back to for “\(key)”."
            case .payloadUnreadable(let path):
                return "“\(path)” is part of the app's signed payload and is not readable "
                    + "by you, so no rollback point could be stored."
            case .backupCorrupted(let name):
                return "The backup for “\(name)” no longer matches what was stored and was not restored."
            }
        }
    }

    /// Remove something inside our own store, including when a file in it is
    /// flagged immutable.
    ///
    /// `ditto` faithfully copies BSD file flags, which is what we want of a
    /// backup — and it means a `uchg` file inside an app bundle comes along into
    /// the store. `removeItem` then fails with EPERM on that one file and, with
    /// `try?`, fails silently: the backup stays, the sweeper appears to run, the
    /// space is never reclaimed, and Clean Up reports success while deleting
    /// nothing. Found on a real machine, where ToDesk's `advInfo.json` had been
    /// locked by hand and every ToDesk backup had become undeletable.
    ///
    /// Clearing the flag is safe **here specifically** because the target is
    /// always a copy this store made, never the user's own file — and only the
    /// user-settable flags are touched, since the system ones need root and
    /// their presence is a genuine reason to stop. A restore is unaffected: it
    /// unpacks its own copy, flags and all.
    @discardableResult
    private static func forceRemove(_ url: URL) -> Bool {
        let fm = FileManager.default
        do { try fm.removeItem(at: url); return true } catch {}
        guard fm.fileExists(atPath: url.path) else { return true }

        clearUserFlags(at: url)
        do {
            try fm.removeItem(at: url)
            return true
        } catch {
            Log.install.error(
                "backup: could not remove \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Clear `uchg`/`uappnd` from `url` and everything under it.
    ///
    /// `lstat`/`lchflags` rather than the follow-the-link pair: a symlink inside
    /// a bundle must have its own flags cleared, and following one would let a
    /// link reach outside the store.
    private static func clearUserFlags(at url: URL) {
        let clearable = UInt32(UF_IMMUTABLE) | UInt32(UF_APPEND)
        func clear(_ path: String) {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_flags & clearable != 0 else { return }
            _ = lchflags(path, info.st_flags & ~clearable)
        }
        clear(url.path)
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil, options: [], errorHandler: nil)
        else { return }
        for case let child as URL in walker { clear(child.path) }
    }

    /// `ditto src dst`, returning true on success. Faithfully duplicates a bundle
    /// including its code signature, unlike `FileManager.copyItem`.
    private static func runDitto(from src: URL, to dst: URL) -> Bool {
        forceRemove(dst)
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
