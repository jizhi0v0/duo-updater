import Darwin
import Foundation

/// Permission to keep a named, allowed running app current. Normal use does
/// not postpone an update: foreground state, media, user activity and time
/// since discovery or a successful quit are not policy inputs. Installation
/// safety, independent helpers, refused normal quits and failure back-off remain.
public enum RunningAppAutoUpdate {
    public static var retryBackoff: TimeInterval { devThreshold ?? 24 * 60 * 60 }
    public static let maxFailures = 3

    /// Local builds only (`DUO_DEV_HOOKS`; `check-no-dev-hooks.sh` keeps it out
    /// of a release): `defaults write com.duoupdater.app
    /// DUO_RUNNING_APP_TEST_THRESHOLD -float 60` shortens only failure back-off
    /// for verification. Successful updates have no waiting period.
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
        /// First observation, retained for persisted history and compatibility
        /// with older ledgers. It no longer delays an update.
        public var behindSince: Date
        public var failures: Int
        /// Set by a refused quit or the last allowed failure. Cleared by a new version.
        public var gaveUp: Bool
        /// Last quit, retained as history across versions; it does not space
        /// successful updates apart.
        public var lastQuit: Date?
        /// Refused-quit and legacy cooldowns survive versions. A new policy's
        /// acquisition cooldown belongs only to its offered version.
        public var retryAfter: Date?
        /// New automatic attempts distinguish recoverable acquisition errors
        /// from failures that pause this offer. Nil on legacy ledgers.
        public var automaticFailure: AutomaticUpdateFailurePolicy.Failure?
        /// Acquisition-only failures have their own bounded recovery budget;
        /// they never spend the installation/quit failure count above.
        public var acquisitionFailures: Int?

        /// `behindSince` keeps its stored name from when it meant "this version
        /// first seen", so ledgers written by earlier builds still decode.
        enum CodingKeys: String, CodingKey {
            case version, behindSince = "firstSeen", failures, gaveUp, lastQuit, retryAfter
            case automaticFailure, acquisitionFailures
        }

