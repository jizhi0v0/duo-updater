import Foundation

/// The automatic-update log, shaped for reading.
///
/// The store keeps a row per state change: one install writes "started" and
/// then its outcome, every scheduler pass ends with a diagnostics row, and an
/// app that stays open is deferred again on every pass. Listed raw, that reads
/// as duplicates and noise. Here each attempt becomes one row carrying its own
/// diagnostics, and an unbroken run of identical outcomes for the same update
/// becomes one row with a count.
public struct AutomaticUpdateActivity: Identifiable, Sendable {
    /// The first attempt's ID, so a row keeps its identity while it grows.
    public let id: String
    public var first: Date
    public var last: Date
    /// The latest attempt's fields.
    public var fields: [String: String]
    /// How many attempts this row stands for.
    public var count: Int
    /// The latest attempt's blockers.
    public var diagnostics: [AutomaticUpdateDiagnostics.Entry]
    /// A pass's diagnostics text that could not be decoded, shown as stored.
    public var undecodedDiagnostics: String?

    public var status: String { fields["status"] ?? "" }

    /// Groups `events` (any order) into rows, newest first.
    public static func rows(from events: [DuoEvent]) -> [AutomaticUpdateActivity] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var blockers: [String: [AutomaticUpdateDiagnostics.Entry]] = [:]
        var undecoded: [String: String] = [:]
        var attempts: [AutomaticUpdateActivity] = []
        var index: [String: Int] = [:]
        var passOf: [String: String] = [:]

        for event in events.sorted(by: { $0.date < $1.date }) {
            guard let row = AutomaticUpdateDiagnostics.fields(event) else { continue }
            let passID = row["passID"] ?? ""
            if row["status"] == "diagnostics" {
                let raw = row["diagnostics"] ?? "[]"
                if let entries = raw.data(using: .utf8)
                    .flatMap({ try? decoder.decode([AutomaticUpdateDiagnostics.Entry].self, from: $0) }) {
                    for entry in entries {
                        for attempt in entry.attempts { blockers[attempt, default: []].append(entry) }
                    }
                } else if !passID.isEmpty {
                    undecoded[passID] = raw
                }
                continue
            }
            // Rows from before attempt IDs existed stand alone.
            let attemptID = row["attemptID"].flatMap { $0.isEmpty ? nil : $0 } ?? event.id.uuidString
            if let i = index[attemptID] {
                attempts[i].last = event.date
                attempts[i].fields = row
            } else {
                index[attemptID] = attempts.count
                attempts.append(.init(id: attemptID, first: event.date, last: event.date, fields: row,
                    count: 1, diagnostics: [], undecodedDiagnostics: nil))
            }
            if !passID.isEmpty { passOf[attemptID] = passID }
        }

        var rows: [AutomaticUpdateActivity] = []
        var latestRow: [String: Int] = [:]
        for var attempt in attempts {
            attempt.diagnostics = (blockers[attempt.id] ?? []).sorted { $0.first < $1.first }
            attempt.undecodedDiagnostics = passOf[attempt.id].flatMap { undecoded[$0] }
            // Retries share a chain; older rows without one fall back to the app.
            let key = attempt.fields["chainID"].flatMap { $0.isEmpty ? nil : $0 }
                ?? attempt.fields["appID"] ?? attempt.id
            if let r = latestRow[key], rows[r].repeats(attempt) {
                rows[r].count += 1
                rows[r].last = attempt.last
                rows[r].fields = attempt.fields
                rows[r].diagnostics = attempt.diagnostics
                rows[r].undecodedDiagnostics = attempt.undecodedDiagnostics
            } else {
                latestRow[key] = rows.count
                rows.append(attempt)
            }
        }
        return rows.sorted { $0.last > $1.last }
    }

    /// Only outcomes that end an attempt without changing anything collapse:
    /// an install or a start is news every time it happens.
    private func repeats(_ next: AutomaticUpdateActivity) -> Bool {
        guard status == "deferred" || status == "notInstalled" else { return false }
        return ["status", "reason", "fromVersion", "toVersion"].allSatisfy { fields[$0] == next.fields[$0] }
    }
}
