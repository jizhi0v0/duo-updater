import Foundation
import Security

/// What an install in progress has touched, written down before it touches it,
/// so the next launch can tell what a process that was killed left behind.
///
/// A `kill -9`, a crash or a power cut runs none of an install's `defer`s: its
/// scratch directory stays, a disk image it had attached stays attached until
/// the Mac restarts, and a third party it handed the swap to (brew) may have
/// died on its next write to the pipe we held, leaving the app deleted. The
/// install lock cannot say any of this afterwards — measured: once the process
/// holding `install.lock` is SIGKILLed the lock is free at once while its
/// children keep running (ppid 1) — so a launch sweep going by the lock alone
/// could delete a directory an orphaned child is still writing.
///
/// **One file per install**, `install-journal/<job>.json` under
/// ``DuoStateDirectory``: the app, its path, its version and cdhash before the
/// swap, the route, the backup key, and this process's pid and start time.
/// Written and fsync'd when the install starts, before anything of the app's is
/// touched (so before every route's commit point), and again each time the
/// install adds a scratch directory, a disk image mount or a third-party child
/// (``noteWorkDirectory(_:)``, ``noteMount(_:image:)``,
/// ``Recording/noteChild(_:)``). Removed when the install ends — finished,
/// failed, refused or cancelled — by ``Recording/finish()``.
///
/// **At launch** (``processLeftovers(lock:cleanup:)``), under the install lock,
/// each file whose writer and child are both gone has its leftovers cleaned
/// and its app looked at: there, readable and intact means the install either
/// finished or never started its swap, and the file goes; missing, unreadable
/// or with a broken signature means it was cut off mid-swap, and the file stays
/// as an interrupted install (``interruptedInstalls()``) until the app is
/// restored or reads again.
///
/// Every write is a plain synchronous file write, so nothing here can be cut
/// short by a task's cancellation — in particular not the writes on an
/// install's wrap-up side, which the rule "past the commit point, the wrap-up
/// runs to its end" needs.
public enum InstallJournal {

    /// Test seam: where the files live. Task-local like
    /// `BackupStore.rootOverride`, so parallel suites cannot see each other's.
    @TaskLocal static var rootOverride: URL?

    /// The install the current task works for, bound by the host around it
    /// (``recording(_:_:)``). What the installers' notes go to.
    @TaskLocal static var current: Recording?

    /// The directory, or nil when journaling is off: in a test process that
    /// did not bind ``rootOverride``, so the many tests that drive a host's
    /// install path never write into the real state directory — the same rule
    /// `ResumableDownloadStore.root` follows.
    static var root: URL? {
        if let rootOverride { return rootOverride }
        if DuoStateDirectory.isTestProcess { return nil }
        return DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("install-journal", isDirectory: true)
    }

    // MARK: - What a file holds

    /// A process, named so that a recycled pid does not pass for it: the pid
    /// and the start time the kernel reports for it (`proc_pidinfo`, as
    /// `CLIToolProcesses` reads it).
    struct ProcessStamp: Codable, Equatable, Sendable {
        let pid: Int32
        /// Seconds since 1970.
        let started: Double

        /// `pid` as it is now, or nil when no such process exists.
        static func of(_ pid: pid_t) -> ProcessStamp? {
            CLIToolProcesses.startTime(of: pid).map {
                ProcessStamp(pid: pid, started: $0.timeIntervalSince1970)
            }
        }

        /// Whether this very process is still running: the pid exists and
        /// started when it did. A millisecond of slack covers the round trip
        /// through a `Double`; two processes with one pid are seconds apart.
        var isRunning: Bool {
            guard let now = Self.of(pid) else { return false }
            return abs(now.started - started) < 0.001
        }
    }

    /// A disk image an install attached: where, and which file, which is what
    /// `hdiutil info` lists it by.
    struct Mount: Codable, Equatable, Sendable {
        let mountPoint: String
        let image: String
    }

    /// Why an install counts as interrupted.
    public enum Damage: String, Codable, Sendable, Equatable {
        /// Nothing at the app's path.
        case missing
        /// Something is there, but its Info.plist does not read — brew empties
        /// a bundle's contents when the successor has the same name.
        case unreadable
        /// It reads, but it was signed before the install and its signature no
        /// longer holds: a swap cut off halfway through.
        case signatureBroken
    }

