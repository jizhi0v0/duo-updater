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
/// - The install must have been out of date for `delay` (chosen in Settings,
///   minutes), counted from when DuoUpdater first saw it behind or from its last
///   quit for an update, whichever is later. A newer release does not restart
///   the count: an app that releases every few minutes would otherwise never be
///   updated. When the delay is up, the newest version is installed, so a
///   release pulled and replaced within the delay is skipped.
/// - Counting from the last quit also spaces quits at least `delay` apart,
///   however often the app releases.
/// - The app must look unused: not in front, not brought to front for
///   `idleThreshold`, holding no power assertion (calls, playback, recording,
///   downloads and builds usually hold one), and with no child process from
///   outside its bundle (a terminal's shell, a build tool).
/// - The person must look away: no input for `userAwayThreshold`, or the
///   screen locked. A quit then never lands under someone's cursor.
/// - A quit the app refuses or ignores ends the attempts for that version: it
///   most likely put up a save prompt, and asking again would stack prompts.
///   Any other failure after a quit counts toward `maxFailures`.
/// - After a refused quit or a failed update, nothing is tried for
///   `retryBackoff`, whatever version comes next. A newer release clears the
///   give-up, and an app that releases every few minutes would otherwise be
///   asked again while its save prompt is still up, or quit again and again
///   for an install that keeps failing.
public enum RunningAppAutoUpdate {
    public static var idleThreshold: TimeInterval { devThreshold ?? 60 * 60 }
    public static var userAwayThreshold: TimeInterval { devThreshold ?? 15 * 60 }
    public static var retryBackoff: TimeInterval { devThreshold ?? 24 * 60 * 60 }
    /// The delays Settings offers, in minutes.
    public static let delayChoices = [15, 30, 60]
    public static let defaultDelayMinutes = 30
    public static let maxFailures = 3

    /// Local builds only (`DUO_DEV_HOOKS`; `check-no-dev-hooks.sh` keeps it out
    /// of a release): `defaults write com.duoupdater.app
    /// DUO_RUNNING_APP_TEST_THRESHOLD -float 60` replaces the delay, both thresholds
    /// and the back-off, so a real-machine run does not wait a day.
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
        /// The newest version offered.
        public var version: String
        /// When DuoUpdater first saw this install offered any update. Kept when a
        /// newer version replaces the offered one. Never earlier than the first
        /// pending release's publish date, so the delay is never shorter than stated.
        public var behindSince: Date
        public var failures: Int
        /// Set by a refused quit or the last allowed failure. Cleared by a new version.
        public var gaveUp: Bool
        /// Kept across versions: the spacing between quits is about the person,
        /// not the release.
        public var lastQuit: Date?
        /// Set by a refused quit or a failed update; kept across versions.
        public var retryAfter: Date?

        /// `behindSince` keeps its stored name from when it meant "this version
        /// first seen", so ledgers written by earlier builds still decode.
        enum CodingKeys: String, CodingKey {
            case version, behindSince = "firstSeen", failures, gaveUp, lastQuit, retryAfter
        }

