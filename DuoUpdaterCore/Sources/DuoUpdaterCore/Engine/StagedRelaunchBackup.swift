import Foundation

/// The rollback point a Relaunch takes before it quits an app so the app's own
/// updater (ShipIt, Sparkle, Spotify's) can apply a build it already downloaded.
///
/// Our own installs back up before every route. A Relaunch did not, so an update
/// applied that way never reached the Rollback list or the bundle diff, and the
/// backup that was there — from an earlier install of ours — was now two versions
/// behind. These are the two decisions around taking one, and `take`, which
/// runs them around the copy for both the menu-bar app and `duo restart`; the
/// copy itself is `InstallCoordinator.backUp`, the same call the install path
/// makes.
public enum StagedRelaunchBackup {

    /// Whether to take a rollback point before quitting the app.
    ///
    /// Not when the user turned backups off. And not when the bundle on disk has
    /// already moved past the version the row was built from: the row is a
    /// snapshot from the last scan, and the apps that reach Relaunch are exactly
    /// the ones that replace themselves. A copy taken then would hold the NEW
    /// build under the OLD version's label, and "roll back" would restore the
    /// update it claims to undo.
    ///
    /// An unreadable bundle is not a landing (`RelaunchProgress.hasLanded` fails
    /// closed), so it still gets an attempt — and `backUp` then reports that it
    /// could not read it, rather than this silently skipping.
    public static func shouldTake(
        keepBackups: Bool, old: VersionSide, disk: VersionSide, buildIsDerived: Bool
    ) -> Bool {
        guard keepBackups else { return false }
        return !RelaunchProgress.hasLanded(old: old, disk: disk, buildIsDerived: buildIsDerived)
    }

    /// Whether the copy just taken is a copy of one build, so it can be kept and
    /// the relaunch can go on.
    ///
    /// The copy takes seconds (`InstallCoordinator.wantsBackup` records Word at
    /// ~8.7s to clone plus ~8.7s to fingerprint; quoted, not re-measured), and the swap-on-quit updaters are waiting for the app to quit — a ShipIt
    /// with the running-instances check for every instance to be gone
    /// (`StagedUpdater.shipIt`), Sparkle 2 for the one instance it
    /// registered (`StagedUpdater`). A user who quits it themselves during that
    /// window lets the updater rewrite the bundle while `ditto` is still reading
    /// it. The manifest is computed from the copy, so a torn copy would verify
    /// against itself and restore cleanly into a broken app.
    ///
    /// So a copy is intact only if every instance that was running when it
    /// started is still running when it ended (none quit — including the one
    /// Sparkle watches — so no swap-on-quit could have started), and the bundle on disk still has not moved past the
    /// version we copied (no updater swapped it in place either). A reopened app
    /// has new process ids, so quit-and-reopen during the copy is not intact
    /// either. An empty `runningBefore` proves nothing and is not intact.
    ///
    /// When this is false the caller also stands down rather than quitting: the
    /// user has taken the relaunch into their own hands, and whatever is running
    /// now may already be the new build.
    public static func isIntact(
        runningBefore: Set<pid_t>, runningAfter: Set<pid_t>,
        old: VersionSide, diskAfter: VersionSide, buildIsDerived: Bool
    ) -> Bool {
        guard !runningBefore.isEmpty, runningBefore.isSubset(of: runningAfter) else { return false }
        return !RelaunchProgress.hasLanded(old: old, disk: diskAfter, buildIsDerived: buildIsDerived)
    }
}

extension StagedRelaunchBackup {

    /// What `take` did.
    public enum Taken: Sendable, Equatable {
        /// No copy attempted: backups are off, or the bundle on disk is already
        /// past the version the caller saw (`shouldTake`).
        case skipped
        /// Another process holds the machine-wide install lock. The relaunch
        /// goes on without a rollback point — the same trade a failed copy makes.
        case lockRefused
        /// The copy was attempted and the app is still up on the build it
        /// started on, so the relaunch goes on.
        case attempted(InstallCoordinator.BackupOutcome)
        /// The app quit, or its bundle moved, while the copy ran: the user has
        /// taken over and its own updater may be swapping now. A copy this
        /// attempt stored has been removed (`discarded`); the caller stands
        /// down instead of quitting whatever runs now.
        case standDown(discarded: Bool)
    }

    /// The system calls `take` makes, injectable for tests.
    public struct System: Sendable {
        public var diskVersion: @Sendable () async -> VersionSide
        /// The pids of the app's running instances, by bundle path.
        public var runningPIDs: @Sendable () -> Set<pid_t>
        public var claimLock: @Sendable () async throws -> Void
        public var releaseLock: @Sendable () async -> Void
        /// The copy itself.
        public var backUp: @Sendable () async -> InstallCoordinator.BackupOutcome
        /// Delete the copy just stored.
        public var remove: @Sendable () async -> Void

