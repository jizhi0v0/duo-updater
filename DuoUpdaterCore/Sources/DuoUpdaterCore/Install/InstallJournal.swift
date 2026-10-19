import Foundation
import Security

/// What an install in progress has touched, written down before it touches it,
/// so the next launch can tell what a process that was killed left behind.
///
/// A `kill -9`, a crash or a power cut runs none of an install's `defer`s: its
/// scratch directory stays, a disk image it had attached stays attached until
/// the Mac restarts, and a third party it handed the swap to (brew) may have
/// died on its next write to the pipe we held after moving the old app aside —
/// its revert then likely fails on that same dead pipe — leaving the app gone. The
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
        /// Set when the install entered its commit point (`InstallCommit.run`),
        /// before the body runs: from then on the app is someone's to change.
        /// Nil until then, and in files written before this field existed.
        var committed: Bool? = nil
        /// The other apps with this bundle ID in the app's folder when the
        /// install began — channel siblings such as "DB Browser for SQLite
        /// Nightly.app" or Android Studio's previews. Never taken for where
        /// the update moved the app (`movedCopy`). Nil in files written before
        /// this existed: no app is then taken for a moved one.
        var sameIDSiblings: [String]? = nil
        /// Set by ``Recording/finish()`` on a file it keeps. The install is
        /// over, whether or not the process that wrote it still runs — the
        /// menu-bar app goes on for days after one.
        var ended: Bool? = nil

        var targetSide: VersionSide { VersionSide(marketing: targetVersion, build: targetBuild) }

        /// Whether the install this describes is still running in the
        /// process that wrote it, or in the third party it started. What every
        /// liveness check here asks, so a file `finish` kept never reads as a
        /// running install: its writer may live on, its install does not.
        var ownerIsRunning: Bool { ended != true && owner.isRunning }
        var childIsRunning: Bool { ended != true && child?.isRunning == true }
        var isRunning: Bool { ownerIsRunning || childIsRunning }
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

        /// Record that the install has reached its commit point. Called by
        /// `InstallCommit.run` while this is the current recording, before
        /// the body starts; ``finish()`` reads it.
        func noteCommitted() {
            update { $0.committed = true }
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

        /// The install has ended, whichever way. Idempotent. Call it after
        /// `InstallCoordinator.settleInstallRollbackPoint(for:journal:succeeded:)`,
        /// which reads the files this may remove.
        ///
        /// `succeeded` is the host's own word that the install landed — the
        /// coordinator returned `applied` — passed in, not read off the disk:
        /// a cask whose new version installs under another name leaves the old
        /// path empty after a success (brew's `Moved#delete` removes the whole
        /// folder when the successor has no artifact with the same target —
        /// Homebrew 7.0.9 `cask/artifact/moved.rb`, read from source).
        ///
        /// Normally its file goes. Two endings keep a record instead:
        ///
        /// - It reached its commit point, did not succeed, and the app is left
        ///   missing or unreadable — the ending the settle keeps the rollback
        ///   point for.
        ///   This file stays, marked interrupted and ended, so the point is
        ///   reachable from ``InstallJournal/interruptedInstalls()`` and
        ///   `duo backups restore`, not only from a hidden directory. Before
        ///   the commit point nothing of the app's was touched, so an app
        ///   missing then was missing already — trashed by the user after the
        ///   scan — and offering it back would resurrect a deleted app.
        /// - It ran over an earlier interrupted install of the same app (a
        ///   reinstall is a legitimate way back) and did not leave the app
        ///   verifiably at its target. The earlier files stay: they still
        ///   describe the way back, and nothing of this install replaced it
        ///   (`InstallCoordinator.backUp` and `takeInstallRollbackPoint` skip
        ///   an app whose ``InstallJournal/standing(of:)`` is not clear). When
        ///   it did leave the app verifiably good, they go — except one whose
        ///   scratch directories or mounts were never cleaned (launch
        ///   processing was deferred, or an image would not detach): that
        ///   file is the only thing that still names them, and
        ///   ``InstallJournal/processLeftovers(lock:)`` is what cleans them.
        public func finish(succeeded: Bool) async {
            let mine: Entry? = lock.withLock {
                guard !finished else { return nil }
                finished = true
                return entry
            }
            guard let mine else { return }
            let app = URL(fileURLWithPath: mine.appPath)
            let earlier = InstallJournal.earlierEntries(for: app, excluding: mine.job)
            // A reinstall that moved the app (a renamed cask) left nothing at
            // the old path to verify: verify where it went.
            let moved = succeeded && !BackupStore.hasReadableBundle(at: app)
                ? InstallJournal.movedCopy(
                    of: app, bundleID: mine.bundleID, atLeast: mine.targetSide, excluding: mine.sameIDSiblings)
                : nil
            if !earlier.isEmpty,
               await InstallJournal.isVerifiablyAt(
                   mine.targetSide, app: moved ?? app,
                   wasSigned: InstallJournal.wasSigned([mine] + earlier.map(\.entry))) {
                for (file, entry) in earlier where entry.workDirectories.isEmpty && entry.mounts.isEmpty {
                    unlink(file.path)
                }
                Log.install.notice(
                    "install journal: \(mine.appName, privacy: .public) reinstalled over its interrupted install; cleared")
                // The settle before this kept the old path's rollback point
                // for that install; with it repaired under the new name, the
                // point is no one's way back.
                if let moved {
                    await BackupStore.removeRollbackPoint(forKey: mine.backupKey)
                    Log.install.notice(
                        "install journal: \(mine.appName, privacy: .public) now at \(moved.path, privacy: .public); its old path's rollback point is discarded")
                }
            }
            if earlier.isEmpty, !succeeded, mine.committed == true, !BackupStore.hasReadableBundle(at: app) {
                var kept = mine
                kept.damage = FileManager.default.fileExists(atPath: app.path) ? .unreadable : .missing
                kept.ended = true
                kept.workDirectories = []
                kept.mounts = []
                kept.child = nil
                InstallJournal.write(kept, to: file)
                Log.install.error(
                    "install journal: \(mine.appName, privacy: .public) is \(kept.damage?.rawValue ?? "?", privacy: .public) after its install ended; kept as an interrupted install — \(InstallJournal.wayBackForTheLog(kept), privacy: .public)")
                return
            }
            if unlink(file.path) != 0, errno != ENOENT {
                Log.install.error(
                    "install journal: could not remove \(self.file.lastPathComponent, privacy: .public) — errno \(errno, privacy: .public)")
            }
        }
    }

    // MARK: - Standing of an app

    /// Where an app stands with the journal, for a host about to install it.
    public enum Standing: Sendable, Equatable {
        /// No earlier install of it left anything.
        case clear
        /// An earlier install of it is still running: process `pid` — the
        /// third party it started (an orphaned brew), or another process's
        /// install. Refuse a new one until it has finished.
        case stillRunning(pid: Int32)
        /// An earlier install of it was cut off. A new one may go ahead — a
        /// reinstall is a legitimate way back — but must take no backup and no
        /// rollback point: the bundle is the damaged one, and either copy
        /// would replace the good one the user would restore from (one slot
        /// per app, `replaceItemAt`). `InstallCoordinator.backUp` and
        /// `takeInstallRollbackPoint` refuse it themselves, for every caller.
        case interrupted
    }

    /// Where `app` stands. An entry this process wrote for an install still in
    /// progress here, with no child running, is that install's own and does
    /// not count; one whose child runs does, whoever wrote it. One `finish`
    /// kept is over, and counts as interrupted whoever wrote it.
    public static func standing(of app: URL) -> Standing {
        guard let root else { return .clear }
        let wanted = standardized(app.path)
        var interrupted = false
        for (_, entry) in readAll(in: root) where standardized(entry.appPath) == wanted {
            if entry.childIsRunning, let child = entry.child { return .stillRunning(pid: child.pid) }
            if entry.ownerIsRunning {
                if entry.owner.pid != getpid() { return .stillRunning(pid: entry.owner.pid) }
            } else {
                interrupted = true
            }
        }
        return interrupted ? .interrupted : .clear
    }

    /// Whether `app`'s install rollback point may be discarded now that an
    /// install of it ended with the app readable. False while an earlier
    /// interrupted install of it is on record, unless this process's install
    /// of it left it verifiably at that install's target: the point is the way
    /// back the earlier one left, and a readable bundle is not yet a good one.
    static func mayDiscardRollbackPoint(for app: URL) async -> Bool {
        guard let root else { return true }
        let wanted = standardized(app.path)
        let entries = readAll(in: root).map(\.entry).filter { standardized($0.appPath) == wanted }
        let dead = entries.filter { !$0.isRunning }
        guard !dead.isEmpty else { return true }
        guard let mine = entries.first(where: { $0.ownerIsRunning && $0.owner.pid == getpid() })
        else { return false }
        return await isVerifiablyAt(mine.targetSide, app: app, wasSigned: wasSigned([mine] + dead))
    }

    /// Whether `recording`, this process's install of `app`, has not reached
    /// its commit point, with no earlier install of it on record. Then nothing
    /// of the app's has been touched: an app missing now was removed by
    /// someone else, and a rollback point of it is no install's way back.
    ///
    /// The commit is read from the recording in memory — the same fact
    /// ``Recording/finish(succeeded:)`` reads — not from its file: a note whose
    /// write failed leaves the file saying "not yet" about a commit that ran,
    /// and reading that would discard the only way back. No recording (the
    /// journal is off, or could not be started) answers false: keep.
    static func ownInstallIsBeforeItsCommit(_ recording: Recording?, for app: URL) -> Bool {
        guard let recording else { return false }
        let mine = recording.snapshot
        guard standardized(mine.appPath) == standardized(app.path) else { return false }
        return mine.committed != true && !hasEarlierInstall(of: app, excluding: recording)
    }

    /// Whether an install of `app` other than `recording`'s is on record and
    /// over — classified or not.
    static func hasEarlierInstall(of app: URL, excluding recording: Recording?) -> Bool {
        !earlierEntries(for: app, excluding: recording?.snapshot.job ?? "").isEmpty
    }

    /// The files of earlier installs of `app` that are over — not running
    /// and not `job` — whatever launch processing made of them.
    fileprivate static func earlierEntries(for app: URL, excluding job: String) -> [(file: URL, entry: Entry)] {
        guard let root else { return [] }
        let wanted = standardized(app.path)
        return readAll(in: root).filter {
            $0.entry.job != job && standardized($0.entry.appPath) == wanted && !$0.entry.isRunning
        }
    }

    /// Whether the app these entries describe was signed before any of them
    /// touched it: the EARLIEST one's cdhash. A later one's was read from the
    /// bundle the earlier left damaged — a main executable deleted or cut
    /// short has no cdhash (measured, `InstallJournalTests`), so it reads as
    /// unsigned and would let an unsigned bundle pass for the app as it was.
    static func wasSigned(_ entries: [Entry]) -> Bool {
        entries.min(by: { $0.startedAt < $1.startedAt })?.oldCDHash != nil
    }

    /// Whether `app` is readable, at `target` or later, has the executable its
    /// Info.plist names, and its code signature holds in full — or it is
    /// unsigned and was unsigned before. What "verifiably good" means wherever
    /// a damaged app's way back is about to be discarded, at the end of an
    /// install: so the strict check (``signature(of:strict:)``), not launch
    /// classification's.
    ///
    /// Not necessarily before the app has run: the menu-bar app's
    /// `performInstall` restarts an updated app (`restart(updated)`) before
    /// its settle and `finish` run, and an app that writes into its own
    /// bundle fails this check from then on. The way back is then kept when
    /// it was no longer needed; the next launch's processing classifies with
    /// the lenient check and clears it. How often: measured by the review of
    /// round 3 on the dev Mac (macOS 27.2, 2026-10-18), 9 of 247 installed
    /// apps pass the lenient check and fail this one (LibreOffice, ToDesk,
    /// WeMeeting, aTrust, JetBrains Air: -67054; EasyConnect: 100013; three
    /// ad-hoc signed local builds: -67056). Not re-measured here. The same
    /// review measured Xcode at 10.56 s strict against 0.01 s lenient; this
    /// runs only when an earlier interrupted install of the app is on record.
    static func isVerifiablyAt(_ target: VersionSide, app: URL, wasSigned: Bool) async -> Bool {
        guard BackupStore.hasReadableBundle(at: app) else { return false }
        let onDisk = versions(at: app)
        guard !target.isEmpty, !onDisk.isEmpty, !VersionComparator.isNewer(target, than: onDisk)
        else { return false }
        // An unsigned bundle has no signature to say its executable is
        // missing: one deleted reads as plain "unsigned" (measured).
        guard hasMainExecutable(app) else { return false }
        switch await offCooperativePool(qos: .userInitiated, { signature(of: app, strict: true) }) {
        case .valid: return true
        case .unsigned: return !wasSigned
        case .invalid: return false
        }
    }

    /// Where the app once at `app` is now, when its update moved it: a cask
    /// renamed in its new version ("Foo.app" → "Foo Pro.app") is installed
    /// beside the old path, and the old one is gone. Another app in the same
    /// folder with `bundleID`, readable, with its executable, at exactly
    /// `target` — what the update installs; a channel sibling's version
    /// (DB Browser's Nightly is pinned at 3.13.99) is not that. Nil without a
    /// bundle ID or a target to go by.
    ///
    /// `siblings` are the same-ID apps the folder held when the install began
    /// (``Entry/sameIDSiblings``): a channel sibling already there is never
    /// the moved copy — taking it for one would resolve a missing app as
    /// moved and discard its only way back. Nil (a file from before that was
    /// recorded): nothing is.
    static func movedCopy(
        of app: URL, bundleID: String?, atLeast target: VersionSide, excluding siblings: [String]?
    ) -> URL? {
        guard let siblings, !target.isEmpty else { return nil }
        let before = Set(siblings.map(standardized))
        for candidate in sameIDApps(beside: app, bundleID: bundleID) where !before.contains(standardized(candidate.path)) {
            guard BackupStore.hasReadableBundle(at: candidate), !namesAMissingExecutable(candidate) else { continue }
            let onDisk = versions(at: candidate)
            if !onDisk.isEmpty, !VersionComparator.isNewer(target, than: onDisk),
               !VersionComparator.isNewer(onDisk, than: target) { return candidate }
        }
        return nil
    }

    /// The other apps in `app`'s folder whose Info.plist says `bundleID`.
    /// Read from the file: `Bundle(url:)` caches per URL, and a moved copy was
    /// just written.
    static func sameIDApps(beside app: URL, bundleID: String?) -> [URL] {
        guard let bundleID, !bundleID.isEmpty else { return [] }
        let folder = app.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.sorted().compactMap { name -> URL? in
            guard name.hasSuffix(".app"), name != app.lastPathComponent else { return nil }
            let candidate = folder.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: BundleLayout.infoPlistURL(for: candidate)),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == bundleID
            else { return nil }
            return candidate
        }
    }

    /// Whether the Info.plist names a `CFBundleExecutable` the bundle does not
    /// have. False when it names none, unlike ``hasMainExecutable(_:)``.
    static func namesAMissingExecutable(_ app: URL) -> Bool {
        guard let data = try? Data(contentsOf: BundleLayout.infoPlistURL(for: app)),
              let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let name = info["CFBundleExecutable"] as? String, !name.isEmpty
        else { return false }
        return !hasMainExecutable(app)
    }

    /// Whether the file the Info.plist's `CFBundleExecutable` names exists —
    /// `Contents/MacOS/` for a Mac app, the bundle root of a wrapped iOS app
    /// (``BundleLayout``). False when it names none.
    static func hasMainExecutable(_ app: URL) -> Bool {
        guard let data = try? Data(contentsOf: BundleLayout.infoPlistURL(for: app)),
              let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let name = info["CFBundleExecutable"] as? String, !name.isEmpty
        else { return false }
        let prefix = BundleLayout.interiorPrefix(for: app)
        let relative = prefix == "Contents/" ? "Contents/MacOS/\(name)" : prefix + name
        return FileManager.default.fileExists(atPath: app.appendingPathComponent(relative).path)
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
        var entry = Entry(
            job: job, appID: app.id, appName: app.name, bundleID: app.bundleID,
            appPath: path.path,
            oldVersion: onDisk.marketing ?? app.shortVersion,
            oldBuild: onDisk.build ?? app.buildVersion,
            oldCDHash: cdhash.map(hex),
            targetVersion: target?.marketing, targetBuild: target?.build,
            route: route.rawValue,
            backupKey: BackupStore.key(bundleID: app.bundleID, path: path),
            startedAt: Date(), owner: owner)
        entry.sameIDSiblings = sameIDApps(beside: path, bundleID: app.bundleID).map(\.path)
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
        /// Gone from its path, but at the target version beside it under
        /// another name: a cask renamed in its new version (`movedCopy`).
        case moved
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
        let live = entries.filter { $0.entry.isRunning }
        let liveDirectories = Set(live.flatMap { $0.entry.workDirectories.map(standardized) })

        var processed: [Processed] = []
        for (file, entry) in entries {
            let name = entry.appName
            guard !entry.isRunning else {
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
                    // Read again: the lookup above can take seconds, and an
                    // install in this process (the lock is shared) may have
                    // attached the same image path since.
                    if liveUse().uses(mount) {
                        mountsLeft = true
                    } else if await cleanup.detach(URL(fileURLWithPath: mount.mountPoint), image) {
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
                // Read again, right before the delete, for the same reason as
                // the detach above.
                guard !liveUse().directories.contains(standardized(path)) else { continue }
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
                // A moved app is read where it went, not at the empty old path.
                let readAt = resolution == .moved
                    ? movedCopy(
                        of: URL(fileURLWithPath: entry.appPath), bundleID: entry.bundleID,
                        atLeast: entry.targetSide, excluding: entry.sameIDSiblings)
                    : nil
                let at = readAt ?? URL(fileURLWithPath: entry.appPath)
                Log.install.notice(
                    "install journal: \(name, privacy: .public) [\(entry.bundleID ?? "?", privacy: .public)] via \(entry.route, privacy: .public): its installer process ended before it finished; the app reads \(String(describing: resolution), privacy: .public)\(readAt.map { " to \($0.path)" } ?? "", privacy: .public) (\(versions(at: at).text(withBuild: true), privacy: .public))")
                // The old path's rollback point would be kept for good: the
                // sweep keeps every point whose app does not read there.
                if resolution == .moved {
                    await BackupStore.removeRollbackPoint(forKey: entry.backupKey)
                }
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
                    "install journal: \(name, privacy: .public) at \(entry.appPath, privacy: .public) is \(damage.rawValue, privacy: .public) after an install via \(entry.route, privacy: .public) was cut off — \(wayBackForTheLog(kept), privacy: .public)")
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
            // Not missing: moved. Offering the old version back at the old
            // path would leave two copies and spend the way back. Only on
            // the first look at an install cut off mid-way: a file already
            // found cut off, or kept by `finish`, describes an install that
            // is over, and a same-ID app turning up beside it since (a channel
            // sibling installed after) is no move of it.
            if !FileManager.default.fileExists(atPath: app.path), entry.damage == nil, entry.ended != true {
                if movedCopy(
                    of: app, bundleID: entry.bundleID, atLeast: entry.targetSide, excluding: entry.sameIDSiblings
                ) != nil {
                    return .resolved(.moved)
                }
            }
            return .damaged(FileManager.default.fileExists(atPath: app.path) ? .unreadable : .missing)
        }
        // A bundle copied into place file by file (a move across volumes is a
        // copy) and cut off can have the new Info.plist before the executable
        // it names: that reads as the target version, but does not run. Only
        // an executable the Info.plist names and the bundle lacks counts — an
        // app without `CFBundleExecutable` is not taken for a broken one.
        if namesAMissingExecutable(app) { return .damaged(.unreadable) }
        // The target on disk is an install that landed, whatever its signature
        // says now: a new version that writes into its own bundle fails a
        // resource check from then on, and calling that "interrupted" would
        // offer to put the old version back over a working one.
        let target = entry.targetSide
        let onDisk = versions(at: app)
        if !target.isEmpty, !onDisk.isEmpty, !VersionComparator.isNewer(target, than: onDisk) {
            return .resolved(.completed)
        }
        let cdhash = await offCooperativePool(qos: .userInitiated) {
            CLIToolProcesses.fileCDHash(app.path).map(hex)
        }
        if let old = entry.oldCDHash {
            if cdhash == old { return .resolved(.unchanged) }
            let status = await offCooperativePool(qos: .userInitiated) { signature(of: app) }
            if status != .valid { return .damaged(.signatureBroken) }
        }
        if entry.oldCDHash == nil,
           onDisk == VersionSide(marketing: entry.oldVersion, build: entry.oldBuild) {
            return .resolved(.unchanged)
        }
        return .resolved(.changedElsewhere)
    }

    enum SignatureStatus: Equatable { case valid, unsigned, invalid }

    /// The bundle's code signature: its executable and Info.plist against the
    /// code directory, resources left out (`kSecCSDoNotValidateResources`).
    /// Measured in `InstallJournalTests` on ad-hoc signed fixtures: a resource
    /// the app rewrote passes this and fails the default check; an executable
    /// cut short fails both. So this asks "was the code swapped halfway", and
    /// an app that keeps state inside its own bundle does not read as broken.
    /// Not strict and not deep — not the install gates' question.
    ///
    /// `strict` validates everything instead — sealed resources, nested code
    /// (`kSecCSCheckNestedCode`), every architecture — for the one question
    /// asked right after an install, before the app has run: is this bundle
    /// whole, so the way back to the one before can go. The lenient check
    /// passes a bundle whose sealed nested helper is deleted or cut short;
    /// this one fails both (measured, `InstallJournalTests`).
    static func signature(of app: URL, strict: Bool = false) -> SignatureStatus {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              let code else { return .invalid }
        let flags = strict
            ? kSecCSCheckNestedCode | kSecCSCheckAllArchitectures
            : kSecCSDoNotValidateResources
        let status = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: flags), nil)
        switch status {
        case errSecSuccess: return .valid
        case errSecCSUnsigned: return .unsigned
        default: return .invalid
        }
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

    /// What an interrupted install's row can offer, said in the log line that
    /// records it: a row with no way back has no Restore and no way to dismiss
    /// it (nothing to put back; it goes once the app reads again), and a
    /// report about one is answered from this line.
    static func wayBackForTheLog(_ entry: Entry) -> String {
        guard let source = restoreSource(for: entry) else {
            return "no way back: no rollback point and no backup under \(entry.backupKey); the row offers no Restore"
        }
        let kind = source.purpose == .installRollbackPoint ? "rollback point" : "backup"
        return "way back: \(kind) \(source.version ?? "?") under \(source.key)"
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

    /// The backup keys of every app with a file here — every key its restore
    /// would look under (``restoreSource(for:)``). Not the orphan prune's or
    /// the space reclaim's to delete: an app an install left missing is
    /// exactly what an uninstalled one looks like, and with backups on its
    /// user backup is its only way back (no rollback point is taken then).
    static func journaledBackupKeys() -> Set<String> {
        guard let root else { return [] }
        var keys: Set<String> = []
        for (_, entry) in readAll(in: root) {
            keys.insert(entry.backupKey)
            keys.formUnion(BackupStore.keyCandidates(
                bundleID: entry.bundleID, path: URL(fileURLWithPath: entry.appPath)))
        }
        return keys
    }

    /// Where `app`'s interrupted install would be restored from, read from
    /// the earliest file of an install of it that is over — classified or not.
    /// Nil when there is no such file, or nothing to restore from.
    public static func wayBack(for app: URL) -> RestoreSource? {
        guard let root else { return nil }
        let wanted = standardized(app.path)
        return readAll(in: root).map(\.entry)
            .filter { standardized($0.appPath) == wanted && !$0.isRunning }
            .min(by: { $0.startedAt < $1.startedAt })
            .flatMap(restoreSource(for:))
    }

    /// The scratch directories a running install has recorded, in this
    /// process or another: not the stale-scratch sweep's to take.
    static func liveWorkDirectories() -> Set<String> { liveUse().directories }

    /// What running installs use, read from disk now.
    struct LiveUse {
        var directories: Set<String> = []
        var mountPoints: Set<String> = []
        var images: Set<String> = []

        func uses(_ mount: Mount) -> Bool {
            mountPoints.contains(InstallJournal.standardized(mount.mountPoint))
                || images.contains(InstallJournal.standardized(mount.image))
        }
    }

    static func liveUse() -> LiveUse {
        guard let root else { return LiveUse() }
        var use = LiveUse()
        for (_, entry) in readAll(in: root)
        where entry.isRunning {
            use.directories.formUnion(entry.workDirectories.map(standardized))
            use.mountPoints.formUnion(entry.mounts.map { standardized($0.mountPoint) })
            use.images.formUnion(entry.mounts.map { standardized($0.image) })
        }
        return use
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

    /// Test seam: the directory scratch directories must sit directly in.
    /// Production: the temporary directory every installer creates them in.
    @TaskLocal static var temporaryDirectoryOverride: URL?

    /// Remove one of our scratch directories. Refuses anything not named like
    /// one (`DuoUpdater-…`) or not directly in the temporary directory: the
    /// path comes from a file on disk, and a recursive delete driven by
    /// persisted state gets a shape check, as
    /// `PackageInstaller.discardWorkDirectory` does.
    static func removeScratchDirectory(_ directory: URL) {
        let base = (temporaryDirectoryOverride ?? FileManager.default.temporaryDirectory)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let parent = directory.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard directory.lastPathComponent.hasPrefix("DuoUpdater-"), parent == base else {
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

    /// Both version fields of the bundle at `app`, or nil when its Info.plist
    /// does not read — for a surface saying what an interrupted install left.
    public static func versionOnDisk(at app: URL) -> VersionSide? {
        BackupStore.hasReadableBundle(at: app) ? versions(at: app) : nil
    }

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
