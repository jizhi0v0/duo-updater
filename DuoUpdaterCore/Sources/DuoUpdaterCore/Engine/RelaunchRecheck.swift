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
        /// The disk went backwards: it now holds `to`, older than what we
        /// installed. `bundleSwapped` says the bundle directory itself was
        /// replaced (ShipIt's swap) rather than written over.
        case reverted(to: VersionSide, bundleSwapped: Bool)
        /// The window ran out with nothing decisive — the installer was still
        /// alive, or the bundle could not be read at the end. Nothing is said
        /// to the user on this.
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
        public var installer: ParkedInstallerProbe.System

        public init(
            read: @escaping @Sendable () async -> Reading?,
            sleep: @escaping @Sendable (Duration) async -> Void,
            installer: ParkedInstallerProbe.System
        ) {
            self.read = read
            self.sleep = sleep
            self.installer = installer
        }

        public static func live(bundle: URL) -> System {
            System(
                read: { RelaunchRecheck.read(bundle) },
                sleep: { try? await Task.sleep(for: $0) },
                installer: .live)
        }
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
            let swapped = expected.inode != nil && now.inode != nil && now.inode != expected.inode
            if VersionComparator.isNewer(expected.side, than: now.side) {
                return .reverted(to: now.side, bundleSwapped: swapped)
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
