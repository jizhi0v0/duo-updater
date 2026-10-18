import Foundation

/// Did the build we just put into effect survive the relaunch?
///
/// The restart that applies our install is a quit, and a quit is exactly what
/// an app's own updater parks on. On the mini 2026-08-22 ChatGPT's Sparkle had
/// 41509 staged and its `Autoupdate` waiting; we installed 41705, quit to
/// relaunch, and `Autoupdate` woke 3 ms after the app died. About 35 s later
/// the disk read 41509 again. Squirrel's ShipIt does the same with a whole
/// bundle swap. `RestartStandoff` holds the quit back when it can see the
/// staged build before the quit, but not every updater is visible then —
/// Sparkle 1's `Autoupdate.app` only starts once the quit has begun — and the
/// install's own landing check (`appliedNothing`) runs before the quit, when
/// the disk is still right. This is the read after.
///
/// It watches the bundle for a bounded window after the relaunch and answers
/// one of three things; see `Verdict`.
///
/// Known limit: "older" is `VersionComparator`'s ordering, so a vendor whose
/// version field is not a version — a commit hash where the marketing string
/// goes, like Ghostty's tip builds (`663205b5 (2024-12-20)`) — can order a
/// newer build below an older one, and a relaunch onto it would read as a
/// revert. Not handled here.
public enum RelaunchRecheck {

    /// One read of the bundle: both version fields off its `Info.plist`, and
    /// the bundle directory's inode, which changes when the bundle is swapped
    /// for another rather than written in place.
    public struct Reading: Sendable, Equatable {
        public var side: VersionSide
        public var inode: UInt64?
        public init(side: VersionSide, inode: UInt64? = nil) {
            self.side = side
            self.inode = inode
        }
    }

    public enum Verdict: Sendable, Equatable {
        /// What we installed (or something newer) stayed on disk.
        case held
        /// The disk went backwards: it now holds `to`, older than what was on
        /// disk before the quit. `bundleSwapped` says the bundle directory itself
        /// was replaced (ShipIt's swap) rather than written over.
        ///
        /// `byOwnUpdater` is whether this can be put down to the app's own
        /// updater: an installer was seen parked on the quit, or the bundle was
        /// swapped whole. Without either there is no evidence of who wrote it —
        /// a hand-copied older bundle written in place reads the same — and the
        /// caller must not name the updater.
        case reverted(to: VersionSide, bundleSwapped: Bool, byOwnUpdater: Bool)
        /// The window ran out with nothing decisive — the installer was still
        /// alive, or the bundle could not be read at the end — or another
        /// process took the install lock during the watch (`duo backups
        /// restore`, `duo install`), which makes any change it sees that
        /// process's, not the app's updater's. Nothing is said to the user on
        /// this.
        case unknown
    }

    /// The polling schedule.
    public struct Timing: Sendable, Equatable {
        /// Between reads.
        public var interval: Duration
        /// How long after the relaunch to keep reading. The revert measured on
        /// ChatGPT (2026-08-22, see the type's doc) landed about 35 s after the
        /// quit; 60 s covers that with room to spare without keeping a watch on
        /// every restart for long.
        public var window: Duration
        /// Consecutive reads that must agree with what we installed, after the
        /// installer is gone, before the watch stops early.
        public var settleReads: Int

        public init(interval: Duration = .seconds(2), window: Duration = .seconds(60), settleReads: Int = 3) {
            self.interval = interval
            self.window = window
            self.settleReads = settleReads
        }

        /// Reads in a full window — one per `interval`, the first after the
        /// first sleep.
        public var maxReads: Int { max(1, Int((window / interval).rounded(.down))) }
    }

    /// The reads and the sleep, injectable so the tests run without a clock.
    public struct System: Sendable {
        public var read: @Sendable () async -> Reading?
        public var sleep: @Sendable (Duration) async -> Void
        /// Whether a process other than this one holds the machine-wide install
        /// lock (`InstallLock`).
        public var installLockHeldElsewhere: @Sendable () -> Bool
        public var installer: ParkedInstallerProbe.System

        public init(
            read: @escaping @Sendable () async -> Reading?,
            sleep: @escaping @Sendable (Duration) async -> Void,
            installLockHeldElsewhere: @escaping @Sendable () -> Bool = { false },
            installer: ParkedInstallerProbe.System
        ) {
            self.read = read
            self.sleep = sleep
            self.installLockHeldElsewhere = installLockHeldElsewhere
            self.installer = installer
        }

