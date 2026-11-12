import Foundation

/// Local-only short process names are retained for unresolved blockers; a running
/// target also keeps where it sits inside the app bundle, its parent's short name
/// and its start time. No argv, environment or absolute paths. None of these
/// reach the sanitized report.
public struct AutomaticProcessDiagnostic: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case enumerationFailed, enumerationTruncated, exited, permissionDenied
        case executablePathUnavailable, unresolvedIdentity, zombie, targetRunning
    }
    public struct Probe: Codable, Hashable, Sendable {
        public enum Name: String, Codable, Sendable {
            case listSize, listPIDs, pidPath, bsdInfo, lifecycleInfo, procargsSize, procargs, existence, privilegedPath
        }
        public let name: Name
        public let result: Int
        public let error: Int32
        public init(_ name: Name, _ result: Int, _ error: Int32) {
            self.name = name; self.result = result; self.error = error
        }
    }
    public let kind: Kind
    public let pid: Int32?
    public let parentPID: Int32?
    public let processName: String?
    /// Raw pbi_status; nil means the BSD-info probe did not answer.
    public let lifecycleState: UInt32?
    public let probes: [Probe]
    /// The executable relative to the app bundle, e.g.
    /// `Contents/XPCServices/Foo.xpc/Contents/MacOS/Foo`.
    public let bundlePath: String?
    /// The parent's short name, when the same snapshot saw it.
    public let parentName: String?
    public let startedAt: Date?

    static func unresolvedKind(alive: Bool, lifecycleState: UInt32?, probes: [Probe]) -> Kind {
        if lifecycleState == UInt32(SZOMB) { return .zombie }
        if !alive, probes.last(where: { $0.name == .existence })?.error == ESRCH { return .exited }
        if probes.contains(where: { $0.error == EPERM || $0.error == EACCES }) { return .permissionDenied }
        return .unresolvedIdentity
    }

    public init(kind: Kind, pid: Int32? = nil, parentPID: Int32? = nil,
                lifecycleState: UInt32? = nil, processName: String? = nil, probes: [Probe] = [],
                bundlePath: String? = nil, parentName: String? = nil, startedAt: Date? = nil) {
        self.kind = kind; self.pid = pid; self.parentPID = parentPID
        self.lifecycleState = lifecycleState; self.processName = processName; self.probes = probes
        self.bundlePath = bundlePath; self.parentName = parentName; self.startedAt = startedAt
    }

    /// A process of `bundle` that keeps it from being replaced, described from
    /// the snapshot it was found in: which executable, who launched it, since when.
    public static func targetRunning(_ process: NestedAppGuard.RunningProcess, in bundle: URL,
        among processes: [NestedAppGuard.RunningProcess]) -> AutomaticProcessDiagnostic {
        let root = bundle.resolvingSymlinksInPath().path + "/"
        let path = NestedAppGuard.resolvedPath(process.executablePath ?? process.launchedPath ?? "")
        let parent = processes.first { $0.pid == process.parentPID && $0.pid != 0 }
        let parentName = parent.flatMap { $0.executablePath ?? $0.launchedPath }
            .map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        return .init(kind: .targetRunning, pid: process.pid, parentPID: process.parentPID,
            processName: path.isEmpty ? nil : (path as NSString).lastPathComponent,
            bundlePath: path.hasPrefix(root) ? String(path.dropFirst(root.count)) : nil,
            parentName: parentName, startedAt: process.startedAt)
    }
}