        public init(version: String, behindSince: Date, failures: Int = 0,
                    gaveUp: Bool = false, lastQuit: Date? = nil, retryAfter: Date? = nil) {
            self.version = version
            self.behindSince = behindSince
            self.failures = failures
            self.gaveUp = gaveUp
            self.lastQuit = lastQuit
            self.retryAfter = retryAfter
        }
    }

    /// Per-install entries, keyed by the install's preference key.
    public struct Ledger: Codable, Equatable, Sendable {
        public var entries: [String: Entry]
        public init(entries: [String: Entry] = [:]) { self.entries = entries }

        /// The entry for `key` offered `version`. A newer version clears the
        /// failures and the give-up, which were about the old one, and keeps
        /// `behindSince`, `lastQuit` and `retryAfter`, which are about the install.
        public mutating func observe(_ key: String, version: String, now: Date) -> Entry {
            guard var entry = entries[key] else {
                let entry = Entry(version: version, behindSince: now)
                entries[key] = entry
                return entry
            }
            if entry.version != version {
                entry.version = version
                entry.failures = 0
                entry.gaveUp = false
                entries[key] = entry
            }
            return entry
        }

        public mutating func recordQuit(_ key: String, now: Date) {
            entries[key]?.lastQuit = now
        }

        public mutating func recordQuitRefused(_ key: String, now: Date) {
            entries[key]?.gaveUp = true
            entries[key]?.retryAfter = now.addingTimeInterval(RunningAppAutoUpdate.retryBackoff)
        }

        public mutating func recordFailure(_ key: String, now: Date) {
            guard var entry = entries[key] else { return }
            entry.failures += 1
            if entry.failures >= RunningAppAutoUpdate.maxFailures { entry.gaveUp = true }
            entry.retryAfter = now.addingTimeInterval(RunningAppAutoUpdate.retryBackoff)
            entries[key] = entry
        }

        /// Drop entries for installs that are no longer offered anything: they
        /// caught up, so the next update starts a new count. Their `lastQuit`
        /// goes too, which costs nothing: the new entry's `behindSince` is after
        /// that quit, so the delay still spaces the next quit from it. So does
        /// `retryAfter`: an install no longer offered anything was updated.
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
        /// A refused quit or failed update less than `retryBackoff` ago.
        case retryLater
        /// Out of date for less than the delay, in minutes.
        case delay(Int)
        /// Quit for an update less than the delay ago, in minutes.
        case recentlyQuit(Int)
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
            case .retryLater:
                return "The app did not quit, or updating it failed, in the last day. Trying again after that."
            case .delay(let minutes):
                return "The app is running, and its update has been waiting less than \(minutes) minutes."
            case .recentlyQuit(let minutes):
                return "The app is running, and it was quit for an update less than \(minutes) minutes ago."
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
    /// `delayMinutes` is the Settings choice; a local build's test threshold
    /// replaces it (`devThreshold`).
    public static func decide(entry: Entry, signals: Signals, now: Date, delayMinutes: Int) -> Verdict {
        let delay = devThreshold ?? TimeInterval(delayMinutes * 60)
        if entry.gaveUp { return .wait(.gaveUp) }
        if let retryAfter = entry.retryAfter, now < retryAfter { return .wait(.retryLater) }
        if now.timeIntervalSince(entry.behindSince) < delay { return .wait(.delay(delayMinutes)) }
        if let lastQuit = entry.lastQuit, now.timeIntervalSince(lastQuit) < delay {
            return .wait(.recentlyQuit(delayMinutes))
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
    ///
    /// A zombie child does not count: it has exited and only waits for its
    /// parent to collect it, and the kernel still lists it. Cua Driver 0.39.0's
    /// `serve` kept one for days (macOS 27, 2026-11-08), which held its update
    /// back for good. A child whose state cannot be read still counts.
    public static func hasForeignChild(
        of bundle: URL, processes: [NestedAppGuard.RunningProcess],
        children: (pid_t) -> [pid_t] = childPIDs,
        isZombie: (pid_t) -> Bool = isZombie
    ) -> Bool {
        let own = Set(processes.filter {
            AutomaticInstall.hasRunningProcess(at: bundle, processes: [$0])
        }.map(\.pid))
        return own.contains { parent in
            children(parent).contains { !own.contains($0) && !isZombie($0) }
        }
    }

    /// True only when a complete state read says `SZOMB`. The `1` asks for
    /// zombie records too (XNU `proc_info.c`), as `NestedAppGuard` does.
    public static func isZombie(_ pid: pid_t) -> Bool {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 1, &info, size) == size else { return false }
        return info.pbsi_status == UInt32(SZOMB)
    }

    public static func childPIDs(_ parent: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 512)
        let count = Int(proc_listchildpids(parent, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size)))
        return count > 0 ? Array(buffer.prefix(min(count, buffer.count))) : []
    }
}