        public init(version: String, behindSince: Date, failures: Int = 0,
                    gaveUp: Bool = false, lastQuit: Date? = nil, retryAfter: Date? = nil,
                    automaticFailure: AutomaticUpdateFailurePolicy.Failure? = nil,
                    acquisitionFailures: Int? = nil) {
            self.version = version
            self.behindSince = behindSince
            self.failures = failures
            self.gaveUp = gaveUp
            self.lastQuit = lastQuit
            self.retryAfter = retryAfter
            self.automaticFailure = automaticFailure
            self.acquisitionFailures = acquisitionFailures
        }
    }

    /// Per-install entries, keyed by the install's preference key.
    public struct Ledger: Codable, Equatable, Sendable {
        public var entries: [String: Entry]
        public init(entries: [String: Entry] = [:]) { self.entries = entries }

        /// The entry for `key` offered `version`. A different offer clears the
        /// failures and the give-up, which were about the old one. Acquisition
        /// recovery is also offer-specific. Legacy and refused-quit cooldowns
        /// remain about the install and survive a changed version.
        public mutating func observe(_ key: String, version: String, now: Date) -> Entry {
            guard var entry = entries[key] else {
                let entry = Entry(version: version, behindSince: now)
                entries[key] = entry
                return entry
            }
            if entry.version != version {
                if entry.automaticFailure != nil { entry.retryAfter = nil }
                entry.version = version
                entry.failures = 0
                entry.gaveUp = false
                entry.automaticFailure = nil
                entry.acquisitionFailures = nil
                entries[key] = entry
            }
            return entry
        }

        public mutating func recordQuit(_ key: String, now: Date) {
            entries[key]?.lastQuit = now
        }

        public mutating func recordQuitRefused(_ key: String, now: Date) {
            entries[key]?.gaveUp = true
            // A refusal now owns this install's cooldown. Do not let the next
            // version clear it as though it were only acquisition recovery.
            entries[key]?.automaticFailure = nil
            entries[key]?.retryAfter = now.addingTimeInterval(RunningAppAutoUpdate.retryBackoff)
        }

        /// Compatibility for unclassified legacy failures and existing safety
        /// deferrals after a quit. New automatic install errors pass a policy.
        public mutating func recordFailure(_ key: String, now: Date) {
            guard var entry = entries[key] else { return }
            entry.failures += 1
            if entry.failures >= RunningAppAutoUpdate.maxFailures { entry.gaveUp = true }
            entry.automaticFailure = nil
            entry.retryAfter = now.addingTimeInterval(RunningAppAutoUpdate.retryBackoff)
            entries[key] = entry
        }

        public mutating func recordFailure(
            _ key: String, failure: AutomaticUpdateFailurePolicy.Failure, now: Date
        ) {
            guard var entry = entries[key] else { return }
            switch failure.disposition {
            case .retryAcquisition:
                let count = (entry.acquisitionFailures ?? 0) + 1
                entry.acquisitionFailures = count
                if count >= AutomaticUpdateFailurePolicy.maxAcquisitionFailures {
                    entry.automaticFailure = failure.pausingVersion
                    entry.retryAfter = nil
                } else {
                    entry.automaticFailure = failure
                    let localDeadline = now.addingTimeInterval(RunningAppAutoUpdate.retryBackoff)
                    entry.retryAfter = max(localDeadline, failure.retryNotBefore ?? localDeadline)
                }
            case .pauseVersion:
                entry.automaticFailure = failure
                entry.retryAfter = nil
            }
            entries[key] = entry
        }

        /// Keep only `keys`; the caller passes every install still present except
        /// those that caught up (a clean "up to date" check), so the next update
        /// starts with fresh failure history. A failed check is not "caught up".
        public mutating func retain(keys: Set<String>) {
            entries = entries.filter { keys.contains($0.key) }
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
        /// A process inside the bundle that the app's quit would not end.
        case independentHelper
        /// Preserve the actual installer error instead of claiming that a
        /// single refusal failed the legacy three-attempt installation limit.
        case pausedFailure(String)

        /// The reason as the Events list shows it.
        public var message: String {
            switch self {
            case .gaveUp:
                return "The app did not quit, or updating it failed \(RunningAppAutoUpdate.maxFailures) times. Waiting for a newer version."
            case .retryLater:
                return "The app did not quit, or updating it failed, in the last day. Trying again after that."
            case .independentHelper:
                return "The app is running, and one of its helpers keeps running when it quits."
            case .pausedFailure(let reason):
                return reason
            }
        }
    }

    /// Only refusal/failure history postpones an otherwise allowed update.
    public static func decide(entry: Entry, now: Date) -> Verdict {
        if let failure = entry.automaticFailure, failure.disposition == .pauseVersion {
            return .wait(.pausedFailure(failure.reason))
        }
        if entry.gaveUp { return .wait(.gaveUp) }
        if let retryAfter = entry.retryAfter, now < retryAfter { return .wait(.retryLater) }
        return .quitAndUpdate
    }

    /// A process inside `bundle` that quitting the app's instances would leave
    /// running: an independent root service, a login item
    /// (`Contents/Library/LoginItems`) or an app extension (`.appex`,
    /// `Contents/PlugIns`) that none of `instancePIDs` started. The
    /// install refuses a bundle it still runs from, so quitting the app would
    /// gain nothing. Other user-owned helpers with launchd as their
    /// parent — XPC services, Chromium's crash handler — end with their client,
    /// and treating them as independent would keep every such app from
    /// updating. One missed here costs one useless quit (counted toward
    /// `maxFailures`).
    public static func independentHelper(
        of bundle: URL, processes: [NestedAppGuard.RunningProcess], instancePIDs: Set<pid_t>
    ) -> NestedAppGuard.RunningProcess? {
        let parents = Dictionary(processes.map { ($0.pid, $0.parentPID) }, uniquingKeysWith: { first, _ in first })
        func descendsFromInstance(_ pid: pid_t) -> Bool {
            var current = pid
            for _ in 0..<64 {
                if instancePIDs.contains(current) { return true }
                guard let parent = parents[current], parent > 1, parent != current else { return false }
                current = parent
            }
            return false
        }
        let root = bundle.resolvingSymlinksInPath().path + "/"
        return processes.first { process in
            guard AutomaticInstall.hasRunningProcess(at: bundle, processes: [process]),
                  !descendsFromInstance(process.pid) else { return false }
            if process.userID == 0 { return true }
            return [process.executablePath, process.launchedPath].compactMap { $0 }.contains { path in
                let resolved = NestedAppGuard.resolvedPath(path)
                guard resolved.hasPrefix(root) else { return false }
                let inside = resolved.dropFirst(root.count)
                return inside.hasPrefix("Contents/Library/LoginItems/")
                    || inside.hasPrefix("Contents/PlugIns/") || inside.contains(".appex/")
            }
        }
    }

}