/// One scheduler pass. Synchronous because the final exchange guard runs on Dispatch.
/// Detailed blockers are stored once per pass, with attempt references on outcome rows.
public final class AutomaticUpdateDiagnostics: @unchecked Sendable {
    public let passID = UUID().uuidString
    private let lock = NSLock()
    private var entries: [AutomaticProcessDiagnostic: Entry] = [:]
    public struct Entry: Codable, Sendable {
        public let id: String
        public let diagnostic: AutomaticProcessDiagnostic
        public var occurrences: Int
        public var attempts: Set<String>
        public var first: Date
        public var last: Date
    }
    public init() {}
    public func record(_ diagnostic: AutomaticProcessDiagnostic, attemptID: String, now: Date = Date()) {
        lock.withLock {
            if var entry = entries[diagnostic] {
                entry.occurrences += 1
                entry.attempts.insert(attemptID)
                entry.last = now
                entries[diagnostic] = entry
            } else {
                entries[diagnostic] = Entry(id: UUID().uuidString, diagnostic: diagnostic,
                    occurrences: 1, attempts: [attemptID], first: now, last: now)
            }
        }
    }
    public var snapshot: [Entry] {
        lock.withLock { entries.values.sorted { $0.id < $1.id } }
    }
    /// Forget what `attemptID` recorded, for an attempt whose row is not written
    /// (a deferral that repeats the last one): nothing would refer to it.
    public func discard(attemptID: String) {
        lock.withLock {
            for (key, var entry) in entries where entry.attempts.contains(attemptID) {
                entry.attempts.remove(attemptID)
                entries[key] = entry.attempts.isEmpty ? nil : entry
            }
        }
    }
    public var isEmpty: Bool { lock.withLock { entries.isEmpty } }
    public func references(for attemptID: String) -> String {
        snapshot.filter { $0.attempts.contains(attemptID) }.map(\.id).joined(separator: ",")
    }
    public var json: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? String(decoding: encoder.encode(snapshot), as: UTF8.self)) ?? "[]"
    }

    public static func fields(_ event: DuoEvent) -> [String: String]? {
        guard event.kind == "automaticUpdate", case .unknown(_, let json) = event.payload,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    /// What a pass needs from the retained history, read once per pass instead of
    /// once per app: every row decoded a single time.
    public struct History: Sendable {
        /// The latest attempt row per app and offered version.
        private var latest: [String: [String: String]] = [:]
        /// The latest attempt row per app, whatever the version.
        private var latestByApp: [String: [String: String]] = [:]
        /// Versions whose attempts since the last install include a failure, or
        /// a start that never reached an outcome (DuoUpdater quit mid-install).
        private var troubled: Set<String> = []

        private static func key(_ appID: String, _ version: String) -> String { appID + "\u{0}" + version }

        public init(_ events: [DuoEvent]) {
            var open: [String: Set<String>] = [:]
            // An attempt's outcome row carries the installed build ("2.8.0 (63)"),
            // its start only the offered version ("2.8.0"), which is also what a
            // pass looks up. Every row of an attempt goes under its start's key.
            var startKeys: [String: String] = [:]
            for event in events.sorted(by: { $0.date < $1.date }) {
                guard let row = AutomaticUpdateDiagnostics.fields(event),
                      let appID = row["appID"], let attemptID = row["attemptID"] else { continue }
                let key = startKeys[appID + "\u{0}" + attemptID] ?? Self.key(appID, row["toVersion"] ?? "")
                if row["status"] == "started" { startKeys[appID + "\u{0}" + attemptID] = key }
                latest[key] = row
                latestByApp[appID] = row
                switch row["status"] {
                case "started": open[key, default: []].insert(attemptID)
                case "installed":
                    open[key] = nil
                    troubled.remove(key)
                case "notInstalled":
                    open[key]?.remove(attemptID)
                    troubled.insert(key)
                default: open[key]?.remove(attemptID)
                }
            }
            for (key, attempts) in open where !attempts.isEmpty { troubled.insert(key) }
        }

        /// The attempt a new one continues: the latest for this copy and version,
        /// unless that one installed it.
        public func predecessor(appID: String, version: String) -> [String: String]? {
            guard let row = latest[Self.key(appID, version)], row["status"] != "installed" else { return nil }
            return row
        }

        /// Whether an install now recovers from an earlier failed or cut-off
        /// attempt at this version, rather than following a wait.
        public func recovers(appID: String, version: String) -> Bool {
            troubled.contains(Self.key(appID, version))
        }

        /// Whether this deferral says what the app's last row already says: the
        /// same version and the same reason. It is then not written again.
        public func repeatsLastDeferral(appID: String, version: String, reason: String) -> Bool {
            guard let last = latestByApp[appID] else { return false }
            return last["status"] == "deferred" && last["toVersion"] == version && last["reason"] == reason
        }
    }

    /// Resume only the latest retained attempt for this installed copy and target version.
    public static func predecessor(in events: [DuoEvent], appID: String, version: String) -> [String: String]? {
        History(events).predecessor(appID: appID, version: version)
    }

    /// Allowlist export: aggregate outcomes and typed probe diagnostics only. No
    /// inventory, activity timeline, persisted identifiers, PIDs or arbitrary text.
    public static func sanitizedReport(_ events: [DuoEvent]) -> String {
        var outcomes: [String: Int] = [:]
        struct Blocker: Codable, Hashable {
            let kind: AutomaticProcessDiagnostic.Kind
            let lifecycleState: UInt32?
            let probes: [AutomaticProcessDiagnostic.Probe]
        }
        var blockers: [Blocker: Int] = [:]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for event in events {
            guard let row = fields(event) else { continue }
            if let status = row["status"], ["started", "installed", "deferred", "notInstalled"].contains(status) {
                outcomes[status, default: 0] += 1
                if row["recoveredFrom"]?.isEmpty == false { outcomes["recovered", default: 0] += 1 }
            }
            if let raw = row["diagnostics"], let data = raw.data(using: .utf8),
               let entries = try? decoder.decode([Entry].self, from: data) {
                for entry in entries {
                    let d = entry.diagnostic
                    blockers[Blocker(kind: d.kind, lifecycleState: d.lifecycleState, probes: d.probes), default: 0] += entry.occurrences
                }
            }
        }
        struct Report: Encodable {
            struct Item: Encodable { let diagnostic: Blocker; let occurrences: Int }
            let format = "automatic-update-diagnostics-v1"
            let outcomes: [String: Int]
            let diagnostics: [Item]
        }
        let report = Report(outcomes: outcomes, diagnostics: blockers.map { .init(diagnostic: $0.key, occurrences: $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(decoding: encoder.encode(report), as: UTF8.self)) ?? "{}"
    }
}