    struct Entry: Codable, Equatable, Sendable {
        var job: String
        var appID: String
        var appName: String
        var bundleID: String?
        var appPath: String
        /// The version on disk when the install started, both halves.
        var oldVersion: String?
        var oldBuild: String?
        /// The main executable's cdhash then, hex; nil for unsigned code.
        var oldCDHash: String?
        /// What the install was going to put there.
        var targetVersion: String?
        var targetBuild: String?
        var route: String
        /// `BackupStore.key` for the app — the key both its backup and its
        /// install rollback point are stored under.
        var backupKey: String
        var startedAt: Date
        var owner: ProcessStamp
        /// The third party the install handed its commit to, once started.
        var child: ProcessStamp?
        var workDirectories: [String] = []
        var mounts: [Mount] = []
        /// Set by launch processing when the app was found cut off.
        var damage: Damage?
    }

    // MARK: - Recording an install

    /// One install's file, kept current as the install goes.
    public final class Recording: @unchecked Sendable {
        let file: URL
        private let lock = NSLock()
        private var entry: Entry
        private var finished = false

        fileprivate init(file: URL, entry: Entry) {
            self.file = file
            self.entry = entry
        }

        var snapshot: Entry { lock.withLock { entry } }

        /// Record the third party this install handed its commit to, so a
        /// launch that finds it still running leaves its directories alone.
        /// Called from `ChildProcess`'s `onLaunch`, while `pid` is the child's.
        func noteChild(_ pid: pid_t) {
            guard let stamp = ProcessStamp.of(pid) else { return }
            update { $0.child = stamp }
        }

        func update(_ change: (inout Entry) -> Void) {
            lock.withLock {
                guard !finished else { return }
                let before = entry
                change(&entry)
                guard entry != before else { return }
                InstallJournal.write(entry, to: file)
            }
        }

        /// The install has ended, whichever way: remove its file. Idempotent.
        public func finish() {
            lock.withLock {
                guard !finished else { return }
                finished = true
                if unlink(file.path) != 0, errno != ENOENT {
                    Log.install.error(
                        "install journal: could not remove \(self.file.lastPathComponent, privacy: .public) — errno \(errno, privacy: .public)")
                }
            }
        }
    }

