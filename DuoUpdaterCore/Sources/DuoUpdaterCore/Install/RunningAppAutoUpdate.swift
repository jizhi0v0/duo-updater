import Darwin
import Foundation
import IOKit.pwr_mgt

/// Whether an unattended update may quit a *running* app, install, and reopen it.
///
/// Off unless the user turned it on and allowed this app by name: no app is
/// quit on a guess about what it is. Every rule below leans toward leaving the
/// app alone, because a wrong "yes" closes something a person was using and a
/// wrong "no" only waits for the next check.
///
/// - The version must have been known for `releaseCooldown`. A broken or
///   pulled release is usually replaced within that window, and an app that
///   releases several times a day is then quit at most for the newest one.
/// - At most one quit per app per `quitSpacing`, whatever the outcome.
/// - The app must look unused: not in front, not brought to front for
///   `idleThreshold`, holding no power assertion (calls, playback, recording,
///   downloads and builds usually hold one), and with no child process from
///   outside its bundle (a terminal's shell, a build tool).
/// - The person must look away: no input for `userAwayThreshold`, or the
///   screen locked. A quit then never lands under someone's cursor.
/// - A quit the app refuses or ignores ends the attempts for that version: it
///   most likely put up a save prompt, and asking again would stack prompts.
///   Any other failure after a quit counts toward `maxFailures`.
public enum RunningAppAutoUpdate {
    public static var idleThreshold: TimeInterval { devThreshold ?? 60 * 60 }
    public static var userAwayThreshold: TimeInterval { devThreshold ?? 15 * 60 }
    public static var releaseCooldown: TimeInterval { devThreshold ?? 24 * 60 * 60 }
    public static var quitSpacing: TimeInterval { devThreshold ?? 24 * 60 * 60 }
    public static let maxFailures = 3

    /// Local builds only (`DUO_DEV_HOOKS`; `check-no-dev-hooks.sh` keeps it out
    /// of a release): `defaults write com.duoupdater.app
    /// DUO_RUNNING_APP_TEST_THRESHOLD -float 60` replaces all four durations
    /// above, so a real-machine run does not wait a day.
    static var devThreshold: TimeInterval? {
        #if DUO_DEV_HOOKS
        let value = UserDefaults.standard.double(forKey: "DUO_RUNNING_APP_TEST_THRESHOLD")
        return value > 0 ? value : nil
        #else
        return nil
        #endif
    }

    /// One install's history with the version it is being offered.
    public struct Entry: Codable, Equatable, Sendable {
        public var version: String
        /// When DuoUpdater first saw this version offered. Never earlier than
        /// the vendor's publish date, so the cooldown is never shorter than stated.
        public var firstSeen: Date
        public var failures: Int
        /// Set by a refused quit or the last allowed failure. Cleared by a new version.
        public var gaveUp: Bool
        /// Kept across versions: the once-a-day cap is about the person, not the release.
        public var lastQuit: Date?

        public init(version: String, firstSeen: Date, failures: Int = 0,
                    gaveUp: Bool = false, lastQuit: Date? = nil) {
            self.version = version
            self.firstSeen = firstSeen
            self.failures = failures
            self.gaveUp = gaveUp
            self.lastQuit = lastQuit
        }
    }

    /// Per-install entries, keyed by the install's preference key.
    public struct Ledger: Codable, Equatable, Sendable {
        public var entries: [String: Entry]
        public init(entries: [String: Entry] = [:]) { self.entries = entries }

        /// The entry for `version`, starting a fresh one when the offered
        /// version changed: a new release resets the cooldown and the failures.
        public mutating func observe(_ key: String, version: String, now: Date) -> Entry {
            if let entry = entries[key], entry.version == version { return entry }
            let entry = Entry(version: version, firstSeen: now, lastQuit: entries[key]?.lastQuit)
            entries[key] = entry
            return entry
        }

        public mutating func recordQuit(_ key: String, now: Date) {
            entries[key]?.lastQuit = now
        }

        public mutating func recordQuitRefused(_ key: String) {
            entries[key]?.gaveUp = true
        }

        public mutating func recordFailure(_ key: String) {
            guard var entry = entries[key] else { return }
            entry.failures += 1
            if entry.failures >= RunningAppAutoUpdate.maxFailures { entry.gaveUp = true }
            entries[key] = entry
        }

        /// Drop entries for installs that are no longer offered anything, so
        /// the ledger does not grow without bound. Their `lastQuit` goes too,
        /// which can only matter if a new version arrives within a day of a
        /// quit that already installed the previous one, and the cooldown still
        /// holds that one back for a day.
        public mutating func retain(keys: Set<String>) {
            entries = entries.filter { keys.contains($0.key) }
        }
    }

    /// What the system says about the app and the person right now.
    public struct Signals: Equatable, Sendable {
        public var isFrontmost: Bool
        /// The latest of: when DuoUpdater started watching, when the app was
        /// launched, and when it was last brought to front or left it.
        public var lastUsed: Date
        public var userIdle: TimeInterval
        public var screenLocked: Bool
        /// The name of a power assertion one of its processes holds, if any.
        public var busyAssertion: String?
        public var hasForeignChild: Bool

