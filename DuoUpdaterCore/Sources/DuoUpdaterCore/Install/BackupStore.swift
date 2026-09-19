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

    /// Test seam for the readable-but-not-active disks, bound like the two
    /// above. Production never binds it and reads ``configure(_:known:)``'s
    /// value instead.
    @TaskLocal public static var knownDisksOverride: [BackupDestination]?

    /// Test seam for the compression setting, bound like the three above.
    /// Production never binds it and reads ``configure(compression:)``'s value.
    @TaskLocal public static var compressionOverride: BundleArchive.Compression?

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
    private nonisolated(unsafe) static var configuredKnownDisks: [BackupDestination] = []
    private nonisolated(unsafe) static var configuredCompression = UpdateSettings.backupCompressionDefault
    private static let destinationLock = NSLock()

    /// Point the store at a destination. Called once per process — the app at
    /// launch, `duo` in `main` — so no command can forget and silently use a
    /// different store than the one the user configured.
    ///
    /// `known` is every disk the user has ever adopted, which is a wider set than
    /// the one being written to: backups already sitting on a disk stay readable
    /// whenever it is plugged in, whether or not it is the disk new backups go
    /// to. Without that, switching disks would make a full set of rollback points
    /// vanish from every list while remaining on disk forever — invisible to the
    /// clean-up sheet that exists to reclaim them, and never superseded, because
    /// retention only ever replaces a backup within the store it is in.
    public static func configure(
        _ destination: BackupDestination, known: [BackupDestination] = []
    ) {
        destinationLock.lock()
        defer { destinationLock.unlock() }
        configuredDestination = destination
        configuredKnownDisks = known
    }

    /// How hard to squeeze a bundle on its way to the disk, as the user has it
    /// set. Told to the store the same way the destination is — on change and at
    /// launch — because the queue that does the app's transfers asks nobody:
    /// it takes ``transferToDestination(forKey:compression:)``'s default, and
    /// while that default was a constant the Settings control changed nothing
    /// the app did. `duo backups sync` passes its own and always did, so the two
    /// wrote the same store two different ways.
    public static func configure(compression: BundleArchive.Compression) {
        destinationLock.lock()
        defer { destinationLock.unlock() }
        configuredCompression = compression
    }

    public static var compression: BundleArchive.Compression {
        if let compressionOverride { return compressionOverride }
        destinationLock.lock()
        defer { destinationLock.unlock() }
        return configuredCompression
    }

    public static var destination: BackupDestination {
        if let destinationOverride { return destinationOverride }
        destinationLock.lock()
        defer { destinationLock.unlock() }
        return configuredDestination
    }

    /// Every disk that may be read from, active or not.
    public static var knownDisks: [BackupDestination] {
        if let knownDisksOverride { return knownDisksOverride }
        // Read through `destination`, not `configuredDestination`: a test that
        // binds only the destination seam must still see that disk here, or its
        // backups become unreadable while the test believes it configured one.
        let active = destination
        destinationLock.lock()
        defer { destinationLock.unlock() }
        // The active destination is included even when nothing registered a list:
        // that is the state of every installation configured before this existed,
        // and reading it as "no disks" would hide their backups.
        guard active.kind == .external, active.path?.isEmpty == false else {
            return configuredKnownDisks
        }
        if configuredKnownDisks.contains(where: { $0.path == active.path }) {
            return configuredKnownDisks
        }
        return [active] + configuredKnownDisks
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

    /// The **active** destination directory when it happens to be reachable,
    /// else nil. For the write-side paths — a transfer, a sweep of the scratch a
    /// transfer left, an automatic prune — which must act on the one store this
    /// Mac owns and no other.
    ///
    /// Read paths use ``reachableStores()`` instead. The distinction is the
    /// safety rule of this whole feature and is worth stating where it is
    /// easiest to get wrong: a disk that is merely *readable* may be another
    /// Mac's, holding backups for apps that were never installed here. Pruning
    /// across it would delete them all, each one correctly identified as an
    /// orphan and each one someone else's only rollback point.
    static var reachableDestinationRoot: URL? {
        if case .ready(let url) = availability() { return url }
        return nil
    }

    /// One store a backup can be read out of.
    ///
    /// Carries the disk's identity and name so a listing can say *which* disk a
    /// backup is on. That question did not exist while there was one destination
    /// and `Backup.Location` answered it by implication; with several readable at
    /// once, "on the backup disk" names nothing.
    public struct Store: Sendable, Equatable, Identifiable {
        /// The directory holding one subdirectory per backed-up app.
        public let root: URL
        /// What a stored copy looks like here: a bundle in the outbox, an
        /// archive on a disk. Not *which* store — that is ``identity``.
        public let location: Backup.Location
        /// The marker identity of the disk. Nil for the outbox.
        public let identity: String?
        /// The disk's name, for UI copy. Nil for the outbox, which every surface
        /// names in its own words ("On this Mac").
        public let volumeName: String?
        /// Whether new backups are written here.
        public let isActive: Bool

        public var id: String { identity ?? root.path }
    }

    /// The store on this Mac. Always present, always readable, always written to
    /// first.
    public static var outboxStore: Store {
        Store(root: outboxRoot, location: .outbox, identity: nil, volumeName: nil,
              isActive: destination.kind != .external)
    }

    /// Every store readable right now: this Mac, then each known disk that is
    /// mounted and carries the marker we recorded for it.
    ///
    /// The outbox comes first so a caller that stops at the first hit prefers the
    /// local copy — it is the newer one by construction (a transfer clears it
    /// only after the disk's copy is complete) and restoring from it does not go
    /// over a cable.
    public static func reachableStores() -> [Store] {
        [outboxStore] + reachableDisks()
    }

    /// The active destination as a store, given the root ``destinationRoot()``
    /// already resolved. Only the write paths have that root in hand.
    private static func activeStore(root: URL) -> Store {
        Store(root: root, location: .destination, identity: destination.identity,
              volumeName: destination.volumeName, isActive: true)
    }

    /// The known disks that are reachable right now, the active one first.
    ///
    /// Each is checked with the same ``availability(_:)`` the active destination
    /// goes through, so a path whose marker is missing or belongs to a different
    /// disk is skipped here exactly as it is refused there. Nothing is created:
    /// a disk that is not plugged in is simply absent from the list.
    public static func reachableDisks() -> [Store] {
        let active = destination
        var out: [Store] = []
        var seen = Set<String>()
        for disk in knownDisks {
            guard case .ready(let url) = availability(disk) else { continue }
            guard seen.insert(disk.identity ?? url.standardizedFileURL.path).inserted
            else { continue }
            out.append(Store(
                root: url, location: .destination,
                identity: disk.identity, volumeName: disk.volumeName,
                isActive: active.kind == .external && active.path == disk.path))
        }
        return out
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
        /// The build the backed-up bundle carried, when it had one. Nil on
        /// backups taken before this was recorded.
        public let buildVersion: String?
        /// Both halves, for anything asking whether the installed copy has
        /// actually moved on from this backup. A marketing-only comparison says
        /// "no" for every app that keeps one marketing version across builds,
        /// which hid the Rollback row after a real update.
        public var versionSide: VersionSide {
            VersionSide(marketing: version, build: buildVersion)
        }
        /// Where the stored copy lives: the `.app` directory for an outbox
        /// backup, the archive file for one on the destination. Read `location`
        /// before assuming which — a destination copy is a single file, so
        /// walking it as a directory yields nothing rather than failing.
        public let bundlePath: URL
        /// Which store this copy was read out of — this Mac, or a named disk.
        public let store: Store
        /// What the stored copy looks like. Derived rather than stored a second
        /// time: a store has exactly one shape, and two fields that could
        /// disagree is one more state than this type has.
        public var location: Location { store.location }
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
        /// Whether the update this backup was taken for was applied through the
        /// App Store.
        ///
        /// It matters at restore time for a reason the other routes don't have: a
        /// rollback here undoes the bundle but not the store's opinion of it. The
        /// update reappears in App Store's Updates list immediately, and — with
        /// automatic app updates on, which is the default — the store re-applies
        /// it on its own, silently undoing the rollback. Worth saying while the
        /// user is deciding. Nil for backups written before this was recorded.
        public let fromAppStore: Bool?
        /// Files the copy deliberately left out, relative to the bundle root
        /// (`Contents/mmkv.default`): unreadable and outside the code seal, so the
        /// app's own runtime state rather than payload. Empty when nothing was
        /// omitted or the backup predates recording it. A bundle diff against
        /// this backup needs it, or those files read as added by the update.
        public let omittedFiles: [String]
        /// What the stored copy hashed to when it was written — the manifest
        /// digest, surfaced so callers can name *this* copy rather than the key,
        /// which outlives every generation ever stored under it.
        ///
        /// Nil for a backup written before manifests existed, and for one whose
        /// bundle held a file we could not read: `BackupManifest.compute` answers
        /// nil for the whole copy in that case, and a copy we never fingerprinted
        /// is one nothing may be cached against. See ``BackupFactsLibrary``.
        public let fingerprint: String?
    }

    /// JSON sidecar persisted next to a backed-up bundle.
    private struct Meta: Codable {
        let version: String?
        /// Optional so sidecars written before it decode unchanged; nil leaves
        /// the comparison marketing-only, i.e. exactly what it was.
        var buildVersion: String?
        let bundleID: String?
        let originalPath: String
        let bundleName: String
        let savedAt: Date
        /// Optional so sidecars written before this field decode unchanged —
        /// a stricter decoder would make every existing backup unreadable, and
        /// `backup(forKey:)` returns nil without a readable sidecar.
        var fromPackageInstall: Bool?
        /// Optional for the same reason as `fromPackageInstall`.
        var fromAppStore: Bool?
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
        /// Set when the user chose a backup disk and said to leave this copy
        /// where it is. Absent means "move it when there is somewhere to move
        /// it to", which is what every backup means by default.
        ///
        /// Note what this is **not**: a flag written at save time recording
        /// whether a destination existed then. That was tried and was wrong in
        /// the case that matters — see ``pendingTransferKeys()``. This is
        /// written only when someone is looking at a sheet naming these exact
        /// backups and presses the button that says to leave them.
        var keepOnThisMac: Bool?
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
        appPath: URL, key: String, version: String?, buildVersion: String? = nil,
        bundleID: String?,
        fromPackageInstall: Bool = false, fromAppStore: Bool = false
    ) async throws -> Backup {
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
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Unique per attempt. It used to be one fixed name per app, on the reasoning
        // that a leftover from a crashed attempt would be cleared by the next run —
        // which holds only while the leftover is ours to delete. ToDesk's was not:
        // a crash mid-copy left a half-written bundle whose files a package install
        // had made root-owned, the `try?` removal in front of it failed silently,
        // `createDirectory(withIntermediateDirectories:)` then succeeded *because
        // the directory already existed*, and ditto copied into a destination that
        // still held those files:
        //
        //     ditto: …/.staging-com.youqu.todesk.mac-…/ToDesk.app/Contents/advInfo.json:
        //            Operation not permitted
        //
        // So one crash permanently disabled backups for that app, and every update
        // since had said only "proceeding without a rollback point". A name nothing
        // else can be sitting on removes that failure mode entirely: whatever is
        // stranded in the store may waste space, but it can no longer poison the
        // next attempt.
        let staging = root.appendingPathComponent(
            "\(stagingPrefix(key: key))-\(UUID().uuidString)", isDirectory: true)
        await sweepStagingLeftovers(in: root, key: key)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)

        let name = appPath.lastPathComponent
        let staged = staging.appendingPathComponent(name)

        // An app that keeps runtime state inside its own bundle (ToDesk writes an
        // mmkv database and log caches under Contents/, root-owned) leaves files
        // we cannot read. Those are not payload — the seal never covered them and
        // the app rewrites them — so the copy may skip them. A file the seal DOES
        // cover is payload, and a bundle without it is broken, so there is
        // nothing worth storing.
        //
        // Walking the bundle is blocking disk work, so it — and the other two
        // whole-bundle walks below — goes to Dispatch. The `ditto`/`chflags` in
        // between are awaited through `ChildProcess` and need no hop; until they
        // were, this whole function ran inside one `offCooperativePool` hop in
        // `InstallCoordinator.backUp`.
        let unreadable = await offCooperativePool(qos: .userInitiated) {
            BackupManifest.unreadableFiles(in: appPath)
        }
        guard unreadable.sealed.isEmpty else {
            Log.install.error(
                "backup: \(name, privacy: .public) has \(unreadable.sealed.count, privacy: .public) sealed file(s) we cannot read, first \(unreadable.sealed.first ?? "?", privacy: .public) — that is payload, so there is nothing worth storing")
            await removeItemOffCooperativePool(at: staging)
            throw BackupError.payloadUnreadable(unreadable.sealed.first ?? appPath.path)
        }

        // `ditto` preserves the bundle's symlinks, xattrs, and (importantly) its
        // code signature exactly — a plain copy can mangle them. It reports one
        // status for the whole run, so a non-zero exit is only acceptable once we
        // have confirmed the ONLY things it dropped are the ones we meant to drop.
        let ditto = await runDitto(from: appPath, to: staged)
        if !ditto.ok {
            Log.install.error(
                "backup: ditto exited \(ditto.status, privacy: .public) copying \(name, privacy: .public) — \(ditto.stderrTail, privacy: .public)")
            // No expected omissions means the copy failed for some other reason
            // (a missing source, a full disk) and there is nothing to forgive.
            // Without this, a source that does not exist produced an empty copy
            // that passed the omission check and got stored as a backup.
            guard !unreadable.unsealed.isEmpty else {
                Log.install.error(
                    "backup: nothing about \(name, privacy: .public) was expected to be skipped, so the copy failed for its own reason")
                await removeItemOffCooperativePool(at: staging)
                throw BackupError.copyFailed(appPath.path)
            }
            let omitted = unreadable.unsealed
            let unexpected = await offCooperativePool(qos: .userInitiated) {
                BackupManifest.unexpectedOmissions(
                    source: appPath, copy: staged, expected: omitted)
            }
            guard unexpected.isEmpty else {
                Log.install.error(
                    "backup: copy of \(name, privacy: .public) lost \(unexpected.count, privacy: .public) file(s) it should have kept")
                await removeItemOffCooperativePool(at: staging)
                throw BackupError.copyFailed(appPath.path)
            }
        }

        // Our copy from here on, so it must not inherit a flag that would stop us
        // ever replacing or removing it — see `clearUserImmutableFlags`. Done before
        // the fingerprint so the manifest describes what is actually stored.
        if await !clearUserImmutableFlags(under: staged) {
            Log.install.error(
                "backup: could not clear immutable flags on the copy of \(name, privacy: .public) — retention may not be able to replace it later")
        }

        let savedAt = Date()
        // Fingerprinted from the staged copy, not the source: what restore has
        // to be able to trust is that the bytes in the store are the ones that
        // came out of this copy, and hashing the source would certify something
        // we did not keep.
        let manifest = await offCooperativePool(qos: .userInitiated) {
            BackupManifest.compute(for: staged)
        }
        if manifest == nil {
            Log.install.error(
                "backup: could not fingerprint \(name, privacy: .public) — restoring it will fall back to the signature gate")
        }
        let meta = Meta(
            version: version, buildVersion: buildVersion, bundleID: bundleID,
            originalPath: appPath.path, bundleName: name, savedAt: savedAt,
            fromPackageInstall: fromPackageInstall, fromAppStore: fromAppStore,
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
            Log.install.error(
                "backup: the copy of \(name, privacy: .public) is complete but its sidecar would not write — discarding it, since every read path keys off the sidecar")
            await removeItemOffCooperativePool(at: staging)
            throw BackupError.copyFailed(appPath.path)
        }

        // New backup is complete in `staging`; now replace the old one atomically (a
        // same-volume rename, so the swap window is a single near-instant operation
        // rather than the multi-second copy above).
        let superseding = fm.fileExists(atPath: dir.path)
        if superseding {
            // The copy being superseded has to be deletable for the exchange to
            // finish. One written before we started stripping `uchg` — or by any
            // path where stripping failed — still carries it, and `replaceItemAt`
            // cannot remove it. Clearing it here is what lets retention ever get
            // past a single poisoned generation.
            await clearUserImmutableFlags(under: dir)
        }
        // The exchange itself is near-instant, but `replaceItemAt` then deletes the
        // generation it displaced — a whole app bundle — so it goes to Dispatch.
        // Only the exchange: `backup(forKey:)` in the failure branch reads `root`,
        // which honours a task-local a Dispatch thread does not have.
        let exchangeError: (any Error)? = await offCooperativePool(qos: .userInitiated) {
            do {
                if superseding {
                    _ = try FileManager.default.replaceItemAt(dir, withItemAt: staging)
                } else {
                    try FileManager.default.moveItem(at: staging, to: dir)
                }
                return nil
            } catch {
                return error
            }
        }
        if let error = exchangeError {
            // `replaceItemAt` can put the new item in place and *then* fail removing
            // the one it displaced. Reporting that as a failed backup is worse than
            // wrong: it tells the user there is no rollback point while a complete,
            // fingerprinted one sits in the store, and the update proceeds as though
            // it were unprotected. Ask what is actually on disk instead of inferring
            // it from the throw.
            if let landed = backup(forKey: key), landed.savedAt == savedAt {
                Log.install.error(
                    "backup: \(name, privacy: .public) is stored and usable, but the copy it replaced would not delete — \(error.localizedDescription, privacy: .public)")
                return landed
            }
            Log.install.error(
                "backup: \(name, privacy: .public) copied and fingerprinted, but swapping it into place failed — \(error.localizedDescription, privacy: .public)")
            await removeItemOffCooperativePool(at: staging)
            throw BackupError.copyFailed(appPath.path)
        }
        let dest = dir.appendingPathComponent(name)
        // Migration cleanup: a copy backed up before keys became path-scoped left
        // a dir under the bare bundle-id legacy key. Now that the canonical,
        // path-scoped backup exists (and `keyCandidates` would only ever fall back
        // to that orphan), drop it so retention stays at one copy on disk instead
        // of leaking a whole stale bundle per migrated app.
        let legacy = legacyKey(bundleID: bundleID, path: appPath)
        if legacy != key {
            // Flags cleared: an orphan under the legacy key is by definition an
            // old backup, so it is exactly the generation that can still carry
            // one, and nothing ever revisits that key to try again.
            await removeClearingImmutableFlagsOffPool(
                at: root.appendingPathComponent(legacy, isDirectory: true))
        }
        return Backup(
            key: key, version: version, buildVersion: buildVersion,
            bundlePath: dest, store: outboxStore, savedAt: savedAt,
            fromPackageInstall: fromPackageInstall, fromAppStore: fromAppStore,
            omittedFiles: unreadable.unsealed, fingerprint: manifest?.digest)
    }

    // MARK: - Transfer

    /// What the archive of `bundleName` is called on the disk.
    static func archiveName(forBundle bundleName: String) -> String {
        (bundleName as NSString).deletingPathExtension + ".aar"
    }

    /// How much of the copy in flight for `key` has landed on the disk.
    ///
    /// Read from the size of the file `BundleArchive` is streaming into, which
    /// is the only thing here that knows. Returns nil when nothing is being
    /// written for that key — the copy has not started, has just finished and
    /// been renamed, or there is no disk.
    ///
    /// **Bytes on the disk, not bytes read from the app.** The archive is
    /// compressed as it is written, so this number ends well below the size of
    /// the bundle it came from — which is why it is offered as a figure and
    /// never as a fraction of one. A percentage would need a denominator nobody
    /// has: the compressed size is not known until it is reached.
    public static func transferBytesLanded(forKey key: String) -> Int64? {
        guard let root = try? destinationRoot(),
              let meta = readMeta(in: outboxRoot.appendingPathComponent(key, isDirectory: true))
        else { return nil }
        let archive = root
            .appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent(archiveName(forBundle: meta.bundleName))
        let partial = BundleArchive.partialURL(for: archive)
        return (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Int64)
            ?? nil
    }

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
            guard let meta = readMeta(in: dir), meta.keepOnThisMac != true else { return false }
            return FileManager.default.fileExists(
                atPath: dir.appendingPathComponent(meta.bundleName).path)
        }
    }

    /// How many key directories a store holds, without reading any of them.
    /// A change signal for a UI that has to notice a backup appearing, at the
    /// cost of one directory listing.
    public static func storedKeyCount(in store: Store) -> Int {
        storedKeys(in: store.root).count
    }

    /// Backups held on this Mac by an explicit choice, rather than owed to a disk.
    public static func heldOnThisMacKeys() -> [String] {
        storedKeys(in: outboxRoot).filter { key in
            readMeta(in: outboxRoot.appendingPathComponent(key, isDirectory: true))?
                .keepOnThisMac == true
        }
    }

    /// Mark the outbox copies of `keys` as staying here.
    ///
    /// Takes explicit keys rather than "everything in the outbox now" so the set
    /// the user was shown is the set that is held: a backup written between the
    /// sheet being drawn and the button being pressed belongs to the new
    /// destination, not to a decision made before it existed.
    public static func holdOnThisMac(keys: [String]) {
        setHold(true, on: keys)
    }

    /// Undo ``holdOnThisMac(keys:)``, so the queue owes them again. Passing nil
    /// releases every held backup, which is what "copy everything now" means.
    public static func releaseHold(keys: [String]? = nil) {
        setHold(false, on: keys ?? heldOnThisMacKeys())
    }

    private static func setHold(_ held: Bool, on keys: [String]) {
        for key in keys {
            let dir = outboxRoot.appendingPathComponent(key, isDirectory: true)
            guard var meta = readMeta(in: dir) else { continue }
            // Cleared rather than set to false: absent is already the default
            // reading, and a sidecar that says nothing is one fewer field for a
            // later reader to wonder about.
            meta.keepOnThisMac = held ? true : nil
            guard let data = try? JSONEncoder().encode(meta) else { continue }
            try? data.write(
                to: dir.appendingPathComponent("backup.json"), options: .atomic)
        }
    }

    /// The app's name for a key, for a progress line someone can read.
    /// `com.pais.handy-1551b69e…` is an identity, not a name.
    public static func displayName(forKey key: String) -> String? {
        for store in reachableStores() {
            if let meta = readMeta(in: store.root.appendingPathComponent(key, isDirectory: true)) {
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
        forKey key: String, compression: BundleArchive.Compression? = nil
    ) async throws -> Backup {
        // Resolved per call, not captured once: the setting can change between
        // one transfer and the next, and the queue never passes one.
        let compression = compression ?? Self.compression
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

        let archiveName = archiveName(forBundle: meta.bundleName)
        let archive = targetDir.appendingPathComponent(archiveName)
        // Straight to the destination rather than via a local staging file:
        // `BundleArchive` already writes a `.partial` beside the target and
        // renames it, so the atomicity is the same, and streaming the compressed
        // output over means a transfer never needs a second bundle-sized hole on
        // the boot volume — which is usually the reason the store was moved.
        try await BundleArchive.archive(bundle: bundle, to: archive, compression: compression)

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

        // Record what comparing this backup would otherwise have to unpack the whole
        // archive for. Here rather than in `save` for three reasons that all point
        // the same way: this is the only route a copy ever reaches a disk by, so the
        // cost is paid exactly where it is repaid; the bundle is still sitting on the
        // boot volume and has just been read end to end to compress it, so the walk
        // is local and warm; and a transfer runs on `BackupTransferQueue`, not on the
        // update the user is waiting for. A backup that stays on this Mac gets no
        // entry, which is the case where there was nothing to unpack anyway.
        //
        // Keyed by the manifest digest, which the sidecar above carries over
        // unchanged — so the entry written here is the one the comparison looks up
        // through the copy on the disk. Nil for a backup we never fingerprinted; see
        // `BackupFactsLibrary.Reference`.
        if let digest = meta.manifest?.digest {
            // Resolved here, not inside the hop — see `BackupFactsLibrary.entry(for:)`.
            let entry = BackupFactsLibrary.entry(
                for: BackupFactsLibrary.Reference(key: key, fingerprint: digest))
            let start = ContinuousClock.now
            let recorded = await offCooperativePool(qos: .utility) {
                guard let facts = try? BundleFactsReader.scan(root: bundle) else { return false }
                return BackupFactsLibrary.store(facts, at: entry)
            }
            if recorded {
                Log.install.info(
                    "backup: recorded what \(key, privacy: .public) holds, so comparing it will not unpack the archive — \(String(describing: ContinuousClock.now - start), privacy: .public)")
            } else {
                Log.install.error(
                    "backup: could not record what \(key, privacy: .public) holds — comparing it with the installed app will unpack the archive")
            }
        }

        forceRemove(outboxDir)
        Log.install.info(
            "backup: moved \(key, privacy: .public) to the backup disk (\(bytes ?? 0, privacy: .public) bytes)")
        return Backup(
            key: key, version: meta.version, buildVersion: meta.buildVersion,
            bundlePath: archive, store: activeStore(root: root), savedAt: meta.savedAt,
            fromPackageInstall: meta.fromPackageInstall, fromAppStore: meta.fromAppStore,
            omittedFiles: meta.omittedFiles ?? [], fingerprint: meta.manifest?.digest)
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

    /// Whether restoring this backup would actually change the installed copy.
    ///
    /// The workbench hides a rollback that would be a no-op. That filter compared
    /// the backup's *marketing* label against the installed marketing string, so
    /// for an app that keeps one marketing version across builds every rollback
    /// looked like a no-op and the row vanished — after a real update, with a
    /// complete backup sitting on disk and no way to reach it.
    ///
    /// A backup with nothing comparable (an old sidecar with no version at all) is
    /// treated as distinct: offering a rollback that turns out to be a no-op is a
    /// far smaller failure than hiding one the user needs.
    public static func rollbackIsDistinct(installed: VersionSide, backup: VersionSide) -> Bool {
        guard !backup.isEmpty, !installed.isEmpty else { return true }
        return !VersionComparator.isSame(installed, as: backup)
    }

    private static func readMeta(in dir: URL) -> Meta? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("backup.json"))
        else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    /// The backup for `key` held in a specific store.
    private static func backup(forKey key: String, in store: Store) -> Backup? {
        let dir = store.root.appendingPathComponent(key, isDirectory: true)
        guard let meta = readMeta(in: dir) else { return nil }
        let payload: URL
        switch store.location {
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
            key: key, version: meta.version, buildVersion: meta.buildVersion,
            bundlePath: payload, store: store, savedAt: meta.savedAt,
            fromPackageInstall: meta.fromPackageInstall, fromAppStore: meta.fromAppStore,
            omittedFiles: meta.omittedFiles ?? [], fingerprint: meta.manifest?.digest)
    }

    /// The current backup for `key`, or nil if none exists.
    ///
    /// The outbox wins when a key exists in both. It is the newer copy by
    /// construction — a transfer only clears it after the destination copy is
    /// complete — and restoring from it is a local directory copy rather than
    /// unpacking an archive across a cable.
    public static func backup(forKey key: String) -> Backup? {
        for store in reachableStores() {
            if let found = backup(forKey: key, in: store) { return found }
        }
        return nil
    }

    // MARK: - Restore

    /// Swap the backed-up bundle for `key` back over `target`, returning the
    /// version restored. Copies the backup to a scratch dir first (so the stored
    /// backup survives the move that `InPlaceSwap` performs), then runs the same
    /// validated, atomic swap an install uses. The backup is left in place — a
    /// rollback shouldn't also destroy the only copy of the version it restored.
    ///
    /// Runs to completion if the calling task is cancelled: every child process
    /// in it is `.runToCompletion`, and `InPlaceSwap.replace` is too.
    @discardableResult
    public static func restore(forKey key: String, over target: URL) async throws -> String? {
        guard let backup = backup(forKey: key) else {
            throw BackupError.noBackup(key)
        }
        let fm = FileManager.default
        // Per attempt, not per key. Keyed on the app alone, two restores of the
        // same key shared one working directory — and since each deletes it going
        // in and again coming out, the second pulled the tree out from under the
        // first mid-copy. A unique name also means `createDirectory` below can
        // never be reporting success on somebody else's directory.
        let scratch = fm.temporaryDirectory
            .appendingPathComponent(
                "DuoUpdater-rollback-\(key)-\(UUID().uuidString)", isDirectory: true)
        // Builds written before the name carried an attempt id left their scratch
        // at the bare per-key path, and one holding a copy of a backup old enough
        // to carry `uchg` cannot be deleted by a plain `removeItem` — so it sat
        // there. Nothing reads it any more, but it is a whole bundle copy, so it
        // is reclaimed here rather than left in `/var/folders` forever. Only that
        // exact name: an attempt id belongs to a restore that may be running now.
        await removeClearingImmutableFlagsOffPool(
            at: fm.temporaryDirectory
                .appendingPathComponent("DuoUpdater-rollback-\(key)", isDirectory: true))
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        // Deleting a whole bundle copy, so it goes to Dispatch; flags cleared
        // because the copy carries whatever the backed-up app set on its files.
        defer { await removeClearingImmutableFlagsOffPool(at: scratch) }
        return try await restore(backup, key: key, stagingIn: scratch, over: target)
    }

    /// `restore(forKey:over:)` from the point its scratch directory exists.
    private static func restore(
        _ backup: Backup, key: String, stagingIn scratch: URL, over target: URL
    ) async throws -> String? {
        // A destination copy is a single archive, not a directory, so it is
        // unpacked rather than copied — and unpacking is what puts the bundle's
        // metadata back after a filesystem that could not hold it.
        let staged: URL
        switch backup.location {
        case .outbox:
            staged = scratch.appendingPathComponent(backup.bundlePath.lastPathComponent)
            let ditto = await runDitto(from: backup.bundlePath, to: staged)
            guard ditto.ok else {
                Log.install.error(
                    "restore: ditto exited \(ditto.status, privacy: .public) copying the stored \(backup.bundlePath.lastPathComponent, privacy: .public) out of the backup store — \(ditto.stderrTail, privacy: .public)")
                throw BackupError.copyFailed(backup.bundlePath.path)
            }
        case .destination:
            staged = try await unpackFromDestination(backup, key: key, into: scratch)
        }
        // Integrity gate before swapping a backup over the live app: a stored copy
        // that has changed since we wrote it has been corrupted or tampered with,
        // and swapping it in would brick the live app. Hard-fail rather than
        // restore it — a rollback that knowingly installs a damaged bundle is worse
        // than leaving the (working) current app in place. See `integrityHolds` for
        // why this asks about our own copy rather than the vendor's signature.
        //
        // Off the cooperative pool: it hashes the whole staged bundle, and for a
        // backup without a manifest it falls back to `SecStaticCodeCheckValidity`
        // (the #351 call). See `offCooperativePool`. The recorded manifest is read
        // HERE, before the hop: `root` honours the `rootOverride` task-local, and a
        // Dispatch thread has no task-locals — read inside the hop, a test's
        // scratch store silently became the real one and the tamper check passed
        // a tampered copy (`tamperingWithTheStoredCopyIsRefused` went red).
        // Whichever store this backup came out of: a disk copy's sidecar sits
        // beside its archive, not in the outbox.
        let recorded = recordedManifest(for: key, in: backup.store.root)
        guard await offCooperativePool(qos: .userInitiated, {
            integrityHolds(for: key, recorded: recorded, staged: staged)
        }) else {
            throw BackupError.backupCorrupted(backup.bundlePath.lastPathComponent)
        }
        try await InPlaceSwap.replace(newApp: staged, over: target)
        // An input method's settings and learned dictionary are not in the bundle,
        // so restoring the bundle alone rolls back the code and leaves the data at
        // whatever the newer version made of it. Restore the snapshot taken with
        // this backup, if there is one. Best-effort and reported: the bundle is
        // already back, and failing the rollback now would be a worse answer than
        // an incomplete one that says so.
        if InPlaceSwap.usesContentsRotation(target: target) {
            do {
                let restored = try await InputMethodDataBackup.restore(forKey: key)
                // Said plainly because the files on disk are only half of it: a
                // running input method holds its preferences and its mmkv/dictionary
                // files open, so what it is using is not what was just restored
                // until it is restarted. Not measured either way for these two apps
                // — stated as the caveat it is rather than implied to be handled.
                Log.install.notice(
                    "rollback: restored \(restored.count, privacy: .public) user-data location(s) with \(target.lastPathComponent, privacy: .public) — a running input method keeps using what it already loaded until it restarts")
            } catch {
                Log.install.error(
                    "rollback: \(target.lastPathComponent, privacy: .public) is back, but its user data was not restored — \(error.localizedDescription, privacy: .public)")
            }
        }
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
    ) async throws -> URL {
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
        try await BundleArchive.extract(archive: backup.bundlePath, into: staged)
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
        /// Which store the checked copy is in, so a report can name the disk. A
        /// run covers several at once, and "on the backup disk" identifies none
        /// of them.
        public let store: Store
        public var location: Backup.Location { store.location }
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
    public static func verify(deep: Bool = false) async -> [VerifyOutcome] {
        var out: [VerifyOutcome] = []
        for store in reachableStores() {
            out += await verify(in: store, deep: deep)
        }
        return out
    }

    private static func verify(in store: Store, deep: Bool) async -> [VerifyOutcome] {
        let root = store.root
        let location = store.location
        let fm = FileManager.default

        // A nested function rather than `compactMap`'s closure: a deep check
        // unpacks an archive, which is a child process this has to await.
        func check(_ key: String) async -> VerifyOutcome? {
            let dir = root.appendingPathComponent(key, isDirectory: true)
            // No sidecar is not a damaged backup, it is not a backup — the sweeper
            // deals with those, and reporting them here would put remnants in a
            // list whose every other row is something the user can act on.
            guard let meta = readMeta(in: dir) else { return nil }
            func outcome(_ result: VerifyOutcome.Result) -> VerifyOutcome {
                VerifyOutcome(
                    key: key, name: (meta.bundleName as NSString).deletingPathExtension,
                    version: meta.version, store: store, result: result)
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
                return outcome(await deepCheck(archive: archive, meta: meta))
            }
        }

        var results: [VerifyOutcome] = []
        for key in storedKeys(in: root) {
            if let result = await check(key) { results.append(result) }
        }
        return results
    }

    private static func deepCheck(archive: URL, meta: Meta) async -> VerifyOutcome.Result {
        guard let recorded = meta.manifest else {
            return .unverifiable("taken before fingerprints were recorded")
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent(
            "DuoUpdater-verify-\(UUID().uuidString)", isDirectory: true)
        defer { forceRemove(scratch) }
        let staged = scratch.appendingPathComponent(meta.bundleName)
        do {
            try await BundleArchive.extract(archive: archive, into: staged)
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
    /// Both the recorded manifest and the recomputation are taken on APFS — the
    /// sidecar's was computed on the outbox copy, and `staged` is in the
    /// temporary directory — so this comparison never straddles two filesystems
    /// no matter where the bytes were parked in between. That is what keeps a
    /// backup on an exFAT stick or an SMB share restorable rather than only
    /// apparently stored.
    private static func integrityHolds(
        for key: String, recorded: BackupManifest?, staged: URL
    ) -> Bool {
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

    /// The manifest `save` recorded for `key`, if its sidecar has one.
    private static func recordedManifest(for key: String, in root: URL) -> BackupManifest? {
        readMeta(in: root.appendingPathComponent(key, isDirectory: true))?.manifest
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
        // Reverse order, so the outbox is applied last and wins a collision: it
        // is the newer copy, and restoring from it does not go over the cable.
        // Between two disks the first one listed wins, which is the active disk —
        // the only one this Mac has been writing to.
        for store in reachableStores().reversed() {
            for key in storedKeys(in: store.root) {
                if let found = backup(forKey: key, in: store) { out[key] = found }
            }
        }
        return out
    }

    /// Drop the backup for `key` (e.g. the user dismissed it).
    ///
    /// Removes it from every store that can be read, not just the one being
    /// written to. Dropping only one copy would leave the others to reappear at
    /// the next refresh, which reads as the deletion having silently failed.
    ///
    /// This is the one deletion that crosses onto a disk this Mac does not write
    /// to, and it is safe for the reason an automatic prune is not: someone
    /// pressed a button naming this backup. See ``reachableDestinationRoot``.
    public static func remove(forKey key: String) {
        for store in reachableStores() {
            removeClearingImmutableFlags(
                at: store.root.appendingPathComponent(key, isDirectory: true))
        }
        // The recorded facts describe bytes that are now gone, and they are held
        // outside the store, so nothing above would ever reach them.
        BackupFactsLibrary.drop(forKey: key)
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
        /// can say *whose* space — this Mac's, or a named disk's.
        public let store: Store
        public var location: Backup.Location { store.location }

        public init(
            key: String, name: String, version: String?, currentVersion: String?,
            savedAt: Date?, sizeBytes: Int64, bundlePath: URL?, appStillInstalled: Bool,
            isRestorable: Bool, store: Store
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
            self.store = store
        }
    }

    /// `CFBundleShortVersionString` of the app currently at `path`, or nil if it
    /// isn't there or has no readable plist.
    private static func installedShortVersion(atPath path: String) -> String? {
        let plist = BundleLayout.infoPlistURL(for: URL(fileURLWithPath: path))
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
        var out: [Listing] = []
        for store in reachableStores() { out += listing(in: store) }
        // Undated (sidecar-less) entries sort last: they are the ones to clear out,
        // not the ones to reason about.
        return out.sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
    }

    private static func listing(in store: Store) -> [Listing] {
        let fm = FileManager.default
        let (root, location) = (store.root, store.location)
        let keys = storedKeys(in: root)
        let dirs = keys.map { root.appendingPathComponent($0, isDirectory: true) }
        // Every size in one pass, so a store whose backups have not changed since
        // the last look is read rather than walked — the difference between the
        // sheet opening at once and it opening after every file of every backup
        // has been visited. See ``BackupSizeIndex``.
        let sizes = BackupSizeIndex.shared.sizes(of: dirs, measuring: directorySize)
        var out: [Listing] = []
        for (index, key) in keys.enumerated() {
            let dir = dirs[index]
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
                sizeBytes: sizes[index],
                bundlePath: payload,
                appStillInstalled: meta.map { fm.fileExists(atPath: $0.originalPath) } ?? false,
                isRestorable: meta != nil,
                store: store))
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
    ///
    /// Deliberately **not** extended to the other readable disks. "Orphan" here
    /// means "no app at the recorded path *on this Mac*", which is a sound reading
    /// only for a store this Mac owns and has been writing to. A disk that is
    /// merely plugged in may carry another Mac's backups, and every one of them
    /// would qualify — the prune would be correct about each and would empty the
    /// disk. See ``reachableDestinationRoot``.
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
            // Measured before the removal (there is nothing left to walk after
            // it) but only counted once the removal actually happened: this
            // number is shown to the user as space reclaimed, and a prune that
            // could not delete reclaimed nothing.
            let size = directorySize(dir)
            if removeClearingImmutableFlags(at: dir) {
                freed += size
                BackupFactsLibrary.drop(forKey: key)
            }
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

    /// On-disk size of this Mac's store and of the **active** disk. `destination`
    /// is zero when that disk is not connected, which is indistinguishable from
    /// "empty" and should be presented alongside ``availability()`` rather than on
    /// its own. Use ``sizesByStore()`` where several disks may be readable.
    public static func storeSizes() -> (outbox: Int64, destination: Int64) {
        (storeSize(of: outboxRoot),
         reachableDestinationRoot.map(storeSize(of:)) ?? 0)
    }

    /// What each readable store is holding, in the order ``reachableStores()``
    /// lists them. Walks every backup in every store, so call it off the main
    /// thread.
    public static func sizesByStore() -> [(store: Store, bytes: Int64)] {
        reachableStores().map { ($0, storeSize(of: $0.root)) }
    }

    public static func storeSize(of root: URL) -> Int64 {
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return 0 }
        // Through the same index the listing reads, which is what makes the two
        // agree and what lets the settings page's own measurement pay for the
        // sheet's: by the time "Clean Up…" is pressed, this has already been asked.
        return BackupSizeIndex.shared.sizes(of: dirs, measuring: directorySize).reduce(0, +)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey],
            options: [], errorHandler: nil)
        else { return 0 }
        // Logical size, including the input-method user-data snapshot
        // (`InputMethodDataBackup`) that now sits beside the bundle in a key
        // directory. That snapshot is an APFS clone, so on the day it is taken it
        // shares nearly all its blocks with the live data and this number
        // overstates what was spent — DoubaoIme's reads 639.3 MB against 578 MB of
        // shared extents. It is still the right number to show: the clone's blocks
        // become the backup's own as the live copy diverges, so this is what the
        // rollback point grows to cost, and a display saying "occupies nothing"
        // would be wrong for every day after the first.
        //
        // `totalFileAllocatedSizeKey` is not the fix it looks like — measured, it
        // reports a 40 MB clone as 40 MB allocated, identically to its source. It
        // does not see through sharing, so switching to it changes nothing except
        // to add a claim that is not true.
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

    /// What `ditto` did, rather than just whether it worked.
    ///
    /// The stderr used to go to `nullDevice`, so a failed backup could only ever
    /// be reported as "failed" — while ditto had, at that moment, named the exact
    /// file it could not copy. Keeping it is the difference between a report you
    /// can act on and one that needs the failure reproduced first.
    struct DittoOutcome {
        let ok: Bool
        let status: Int32
        /// The tail of stderr. ditto emits one line per skipped file, and a big
        /// bundle can produce hundreds; the last few are what identify the fault.
        let stderrTail: String
    }

    /// Clear the user-immutable (`uchg`) flag under a copy we own.
    ///
    /// `ditto` preserves file flags, and an app is free to set `uchg` on files it
    /// wants to protect — ToDesk does, on `Contents/advInfo.json`. An immutable
    /// file cannot be deleted by anyone but root, its own owner included, so the
    /// flag rides into the backup store and makes our copy permanently
    /// undeletable: the staging directory cannot be cleared, and retention cannot
    /// replace the copy it is meant to supersede. The vendor's reason for the flag
    /// applies to the app they installed, not to a rollback copy in our own
    /// Application Support, so we drop it.
    ///
    /// Only `uchg`. `schg` is the system-immutable flag and needs root to clear;
    /// nothing we store should carry one, and if something does, failing loudly
    /// later is better than pretending we can handle it here.
    ///
    /// Not killed on cancellation: it runs on a copy that is about to be stored,
    /// replaced or deleted, and every one of those needs it to have finished.
    @discardableResult
    private static func clearUserImmutableFlags(under url: URL) async -> Bool {
        guard let outcome = try? await ChildProcess.run(
            "/usr/bin/chflags", ["-R", "nouchg", url.path],
            standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion)
        else { return false }
        return outcome.succeeded
    }

    /// Delete something we own, clearing `uchg` off it and retrying if the first
    /// attempt is refused.
    ///
    /// `save` strips the flag from every copy it stores, so nothing written since
    /// carries one — but a backup taken before that did, and it is still sitting
    /// in the store. Those are the copies the removal paths meet: a plain
    /// `removeItem` fails EPERM on the one locked file, and spelled `try?` it
    /// fails silently, which is worse than loudly. The removal is a partial one —
    /// it unlinks what it can before the refusal — so it can take `backup.json`
    /// with it and leave a bundle behind that `pruneOrphans` then skips for want
    /// of a sidecar, while `totalSize` goes on counting it.
    ///
    /// Clearing is safe here because the target is always a copy this store made,
    /// never the user's own file, and only the user-settable flags go: `schg`
    /// needs root, and something wearing one is a genuine reason to stop rather
    /// than something to work around. A restore is unaffected either way — it
    /// copies its own bundle out with `ditto`, flags and all.
    ///
    /// In-process rather than the `chflags` of `clearUserImmutableFlags`, which
    /// needs an async context: every caller here is already on a Dispatch thread
    /// doing the deletion, and `lchflags` never follows a symlink, so a link
    /// inside a bundle has its own flag cleared instead of reaching outside the
    /// store.
    @discardableResult
    private static func removeClearingImmutableFlags(at url: URL) -> Bool {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: url)
            return true
        } catch {
            // `lstat`, not `fileExists`: it answers for the link itself, and
            // "already gone" is the one failure that is not one.
            var probe = stat()
            guard lstat(url.path, &probe) == 0 else { return true }
        }
        clearUserImmutableFlags(inProcessUnder: url)
        do {
            try fm.removeItem(at: url)
            return true
        } catch {
            Log.install.error(
                "backup: \(url.lastPathComponent, privacy: .public) would not delete even after clearing its immutable flags — \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// `removeClearingImmutableFlags` off the cooperative pool, for the callers
    /// in an async context that can be deleting a whole bundle copy.
    ///
    /// Resolve `url` before calling, as `removeItemOffCooperativePool` says: a
    /// Dispatch thread has no task-locals, so a path built from `root` inside the
    /// hop would ignore a test's override.
    private static func removeClearingImmutableFlagsOffPool(at url: URL) async {
        await offCooperativePool(qos: .userInitiated) {
            _ = removeClearingImmutableFlags(at: url)
        }
    }

    /// Clear `uchg`/`uappnd` from `url` and everything under it, without a child
    /// process. See `removeClearingImmutableFlags` for why the flags go at all.
    private static func clearUserImmutableFlags(inProcessUnder url: URL) {
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

    /// The prefix every staging directory for `key` shares — the bundle copy's own
    /// and `InputMethodDataBackup`'s user-data snapshot alike.
    ///
    /// One function rather than the literal spelled out at each site, because
    /// `sweepStagingLeftovers` selects on exactly this and nothing else ever will:
    /// a stager that invents its own name is stranded PERMANENTLY when its cleanup
    /// does not run, and invisibly, since every scan of the store's root passes
    /// `.skipsHiddenFiles` — so retention never prunes it and `backupSize` never
    /// counts it. `InputMethodDataBackup` shipped that way briefly and its snapshot
    /// is a copy of the user's entire input-method data directory.
    static func stagingPrefix(key: String) -> String { ".staging-\(key)" }

    /// Best-effort removal of staging dirs left by earlier attempts for this app.
    /// Best-effort is the point: one that will not go is reported and stepped
    /// around, never allowed to fail the backup that follows. Hidden names, so
    /// `allBackups`' directory scan skips them either way.
    ///
    /// Internal rather than private so `InputMethodDataBackupTests` can pin that
    /// the user-data snapshot's own name is one this reclaims.
    static func sweepStagingLeftovers(in root: URL, key: String) async {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in entries where name.hasPrefix(stagingPrefix(key: key)) {
            let leftover = root.appendingPathComponent(name)
            // Anything we copied may carry a `uchg` the source set; clear it before
            // trying, or a leftover written before this existed can never be swept.
            await clearUserImmutableFlags(under: leftover)
            // A leftover is a partial bundle copy or a user-data snapshot, so
            // deleting it is real disk work: off the cooperative pool.
            let failure: String? = await offCooperativePool(qos: .userInitiated) {
                do {
                    try FileManager.default.removeItem(at: leftover)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            if let failure {
                Log.install.error(
                    "backup: leftover staging dir \(name, privacy: .public) would not clear — \(failure, privacy: .public); this backup uses a fresh one, but that directory is stranded until it is removed by hand")
            }
        }
    }

    /// `ditto src dst`, with stderr's last few lines kept for the log.
    ///
    /// stderr used to go to a temporary file because nothing drained a `Pipe`
    /// while `ditto` ran, and a bundle noisy enough to fill the buffer would have
    /// blocked it forever. `ChildProcess` drains both pipes as the child writes, so
    /// it is captured directly now. Runs to completion on cancellation: a half
    /// copy is what `save` and `restore` both exist to avoid.
    private static func runDitto(from src: URL, to dst: URL) async -> DittoOutcome {
        try? FileManager.default.removeItem(at: dst)
        let outcome: ChildProcess.Outcome
        do {
            outcome = try await ChildProcess.run(
                "/usr/bin/ditto", [src.path, dst.path],
                standardOutput: .discard, onCancel: .runToCompletion)
        } catch {
            return DittoOutcome(ok: false, status: -1, stderrTail: "could not start ditto: \(error)")
        }
        let text = String(data: outcome.standardError, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n")
        let tail = lines.suffix(4).joined(separator: " | ")
        return DittoOutcome(
            ok: outcome.terminationStatus == 0, status: outcome.terminationStatus,
            stderrTail: lines.count > 4 ? "(\(lines.count) lines) … \(tail)" : tail)
    }
}
