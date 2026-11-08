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
            case listSize, listPIDs, pidPath, bsdInfo, lifecycleInfo, procargsSize, procargs, existence
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

    /// Resume only the latest retained attempt for this installed copy and target version.
    public static func predecessor(in events: [DuoEvent], appID: String, version: String) -> [String: String]? {
        for event in events.sorted(by: { $0.date > $1.date }) {
            guard let row = fields(event), row["appID"] == appID,
                  row["toVersion"] == version, row["attemptID"] != nil else { continue }
            return row["status"] == "installed" ? nil : row
        }
        return nil
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
