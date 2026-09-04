import Foundation
import DuoUpdaterCore

/// `duo requests` — what DuoUpdater itself put on the network.
///
/// The counterpart to the download ledger the app already shows. That one
/// answers "how much bandwidth did keeping this machine up to date cost", and
/// counts only installer bytes; this one answers "what does the updater talk to,
/// how often, and what for" — which is the question an always-running background
/// updater owes its user an answer to, because it is a plausible candidate for
/// the heaviest network consumer on the machine and nothing was counting.
public enum Requests {

    public struct Options {
        public enum Operation {
            case summary
            /// Raw tail. `limit` records, newest last.
            case recent(limit: Int)
            case reset
        }
        public var operation: Operation
        public var json = false
        /// Show `duo`'s own requests alongside the app's. Off by default: a
        /// `duo verify` sweep is ~150 requests of diagnostics, and mixing them
        /// into the app's totals is how a report starts lying about what the
        /// background updater costs.
        public var allClients = false
        public var assumeYes = false

        public init(operation: Operation) { self.operation = operation }
    }

    public static func run(_ options: Options) async -> Int32 {
        let store = EventStore.shared

        if case .reset = options.operation {
            guard options.assumeYes
                    || confirm("Discard every recorded event and every running total?")
            else { return 1 }
            await store.reset()
            if !options.json { print("request history cleared") }
            return 0
        }

        let client: RequestClient? = options.allClients ? nil : .app

        switch options.operation {
        case .summary:
            let snapshot = await store.totals()
            let coverage = await store.coverage(kind: "request")
            options.json
                ? printJSON(summaryPayload(snapshot, client: client))
                : printSummary(snapshot, client: client, allClients: options.allClients,
                               coverage: coverage)
        case .recent(let limit):
            let query = EventQuery(kind: "request", client: client, limit: limit)
            if options.json {
                // The stored rows, not a re-encode. Sending `RequestEvent` back
                // through `printJSON` rendered all eleven phase timestamps as
                // whole-second ISO-8601 — measured: `fetchStart`,
                // `domainLookupStart` and `connectStart` all printed as the same
                // instant, so every interval a consumer computed was zero. It also
                // made this command and `duo events` disagree about the same
                // event. One shape, straight from the database.
                print("[" + (await store.rawRows(query)).map(\.json).joined(separator: ",\n") + "]")
            } else {
                let rows = await store.events(query)
                printRecent(rows.compactMap { event in event.request.map { (event, $0) } })
            }
        case .reset:
            break   // handled above
        }
        return 0
    }

    // MARK: - Summary

    private static func printSummary(
        _ snapshot: RequestTotalsSnapshot, client: RequestClient?, allClients: Bool,
        coverage: (count: Int, oldest: Date?, newest: Date?)
    ) {
        let rows = snapshot.totals(for: client)
        guard !rows.isEmpty else {
            print("Nothing recorded yet.")
            if !allClients {
                print("(`--all-clients` also counts requests made by `duo` itself.)")
            }
            return
        }

        let received = rows.reduce(0) { $0 + $1.bytesReceived }
        let sent = rows.reduce(0) { $0 + $1.bytesSent }
        let requests = rows.reduce(0) { $0 + $1.requests }
        let cached = rows.reduce(0) { $0 + $1.cachedRequests }
        let notModified = rows.reduce(0) { $0 + $1.notModified }
        let failures = rows.reduce(0) { $0 + $1.failures }
        let since = rows.map(\.firstSeen).min()

        print("\(ByteFormat.string(received)) received, \(ByteFormat.string(sent)) sent")
        var line = "\(requests) requests to \(Set(rows.map(\.host)).count) hosts"
        if let since { line += " since \(Self.stamp.string(from: since))" }
        print(line)
        // Spelled out rather than folded into the request count: these are the
        // three ways a request can be much cheaper, or free, than it looks, and a
        // total that hides them makes revalidation look like re-downloading.
        print("\(notModified) answered 304 · \(cached) served from cache · \(failures) failed")
        if !allClients {
            print("(the menu-bar app only; `--all-clients` adds `duo`'s own requests)")
        }
        // Totals are kept forever; events are pruned. Saying so here is the whole
        // reason the two can be printed on one screen without misleading anyone:
        // after the retention window, the totals above legitimately account for
        // traffic whose events `duo requests recent` can no longer show.
        if let oldest = coverage.oldest, let since, oldest > since {
            print("(totals run from the start; the \(coverage.count) retained events "
                  + "only go back to \(Self.stamp.string(from: oldest)))")
        }

        print("")
        print("BY PURPOSE")
        for row in snapshot.byPurpose(client: client) {
            print(purposeLine(row, total: received))
        }

        print("")
        print("BY HOST")
        for row in snapshot.byHost(client: client).prefix(hostLimit) {
            print(hostLine(row, total: received))
        }
        let hosts = snapshot.byHost(client: client).count
        if hosts > hostLimit { print("  … and \(hosts - hostLimit) more") }
    }