        public init(isFrontmost: Bool, lastUsed: Date, userIdle: TimeInterval, screenLocked: Bool,
                    busyAssertion: String?, hasForeignChild: Bool) {
            self.isFrontmost = isFrontmost
            self.lastUsed = lastUsed
            self.userIdle = userIdle
            self.screenLocked = screenLocked
            self.busyAssertion = busyAssertion
            self.hasForeignChild = hasForeignChild
        }
    }

    public enum Verdict: Equatable, Sendable {
        case quitAndUpdate
        case wait(Reason)
    }

    public enum Reason: Equatable, Sendable {
        case gaveUp
        case cooldown
        case quitToday
        case frontmost
        case recentlyUsed
        case personPresent
        case busy(String)
        case childProcess

        /// The reason as the Events list shows it.
        public var message: String {
            switch self {
            case .gaveUp:
                return "The app did not quit, or updating it failed \(RunningAppAutoUpdate.maxFailures) times. Waiting for a newer version."
            case .cooldown:
                return "The app is running, and this version is less than a day old."
            case .quitToday:
                return "The app is running, and it was already quit for an update in the last day."
            case .frontmost:
                return "The app is running and in front."
            case .recentlyUsed:
                return "The app is running and was used in the last hour."
            case .personPresent:
                return "The app is running, and the Mac is in use."
            case .busy(let name):
                return "The app is running and busy (\(name))."
            case .childProcess:
                return "The app is running a process of its own, such as a shell or a build."
            }
        }
    }

    /// Cheapest and most stable reasons first, so the Events list says the
    /// same thing on every pass until that reason goes away.
    public static func decide(entry: Entry, signals: Signals, now: Date) -> Verdict {
        if entry.gaveUp { return .wait(.gaveUp) }
        if now.timeIntervalSince(entry.firstSeen) < releaseCooldown { return .wait(.cooldown) }
        if let lastQuit = entry.lastQuit, now.timeIntervalSince(lastQuit) < quitSpacing {
            return .wait(.quitToday)
        }
        if signals.isFrontmost { return .wait(.frontmost) }
        if now.timeIntervalSince(signals.lastUsed) < idleThreshold { return .wait(.recentlyUsed) }
        if !signals.screenLocked && signals.userIdle < userAwayThreshold { return .wait(.personPresent) }
        if let name = signals.busyAssertion { return .wait(.busy(name)) }
        if signals.hasForeignChild { return .wait(.childProcess) }
        return .quitAndUpdate
    }

    // MARK: - Reading the signals

    /// `UserIsActive` is a "the user touched something" tickle, not work in
    /// progress, so it never makes an app busy.
    static let ignoredAssertionTypes: Set<String> = ["UserIsActive"]

    /// The name of the first assertion owned by, or taken on behalf of, one of
    /// `pids`. Audio capture is the case "on behalf of" exists for: coreaudiod
    /// holds the assertion and names the app in `AssertionOnBehalfOfPID`
    /// (read with `IOPMCopyAssertionsByProcess` on macOS 27, 2026-11-07; the key
    /// is not in the public header).
    static func busyAssertion(in byPID: [Int: [[String: Any]]], pids: Set<pid_t>) -> String? {
        for (owner, assertions) in byPID.sorted(by: { $0.key < $1.key }) {
            for assertion in assertions {
                let type = assertion["AssertType"] as? String ?? ""
                guard !ignoredAssertionTypes.contains(type) else { continue }
                let onBehalf = (assertion["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value
                guard pids.contains(pid_t(owner)) || onBehalf.map(pids.contains) == true else { continue }
                return assertion["AssertName"] as? String ?? type
            }
        }
        return nil
    }

    /// Every power assertion on the system, by owning pid. Empty if the call fails,
    /// which reads as "not busy": the other signals still have to agree.
    public static func liveAssertions() -> [Int: [[String: Any]]] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let dict = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [:] }
        var result: [Int: [[String: Any]]] = [:]
        for (pid, assertions) in dict { result[pid.intValue] = assertions }
        return result
    }

    public static func busyAssertion(pids: Set<pid_t>) -> String? {
        busyAssertion(in: liveAssertions(), pids: pids)
    }

    /// A process started by the app that is not part of it — a shell in a
    /// terminal or an editor, a compiler, `ssh`. Helpers inside the bundle are
    /// part of the app and quit with it.
    ///
    /// Children are asked of the kernel per parent (`proc_listchildpids`), not
    /// read off `processes`: a terminal's `/usr/bin/login` runs as root, and
    /// `PROC_PIDTBSDINFO` refuses it (EPERM), so the process list carries it with
    /// parent 0 and it looks like nobody's child. Measured on Ghostty 1.3.1,
    /// macOS 27, 2026-11-08: a real-machine run quit Ghostty with a shell open
    /// because of exactly that.
    public static func hasForeignChild(
        of bundle: URL, processes: [NestedAppGuard.RunningProcess],
        children: (pid_t) -> [pid_t] = childPIDs
    ) -> Bool {
        let own = Set(processes.filter {
            AutomaticInstall.hasRunningProcess(at: bundle, processes: [$0])
        }.map(\.pid))
        return own.contains { parent in children(parent).contains { !own.contains($0) } }
    }

    public static func childPIDs(_ parent: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 512)
        let count = Int(proc_listchildpids(parent, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size)))
        return count > 0 ? Array(buffer.prefix(min(count, buffer.count))) : []
    }
}