        public init(
            diskVersion: @escaping @Sendable () async -> VersionSide,
            runningPIDs: @escaping @Sendable () -> Set<pid_t>,
            claimLock: @escaping @Sendable () async throws -> Void,
            releaseLock: @escaping @Sendable () async -> Void,
            backUp: @escaping @Sendable () async -> InstallCoordinator.BackupOutcome,
            remove: @escaping @Sendable () async -> Void
        ) {
            self.diskVersion = diskVersion
            self.runningPIDs = runningPIDs
            self.claimLock = claimLock
            self.releaseLock = releaseLock
            self.backUp = backUp
            self.remove = remove
        }

        /// The real machine. `backUp` is the caller's: the menu-bar app wraps
        /// `InstallCoordinator.backUp` with its row notes, the CLI calls it bare.
        ///
        /// **Route.** Callers pass `.sparkle`, not `InstallCoordinator.route(for:)`:
        /// that says how WE would install the app, and here we install nothing.
        /// `backUp` reads the route for two restore-time warnings only, and both
        /// describe the wrong thing here — `.installer` would warn that a pkg's
        /// helpers stay newer, `.appStore` that the store will re-apply the
        /// update; neither applied this one. The app's own updater did, which is
        /// what `.sparkle` records: neither flag. Its one blind spot: an updater
        /// parked with staging we cannot read may be about to run a package.
        public static func live(
            for app: InstalledApp,
            backUp: @escaping @Sendable () async -> InstallCoordinator.BackupOutcome
        ) -> System {
            System(
                diskVersion: {
                    let path = app.path
                    return await Task.detached(priority: .utility) {
                        StagedRelaunch.diskVersionSide(path)
                    }.value
                },
                runningPIDs: { Set(AppRestarter.runningInstances(of: app).map(\.processIdentifier)) },
                claimLock: { try await ProcessInstallLock.shared.claim() },
                releaseLock: { await ProcessInstallLock.shared.release() },
                backUp: backUp,
                remove: {
                    let key = BackupStore.key(bundleID: app.bundleID, path: app.path)
                    // Deletes a whole bundle copy: Dispatch, as `deleteBackups` does.
                    await offCooperativePool(qos: .utility) { BackupStore.remove(forKey: key) }
                })
        }
    }

    /// Take the rollback point a Relaunch owes the user before it quits the app
    /// for the app's own updater — the menu-bar app's Relaunch and `duo restart`
    /// both run this, so neither can drift from the other.
    ///
    /// **Lock.** Held around the copy exactly as an install holds it around its
    /// backup: the other host writes the same backup store, and
    /// `BackupStore.save` sweeps other staging directories for the same key.
    ///
    /// - Parameters:
    ///   - old: what the caller saw installed — the PAIR (see `quitAndAwait`).
    ///   - runningBefore: the instances seen running before the copy.
    public static func take(
        _ app: InstalledApp, keepBackups: Bool, old: VersionSide,
        runningBefore: Set<pid_t>, system: System
    ) async -> Taken {
        let buildIsDerived = AppScanner.buildVersionIsOverridden(bundleID: app.bundleID)
        guard shouldTake(
            keepBackups: keepBackups, old: old, disk: await system.diskVersion(),
            buildIsDerived: buildIsDerived) else {
            if keepBackups {
                Log.install.notice("relaunch-staged backup skipped: \(app.name, privacy: .public) on disk is already past \(old.text(withBuild: true), privacy: .public)")
            }
            return .skipped
        }
        do {
            try await system.claimLock()
        } catch {
            Log.install.error("relaunch-staged backup blocked by the machine install lock: \(app.name, privacy: .public) — relaunching without a rollback point")
            return .lockRefused
        }
        let outcome = await system.backUp()
        let intact = isIntact(
            runningBefore: runningBefore, runningAfter: system.runningPIDs(),
            old: old, diskAfter: await system.diskVersion(), buildIsDerived: buildIsDerived)
        var discarded = false
        if !intact {
            Log.install.notice("relaunch-staged: \(app.name, privacy: .public) quit or changed during its backup — standing down")
            // Only a copy this attempt stored is suspect. A failed or unreadable
            // one never replaced the previous backup, which must survive.
            switch outcome {
            case .saved, .savedWithoutRuntimeState:
                await system.remove()
                discarded = true
                Log.install.error("relaunch-staged: discarded \(app.name, privacy: .public)'s backup — its bundle may have been swapped mid-copy")
            case .unreadable, .insufficientSpace, .cancelled, .failed:
                break
            }
        }
        await system.releaseLock()
        return intact ? .attempted(outcome) : .standDown(discarded: discarded)
    }
}