        /// `installer` is passed in so the caller's deadline on `launchctl`
        /// (`ParkedInstallerProbe.System.live(launchctlDeadline:)`) also covers
        /// the liveness checks made here.
        public static func live(bundle: URL, installer: ParkedInstallerProbe.System) -> System {
            System(
                read: { RelaunchRecheck.read(bundle) },
                sleep: { try? await Task.sleep(for: $0) },
                // Lock-free: `currentHolder` would take the lock for a moment
                // to test it and could make a real install's `acquire` fail.
                installLockHeldElsewhere: { InstallLock.recordedHolderElsewhere() != nil },
                installer: installer)
        }
    }

    /// Whether a "went back to an older build" note still describes the disk:
    /// `disk` (read now) is older than `expected` (read before the quit). The
    /// note's own retraction asks this rather than trusting the row, because a
    /// check round can publish a row scanned before the revert (`.upToDate`)
    /// while the older build sits on disk. An unreadable bundle keeps the note —
    /// a swap in progress is no evidence the revert is gone.
    public static func revertStillOnDisk(expected: Reading, disk: Reading?) -> Bool {
        guard let disk else { return true }
        return VersionComparator.isNewer(expected.side, than: disk.side)
    }

    /// The bundle as it stands now; nil while its `Info.plist` cannot be read
    /// (mid-swap, or gone).
    public static func read(_ bundle: URL) -> Reading? {
        let side = StagedRelaunch.diskVersionSide(bundle)
        guard !side.isEmpty else { return nil }
        let inode = ((try? FileManager.default.attributesOfItem(atPath: bundle.path))?[.systemFileNumber]
            as? NSNumber)?.uint64Value
        return Reading(side: side, inode: inode)
    }

    /// Watch the bundle after a relaunch.
    ///
    /// - Parameters:
    ///   - expected: the bundle as read just before the quit — what we mean to
    ///     have put into effect.
    ///   - installer: the app's own installer, found before the quit
    ///     (`ParkedInstallerProbe.find`), or nil when none was visible.
    ///
    /// The rules, per read:
    ///   - Older than `expected` (`VersionComparator.isNewer`, marketing first,
    ///     builds on a tie — never string inequality) → `.reverted` at once. No
    ///     installer writes an older build and then a newer one, so there is
    ///     nothing to wait for.
    ///   - The same or newer (`hasReached`) → a read that held.
    ///   - Unreadable, or nothing comparable → neither; it restarts the settle
    ///     count (a bundle moved away mid-swap reads like this).
    ///
    /// The watch stops early, `.held`, after `settleReads` held reads in a row
    /// once the move it was waiting for is over: the installer found before the
    /// quit has exited, or — with no installer in sight — the bundle was swapped
    /// (new inode) for one that holds. With no installer seen and no swap, the
    /// whole window is read: that is Sparkle 1, whose installer only appears
    /// after the quit. At the end of the window: `.unknown` while the installer
    /// still runs or the last read did not hold, `.held` otherwise.
    public static func watch(
        expected: Reading, installer: ParkedInstallerProbe?,
        timing: Timing = .init(), system: System
    ) async -> Verdict {
        var installer = installer
        var installerAlive = installer != nil
        var settled = 0
        var lastHeld = false
        for _ in 0..<timing.maxReads {
            if Task.isCancelled { return .unknown }
            await system.sleep(timing.interval)
            if Task.isCancelled { return .unknown }
            guard let now = await system.read() else {
                settled = 0
                lastHeld = false
                continue
            }
            // After the read, so a change the read saw is judged against the
            // lock as it stood then.
            if system.installLockHeldElsewhere() { return .unknown }
            let swapped = expected.inode != nil && now.inode != nil && now.inode != expected.inode
            if VersionComparator.isNewer(expected.side, than: now.side) {
                return .reverted(
                    to: now.side, bundleSwapped: swapped, byOwnUpdater: installer != nil || swapped)
            }
            guard VersionComparator.hasReached(expected.side, disk: now.side) else {
                settled = 0
                lastHeld = false
                continue
            }
            lastHeld = true
            if var probe = installer {
                installerAlive = await probe.isAlive(system: system.installer)
                installer = probe
            }
            let moveIsOver = installer != nil ? !installerAlive : swapped
            settled = moveIsOver ? settled + 1 : 0
            if settled >= timing.settleReads { return .held }
        }
        return lastHeld && !installerAlive ? .held : .unknown
    }
}