    /// Start the file for an install of `app` by `route` towards `target`.
    /// Nil when journaling is off or the file could not be written — the
    /// install goes ahead without one, as it did before this existed; the
    /// failure is logged.
    ///
    /// Call it after taking the install lock and before anything of the app's
    /// is touched, and pair it with ``Recording/finish()`` on every way out.
    public static func begin(
        app: InstalledApp, route: InstallCoordinator.Route, target: VersionSide?
    ) async -> Recording? {
        guard let root else { return nil }
        guard let owner = ProcessStamp.of(getpid()) else {
            Log.install.error("install journal: cannot read this process's own start time; installing without a journal")
            return nil
        }
        let path = app.path
        // A blocking Security call, so off the pool like every other one.
        let cdhash = await offCooperativePool(qos: .userInitiated) {
            CLIToolProcesses.fileCDHash(path.path)
        }
        let onDisk = versions(at: path)
        let job = UUID().uuidString
        let entry = Entry(
            job: job, appID: app.id, appName: app.name, bundleID: app.bundleID,
            appPath: path.path,
            oldVersion: onDisk.marketing ?? app.shortVersion,
            oldBuild: onDisk.build ?? app.buildVersion,
            oldCDHash: cdhash.map(hex),
            targetVersion: target?.marketing, targetBuild: target?.build,
            route: route.rawValue,
            backupKey: BackupStore.key(bundleID: app.bundleID, path: path),
            startedAt: Date(), owner: owner)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            Log.install.error(
                "install journal: cannot create \(root.path, privacy: .public) — \(error.localizedDescription, privacy: .public); installing without a journal")
            return nil
        }
        let file = root.appendingPathComponent("\(job).json", isDirectory: false)
        guard write(entry, to: file) else { return nil }
        return Recording(file: file, entry: entry)
    }

    /// Run `body` with `recording` as the install the installers' notes go to.
    /// A nil recording runs `body` as is. `isolation` and the `#if` are
    /// `RequestAttribution.withApp`'s, for the reasons given there: the
    /// menu-bar app's install closure is MainActor-bound and not `Sendable`.
    public static func recording<T>(
        _ recording: Recording?,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        #if compiler(>=6.4)
        try await $current.withValue(recording) { () async throws -> T in try await body() }
        #else
        try await $current.withValue(recording, operation: body, isolation: isolation)
        #endif
    }

    /// Record a scratch directory the current install has just created.
    static func noteWorkDirectory(_ directory: URL) {
        current?.update { entry in
            let path = directory.path
            if !entry.workDirectories.contains(path) { entry.workDirectories.append(path) }
        }
    }

    /// Record a disk image the current install is about to attach. Before the
    /// attach, not after: a process killed while `hdiutil` attaches leaves the
    /// image attached, and a mount recorded that was never made is only an
    /// `hdiutil info` lookup that finds nothing.
    static func noteMount(_ mountPoint: URL, image: URL) {
        current?.update { entry in
            let mount = Mount(mountPoint: mountPoint.path, image: image.path)
            if !entry.mounts.contains(mount) { entry.mounts.append(mount) }
        }
    }

    // MARK: - At launch

    /// What launch processing did with one file.
    public enum Processed: Sendable, Equatable {
        /// Its install is still running — the process that wrote it, or the
        /// third party it started, or another install of the same app in this
        /// process. Left alone, for the next launch.
        case stillRunning(app: String)
        /// A disk image it recorded would not come off, or could not be found
        /// in `hdiutil info` either way. Left alone, scratch directory
        /// included (the mount may be inside it), for the next launch.
        case leftoversRemain(app: String)
        /// The app reads and is intact: the install finished (`completed`),
        /// never got to its swap (`unchanged`), or the app changed some other
        /// way since. The file is gone.
        case resolved(app: String, Resolution)
        /// The app is missing, unreadable or broken: the file stays, as an
        /// interrupted install.
        case interrupted(app: String, Damage)
    }

    public enum Resolution: Sendable, Equatable {
        case completed
        case unchanged
        case changedElsewhere
    }

    /// What processing runs to clean a disk image up, so a test can replay one
    /// without attaching a real image. Production uses `live`.
    struct Cleanup: Sendable {
        var attachment: @Sendable (_ image: URL) async -> DiskImageMount.Attachment
        var detach: @Sendable (_ mountPoint: URL, _ image: URL) async -> Bool

        static let live = Cleanup(
            attachment: { await DiskImageMount.attachment(of: $0) },
            detach: { await DiskImageMount.detach($0, image: $1) })
    }

    /// Go through every file an earlier process left: clean up after the
    /// installs whose process and child are gone, and decide what became of
    /// their apps (see the type's comment). Run at launch, after
    /// `InPlaceSwap.recoverInterruptedSwaps` and before
    /// `InstallCoordinator.sweepSettledInstallRollbackPoints`, which keeps the
    /// rollback point of every app with a file here.
    ///
    /// Takes the machine-wide install lock, non-blocking, like those two.
    /// Returns nil when another process holds it — nothing was looked at, and
    /// the caller should try again later.
    @discardableResult
    public static func processLeftovers(
        lock: ProcessInstallLock = .shared
    ) async -> [Processed]? {
        await processLeftovers(lock: lock, cleanup: .live)
    }

    static func processLeftovers(
        lock: ProcessInstallLock, cleanup: Cleanup
    ) async -> [Processed]? {
        guard let root else { return [] }
        do {
            try await lock.claim()
        } catch {
            Log.install.notice("install journal: another installer holds the install lock, leftovers deferred")
            return nil
        }
        removeStaleTemporaryFiles(in: root)
        let entries = readAll(in: root)
        // What a running install is using, in this process (which shares the
        // lock) or any other — its app and its scratch directories. A dead
        // install's directory can have the same name as a live one's: the
        // Sparkle, Vendor and Xcode routes name theirs after the app and the
        // version.
        let live = entries.filter { $0.entry.owner.isRunning || $0.entry.child?.isRunning == true }
        let liveDirectories = Set(live.flatMap { $0.entry.workDirectories.map(standardized) })

        var processed: [Processed] = []
        for (file, entry) in entries {
            let name = entry.appName
            guard !entry.owner.isRunning, entry.child?.isRunning != true else {
                processed.append(.stillRunning(app: name))
                continue
            }
            let appPath = standardized(entry.appPath)
            guard !live.contains(where: { $0.file != file && standardized($0.entry.appPath) == appPath }) else {
                processed.append(.stillRunning(app: name))
                continue
            }
            // Mounts first: an install's mount points are inside its scratch
            // directory, and a delete walking into an attached volume is not
            // something to start.
            var mountsLeft = false
            for mount in entry.mounts {
                let image = URL(fileURLWithPath: mount.image)
                switch await cleanup.attachment(image) {
                case .none:
                    continue
                case .disk:
                    if await cleanup.detach(URL(fileURLWithPath: mount.mountPoint), image) {
                        Log.install.notice(
                            "install journal: detached \(image.lastPathComponent, privacy: .public), left attached by \(name, privacy: .public)'s install")
                    } else {
                        mountsLeft = true
                    }
                case .unknown:
                    mountsLeft = true
                }
            }
            guard !mountsLeft else {
                Log.install.error(
                    "install journal: a disk image \(name, privacy: .public)'s install attached is still attached or cannot be looked up; its leftovers stay for the next launch")
                processed.append(.leftoversRemain(app: name))
                continue
            }
            for path in entry.workDirectories where !liveDirectories.contains(standardized(path)) {
                removeScratchDirectory(URL(fileURLWithPath: path, isDirectory: true))
            }

            let verdict = await classify(entry)
            switch verdict {
            case .resolved(let resolution):
                if unlink(file.path) != 0, errno != ENOENT {
                    Log.install.error(
                        "install journal: could not remove \(file.lastPathComponent, privacy: .public) — errno \(errno, privacy: .public)")
                }
                // The result record of an install whose process died before
                // it could report one. `.notice`, like `install returned`.
                Log.install.notice(
                    "install journal: \(name, privacy: .public) [\(entry.bundleID ?? "?", privacy: .public)] via \(entry.route, privacy: .public): its installer process ended before it finished; the app reads \(String(describing: resolution), privacy: .public) (\(versions(at: URL(fileURLWithPath: entry.appPath)).text(withBuild: true), privacy: .public))")
                processed.append(.resolved(app: name, resolution))
            case .damaged(let damage):
                var kept = entry
                kept.damage = damage
                // Cleaned already; a later launch has no reason to look again.
                kept.workDirectories = []
                kept.mounts = []
                kept.child = nil
                write(kept, to: file)
                Log.install.error(
                    "install journal: \(name, privacy: .public) at \(entry.appPath, privacy: .public) is \(damage.rawValue, privacy: .public) after an install via \(entry.route, privacy: .public) was cut off")
                processed.append(.interrupted(app: name, damage))
            }
        }
        await lock.release()
        return processed
    }

    enum Verdict: Equatable {
        case resolved(Resolution)
        case damaged(Damage)
    }

    /// What became of `entry`'s app.
    ///
    /// Unreadable is decided exactly as the rollback point's settling decides
    /// it (`BackupStore.hasReadableBundle`), so the two agree on every app
    /// they both look at. The signature is only read when it can mean
    /// something: the code was signed before, and its cdhash has changed — an
    /// app that writes files into its own bundle keeps its cdhash and would
    /// otherwise read as broken.
    static func classify(_ entry: Entry) async -> Verdict {
        let app = URL(fileURLWithPath: entry.appPath)
        guard BackupStore.hasReadableBundle(at: app) else {
            return .damaged(FileManager.default.fileExists(atPath: app.path) ? .unreadable : .missing)
        }
        let cdhash = await offCooperativePool(qos: .userInitiated) {
            CLIToolProcesses.fileCDHash(app.path).map(hex)
        }
        if let old = entry.oldCDHash {
            if cdhash == old { return .resolved(.unchanged) }
            let valid = await offCooperativePool(qos: .userInitiated) { signatureHolds(at: app) }
            if !valid { return .damaged(.signatureBroken) }
        }
        let target = VersionSide(marketing: entry.targetVersion, build: entry.targetBuild)
        let onDisk = versions(at: app)
        if !target.isEmpty, !onDisk.isEmpty, !VersionComparator.isNewer(target, than: onDisk) {
            return .resolved(.completed)
        }
        if entry.oldCDHash == nil,
           onDisk == VersionSide(marketing: entry.oldVersion, build: entry.oldBuild) {
            return .resolved(.unchanged)
        }
        return .resolved(.changedElsewhere)
    }

    /// The bundle's signature against its own seal — executable and resources,
    /// the default `SecStaticCodeCheckValidity`. Not strict and not deep: this
    /// asks "was the swap cut off halfway", not the install gates' question.
    private static func signatureHolds(at app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    // MARK: - Interrupted installs

    /// Where an interrupted install can be restored from.
    public struct RestoreSource: Sendable, Equatable {
        public let key: String
        /// Which copy of `key`: the install rollback point, or the user's
        /// backup. Pass it to `BackupStore.restoreReportingUserData(forKey:over:from:)`.
        public let purpose: BackupStore.Purpose
        public let version: String?
        /// The stored bundle, when it is a directory on this Mac — something a
        /// surface can read a name and icon from with the app gone. Nil for a
        /// copy archived on the backup disk.
        public let bundle: URL?
    }

    /// An install that was cut off and left its app missing or broken.
    public struct InterruptedInstall: Sendable, Equatable, Identifiable {
        /// The journal's job id.
        public let id: String
        public let appID: String
        public let appName: String
        public let bundleID: String?
        public let appPath: URL
        /// The version on disk before the install started.
        public let oldVersion: String?
        public let oldBuild: String?
        /// `InstallCoordinator.Route`'s raw value.
        public let route: String
        public let damage: Damage
        /// Nil when there is nothing to restore from: no backup was being
        /// kept and the route takes no rollback point (or taking one failed).
        public let restoreFrom: RestoreSource?
        /// A bundle to read the app's icon from: the app itself when something
        /// readable is still there, else the stored copy's, else nil.
        public let iconSource: URL?
    }

    /// Every install launch processing found cut off, oldest first.
    ///
    /// The restore source is the install rollback point when there is one —
    /// it is taken right before the install, for exactly this — and otherwise
    /// the user's backup of the app, which is from this install when backups
    /// were on for it, and possibly an older one when they were not.
    public static func interruptedInstalls() -> [InterruptedInstall] {
        guard let root else { return [] }
        return readAll(in: root)
            .map(\.entry)
            .filter { $0.damage != nil }
            .sorted { $0.startedAt < $1.startedAt }
            .map { entry in
                let app = URL(fileURLWithPath: entry.appPath)
                let source = restoreSource(for: entry)
                let icon = BackupStore.hasReadableBundle(at: app) ? app : source?.bundle
                return InterruptedInstall(
                    id: entry.job, appID: entry.appID, appName: entry.appName,
                    bundleID: entry.bundleID, appPath: app,
                    oldVersion: entry.oldVersion, oldBuild: entry.oldBuild,
                    route: entry.route, damage: entry.damage ?? .missing,
                    restoreFrom: source, iconSource: icon)
            }
    }

    private static func restoreSource(for entry: Entry) -> RestoreSource? {
        if let point = BackupStore.rollbackPoint(forKey: entry.backupKey) {
            return RestoreSource(
                key: entry.backupKey, purpose: .installRollbackPoint, version: point.version,
                bundle: point.location == .outbox ? point.bundlePath : nil)
        }
        let candidates = BackupStore.keyCandidates(
            bundleID: entry.bundleID, path: URL(fileURLWithPath: entry.appPath))
        for key in candidates {
            if let backup = BackupStore.backup(forKey: key) {
                return RestoreSource(
                    key: key, purpose: .userBackup, version: backup.version,
                    bundle: backup.location == .outbox ? backup.bundlePath : nil)
            }
        }
        return nil
    }

    /// The app at `target` has been put back: drop the interrupted installs
    /// recorded for it. Called by `BackupStore`'s restore once its swap has
    /// landed. Files of installs still being processed or still running are
    /// not interrupted ones, and are left alone.
    static func resolveInterrupted(at target: URL) {
        guard let root else { return }
        let wanted = standardized(target.path)
        for (file, entry) in readAll(in: root)
        where entry.damage != nil && standardized(entry.appPath) == wanted {
            if unlink(file.path) == 0 {
                Log.install.notice(
                    "install journal: \(entry.appName, privacy: .public) restored; its interrupted install is cleared")
            }
        }
    }

    /// The app paths that have a file here — a running install, one not yet
    /// processed, or an interrupted one. Their rollback points are not the
    /// rollback sweep's to discard.
    static func journaledAppPaths() -> Set<String> {
        guard let root else { return [] }
        return Set(readAll(in: root).map { standardized($0.entry.appPath) })
    }

    /// The scratch directories a running install has recorded, in this
    /// process or another: not the stale-scratch sweep's to take.
    static func liveWorkDirectories() -> Set<String> {
        guard let root else { return [] }
        return Set(readAll(in: root)
            .filter { $0.entry.owner.isRunning || $0.entry.child?.isRunning == true }
            .flatMap { $0.entry.workDirectories.map(standardized) })
    }

    // MARK: - Files

    /// Write `entry` to `file` so that a kill at any moment leaves either the
    /// old file or the new one, and the new one is on disk once this returns:
    /// a temporary file, fsync'd, renamed over, then the directory fsync'd.
    @discardableResult
    static func write(_ entry: Entry, to file: URL) -> Bool {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(entry)
        } catch {
            Log.install.error("install journal: cannot encode an entry — \(error.localizedDescription, privacy: .public)")
            return false
        }
        let temporary = file.path + ".tmp"
        let fd = open(temporary, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            Log.install.error("install journal: cannot open \(temporary, privacy: .public) — errno \(errno, privacy: .public)")
            return false
        }
        let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        let synced = fsync(fd) == 0
        close(fd)
        guard written == data.count, synced, rename(temporary, file.path) == 0 else {
            Log.install.error("install journal: cannot write \(file.lastPathComponent, privacy: .public) — errno \(errno, privacy: .public)")
            unlink(temporary)
            return false
        }
        let directory = open(file.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
        if directory >= 0 {
            fsync(directory)
            close(directory)
        }
        return true
    }

    /// Every file in `root` that decodes. One that does not is left where it
    /// is and logged: it may be a newer build's, and deleting state a later
    /// version wrote is not this one's call.
    static func readAll(in root: URL) -> [(file: URL, entry: Entry)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let decoder = JSONDecoder()
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            let file = root.appendingPathComponent(name, isDirectory: false)
            guard let data = FileManager.default.contents(atPath: file.path) else { return nil }
            do {
                return (file, try decoder.decode(Entry.self, from: data))
            } catch {
                Log.install.error("install journal: \(name, privacy: .public) does not decode, left as is — \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// A `.tmp` left by a process killed inside ``write(_:to:)``. An hour old
    /// is no live write's: one takes microseconds.
    private static func removeStaleTemporaryFiles(in root: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let cutoff = Date().addingTimeInterval(-3600)
        for name in names where name.hasSuffix(".tmp") {
            let path = root.appendingPathComponent(name).path
            if let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
               modified < cutoff {
                unlink(path)
            }
        }
    }

    /// Remove one of our scratch directories. Refuses anything not named like
    /// one (`DuoUpdater-…`): the path comes from a file on disk, and a
    /// recursive delete driven by persisted state gets a shape check, as
    /// `PackageInstaller.discardWorkDirectory` does.
    static func removeScratchDirectory(_ directory: URL) {
        guard directory.lastPathComponent.hasPrefix("DuoUpdater-") else {
            Log.install.error(
                "install journal: refused to remove \(directory.path, privacy: .public) — not a scratch directory of ours")
            return
        }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            Log.install.notice("install journal: removed \(directory.lastPathComponent, privacy: .public), left by a killed install")
        } catch {
            // Logged rather than swallowed: a `uchg` file stops the delete,
            // and a directory left here is re-created on by the next install.
            Log.install.error(
                "install journal: could not remove \(directory.path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    /// Both version fields, from one read of the Info.plist.
    static func versions(at app: URL) -> VersionSide {
        guard let data = try? Data(contentsOf: BundleLayout.infoPlistURL(for: app)),
              let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return VersionSide() }
        return VersionSide(
            marketing: VersionSide.plistVersionField(info["CFBundleShortVersionString"]),
            build: VersionSide.plistVersionField(info["CFBundleVersion"]))
    }

    static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
