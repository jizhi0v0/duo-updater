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

    public static var root: URL {
        if let rootOverride { return rootOverride }
        return DuoStateDirectory.base
            .appendingPathComponent("DuoUpdater/Backups", isDirectory: true)
    }

    /// A stored backup: the bundle on disk plus the metadata we show in the UI.
    public struct Backup: Sendable, Equatable {
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
        sweepStagingLeftovers(in: root, key: key)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)

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
            Log.install.error(
                "backup: \(name, privacy: .public) has \(unreadable.sealed.count, privacy: .public) sealed file(s) we cannot read, first \(unreadable.sealed.first ?? "?", privacy: .public) — that is payload, so there is nothing worth storing")
            try? fm.removeItem(at: staging)
            throw BackupError.payloadUnreadable(unreadable.sealed.first ?? appPath.path)
        }

        // `ditto` preserves the bundle's symlinks, xattrs, and (importantly) its
        // code signature exactly — a plain copy can mangle them. It reports one
        // status for the whole run, so a non-zero exit is only acceptable once we
        // have confirmed the ONLY things it dropped are the ones we meant to drop.
        let ditto = runDitto(from: appPath, to: staged)
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
                try? fm.removeItem(at: staging)
                throw BackupError.copyFailed(appPath.path)
            }
            let unexpected = BackupManifest.unexpectedOmissions(
                source: appPath, copy: staged, expected: unreadable.unsealed)
            guard unexpected.isEmpty else {
                Log.install.error(
                    "backup: copy of \(name, privacy: .public) lost \(unexpected.count, privacy: .public) file(s) it should have kept")
                try? fm.removeItem(at: staging)
                throw BackupError.copyFailed(appPath.path)
            }
        }

        // Our copy from here on, so it must not inherit a flag that would stop us
        // ever replacing or removing it — see `clearUserImmutableFlags`. Done before
        // the fingerprint so the manifest describes what is actually stored.
        if !clearUserImmutableFlags(under: staged) {
            Log.install.error(
                "backup: could not clear immutable flags on the copy of \(name, privacy: .public) — retention may not be able to replace it later")
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
            version: version, buildVersion: buildVersion, bundleID: bundleID,
            originalPath: appPath.path, bundleName: name, savedAt: savedAt,
            fromPackageInstall: fromPackageInstall, fromAppStore: fromAppStore,
            omittedFiles: unreadable.unsealed.isEmpty ? nil : unreadable.unsealed,
            manifest: manifest)
        // The sidecar is what EVERY read path keys off (`backup(forKey:)` returns nil
        // without it), so a backup whose sidecar didn't write is unusable. Fail the
        // save (leaving the prior backup intact) rather than leave an invisible bundle.
        guard let metaData = try? JSONEncoder().encode(meta),
              (try? metaData.write(to: staging.appendingPathComponent("backup.json"),
                                   options: .atomic)) != nil else {
            Log.install.error(
                "backup: the copy of \(name, privacy: .public) is complete but its sidecar would not write — discarding it, since every read path keys off the sidecar")
            try? fm.removeItem(at: staging)
            throw BackupError.copyFailed(appPath.path)
        }

        // New backup is complete in `staging`; now replace the old one atomically (a
        // same-volume rename, so the swap window is a single near-instant operation
        // rather than the multi-second copy above).
        do {
            if fm.fileExists(atPath: dir.path) {
                // The copy being superseded has to be deletable for the exchange to
                // finish. One written before we started stripping `uchg` — or by any
                // path where stripping failed — still carries it, and `replaceItemAt`
                // cannot remove it. Clearing it here is what lets retention ever get
                // past a single poisoned generation.
                clearUserImmutableFlags(under: dir)
                _ = try fm.replaceItemAt(dir, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: dir)
            }
        } catch {
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
            key: key, version: version, buildVersion: buildVersion,
            bundlePath: dest, savedAt: savedAt,
            fromPackageInstall: fromPackageInstall, fromAppStore: fromAppStore)
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

    /// The current backup for `key`, or nil if none exists.
    public static func backup(forKey key: String) -> Backup? {
        let dir = root.appendingPathComponent(key, isDirectory: true)
        let metaURL = dir.appendingPathComponent("backup.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
        let bundle = dir.appendingPathComponent(meta.bundleName)
        guard FileManager.default.fileExists(atPath: bundle.path) else { return nil }
        return Backup(
            key: key, version: meta.version, buildVersion: meta.buildVersion,
            bundlePath: bundle, savedAt: meta.savedAt,
            fromPackageInstall: meta.fromPackageInstall, fromAppStore: meta.fromAppStore)
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
        let ditto = runDitto(from: backup.bundlePath, to: staged)
        guard ditto.ok else {
            Log.install.error(
                "restore: ditto exited \(ditto.status, privacy: .public) copying the stored \(backup.bundlePath.lastPathComponent, privacy: .public) out of the backup store — \(ditto.stderrTail, privacy: .public)")
            throw BackupError.copyFailed(backup.bundlePath.path)
        }
        // Integrity gate before swapping a backup over the live app: a stored copy
        // that has changed since we wrote it has been corrupted or tampered with,
        // and swapping it in would brick the live app. Hard-fail rather than
        // restore it — a rollback that knowingly installs a damaged bundle is worse
        // than leaving the (working) current app in place. See `integrityHolds` for
        // why this asks about our own copy rather than the vendor's signature.
        guard integrityHolds(for: key, staged: staged) else {
            throw BackupError.backupCorrupted(backup.bundlePath.lastPathComponent)
        }
        try InPlaceSwap.replace(newApp: staged, over: target)
        // An input method's settings and learned dictionary are not in the bundle,
        // so restoring the bundle alone rolls back the code and leaves the data at
        // whatever the newer version made of it. Restore the snapshot taken with
        // this backup, if there is one. Best-effort and reported: the bundle is
        // already back, and failing the rollback now would be a worse answer than
        // an incomplete one that says so.
        if InPlaceSwap.usesContentsRotation(target: target) {
            do {
                let restored = try InputMethodDataBackup.restore(forKey: key)
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

    /// Whether the staged copy is still what we stored.
    ///
    /// Prefers the manifest recorded at save time, which asks the question a
    /// gate on a *backup* should ask. Falls back to the vendor code signature
    /// only for backups written before manifests existed — that gate refuses
    /// apps which break their own seal by writing state inside their bundle
    /// (ToDesk, EasyConnect), so a faithful copy of what the user was running
    /// was rejected as "corrupted".
    private static func integrityHolds(for key: String, staged: URL) -> Bool {
        let metaURL = root.appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent("backup.json")
        let recorded = (try? Data(contentsOf: metaURL))
            .flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }?.manifest

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
    public static func listing() -> [Listing] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var out: [Listing] = []
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let bundle = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .first { $0.pathExtension == "app" }
            let meta = (try? Data(contentsOf: dir.appendingPathComponent("backup.json")))
                .flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
            out.append(Listing(
                key: dir.lastPathComponent,
                name: meta?.bundleName ?? bundle?.lastPathComponent ?? dir.lastPathComponent,
                version: meta?.version,
                currentVersion: meta.flatMap { installedShortVersion(atPath: $0.originalPath) },
                savedAt: meta?.savedAt,
                sizeBytes: directorySize(dir),
                bundlePath: bundle,
                appStillInstalled: meta.map { fm.fileExists(atPath: $0.originalPath) } ?? false,
                isRestorable: meta != nil))
        }
        // Undated (sidecar-less) entries sort last: they are the ones to clear out,
        // not the ones to reason about.
        return out.sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
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

        public var errorDescription: String? {
            switch self {
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

    /// `ditto src dst`, returning true on success. Faithfully duplicates a bundle
    /// including its code signature, unlike `FileManager.copyItem`.
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
    @discardableResult
    private static func clearUserImmutableFlags(under url: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        p.arguments = ["-R", "nouchg", url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
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
    static func sweepStagingLeftovers(in root: URL, key: String) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in entries where name.hasPrefix(stagingPrefix(key: key)) {
            let leftover = root.appendingPathComponent(name)
            // Anything we copied may carry a `uchg` the source set; clear it before
            // trying, or a leftover written before this existed can never be swept.
            clearUserImmutableFlags(under: leftover)
            do { try fm.removeItem(at: leftover) } catch {
                Log.install.error(
                    "backup: leftover staging dir \(name, privacy: .public) would not clear — \(error.localizedDescription, privacy: .public); this backup uses a fresh one, but that directory is stranded until it is removed by hand")
            }
        }
    }

    private static func runDitto(from src: URL, to dst: URL) -> DittoOutcome {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        // stderr goes to a file rather than a `Pipe`: nothing drains a pipe while
        // ditto runs, so a bundle noisy enough to fill the buffer would block it
        // forever, turning a diagnostic into a hang.
        let errURL = fm.temporaryDirectory.appendingPathComponent("duo-ditto-\(UUID().uuidString).err")
        fm.createFile(atPath: errURL.path, contents: nil)
        defer { try? fm.removeItem(at: errURL) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [src.path, dst.path]
        p.standardOutput = FileHandle.nullDevice
        let errHandle = try? FileHandle(forWritingTo: errURL)
        p.standardError = errHandle ?? FileHandle.nullDevice
        do { try p.run() } catch {
            return DittoOutcome(ok: false, status: -1, stderrTail: "could not start ditto: \(error)")
        }
        p.waitUntilExit()
        try? errHandle?.close()
        let text = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n")
        let tail = lines.suffix(4).joined(separator: " | ")
        return DittoOutcome(
            ok: p.terminationStatus == 0, status: p.terminationStatus,
            stderrTail: lines.count > 4 ? "(\(lines.count) lines) … \(tail)" : tail)
    }
}