    /// How many hosts the table shows before it truncates.
    private static let hostLimit = 25

    private static func purposeLine(_ row: RequestTotal, total: Int64) -> String {
        "  " + pad(row.purpose.rawValue, 16)
            + pad(ByteFormat.string(row.bytesReceived), 12, right: true)
            + pad(share(row.bytesReceived, of: total), 8, right: true)
            + "  " + "\(row.requests) req"
            + (row.notModified > 0 ? ", \(row.notModified) × 304" : "")
    }

    private static func hostLine(_ row: RequestTotal, total: Int64) -> String {
        "  " + pad(row.host, 40)
            + pad(ByteFormat.string(row.bytesReceived), 12, right: true)
            + pad(share(row.bytesReceived, of: total), 8, right: true)
            + "  " + "\(row.requests) req"
    }

    private static func share(_ part: Int64, of total: Int64) -> String {
        guard total > 0 else { return "—" }
        return String(format: "%.1f%%", Double(part) / Double(total) * 100)
    }

    // MARK: - Recent

    private static func printRecent(_ rows: [(DuoEvent, RequestEvent)]) {
        guard !rows.isEmpty else { print("Nothing recorded yet."); return }
        for (envelope, row) in rows {
            // Status column has to distinguish three things, not two: an HTTP
            // status, a cache hit that never asked, and a transfer that never got
            // an answer at all.
            let status: String
            if row.fromCache { status = "cache" }
            else if let code = row.status { status = String(code) }
            else { status = "fail" }
            let where_ = row.remoteAddress.map { "\($0):\(row.remotePort ?? 0)" } ?? "—"
            print(
                pad(Self.stamp.string(from: envelope.date), 20)
                + pad(row.purpose.rawValue, 16)
                + pad(status, 6)
                + pad(ByteFormat.string(row.bytesReceived), 11, right: true)
                + "  " + pad(where_, 22)
                + row.host + row.path)
        }
    }

    // MARK: - Output helpers

    private static func pad(_ s: String, _ width: Int, right: Bool = false) -> String {
        let padding = String(repeating: " ", count: max(0, width - s.count))
        return right ? padding + s + " " : s + padding
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// A rollup row, with the collapsed dimension left out.
    ///
    /// `RequestTotal` carries both `host` and `purpose` because that is what it is
    /// keyed on, and a rollup has to put *something* in the field it just summed
    /// away. Invisible in the text tables, but emitting `"purpose": "other"` on a
    /// per-host row is a machine-readable statement that happens to be false —
    /// so the JSON gets shapes that only claim what they know.
    private struct Rollup: Encodable {
        let key: String
        let bytesReceived: Int64
        let bytesSent: Int64
        let requests: Int
        let cachedRequests: Int
        let notModified: Int
        let failures: Int
        let firstSeen: Date
        let lastSeen: Date

        init(_ total: RequestTotal, key: String) {
            self.key = key
            bytesReceived = total.bytesReceived
            bytesSent = total.bytesSent
            requests = total.requests
            cachedRequests = total.cachedRequests
            notModified = total.notModified
            failures = total.failures
            firstSeen = total.firstSeen
            lastSeen = total.lastSeen
        }
    }

    private struct SummaryPayload: Encodable {
        let bytesReceived: Int64
        let bytesSent: Int64
        let requests: Int
        let notModified: Int
        let cached: Int
        let failures: Int
        let byPurpose: [Rollup]
        let byHost: [Rollup]
        let totals: [RequestTotal]
    }

    private static func summaryPayload(
        _ snapshot: RequestTotalsSnapshot, client: RequestClient?
    ) -> SummaryPayload {
        let rows = snapshot.totals(for: client)
        return SummaryPayload(
            bytesReceived: rows.reduce(0) { $0 + $1.bytesReceived },
            bytesSent: rows.reduce(0) { $0 + $1.bytesSent },
            requests: rows.reduce(0) { $0 + $1.requests },
            notModified: rows.reduce(0) { $0 + $1.notModified },
            cached: rows.reduce(0) { $0 + $1.cachedRequests },
            failures: rows.reduce(0) { $0 + $1.failures },
            byPurpose: snapshot.byPurpose(client: client).map { Rollup($0, key: $0.purpose.rawValue) },
            byHost: snapshot.byHost(client: client).map { Rollup($0, key: $0.host) },
            totals: rows)
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        print(String(decoding: data, as: UTF8.self))
    }

    private static func confirm(_ question: String) -> Bool {
        guard isatty(FileHandle.standardInput.fileDescriptor) == 1 else {
            FileHandle.standardError.write(Data("\(question) needs --yes when stdin is not a terminal\n".utf8))
            return false
        }
        print("\(question) [y/N] ", terminator: "")
        return (readLine() ?? "").lowercased().hasPrefix("y")
    }
}
