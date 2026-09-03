import Foundation
import DuoUpdaterCore

/// `duo events` — the raw event stream, as NDJSON, for piping somewhere that
/// draws.
///
/// The counterpart to `duo requests`, which curates. This one emits rows
/// **exactly as stored**: the envelope this build wrote, and the payload JSON
/// byte-for-byte as it went in. That matters because `duo` is installed
/// separately from the menu-bar app and is routinely the older of the two —
/// re-encoding a payload through this build's `RequestEvent` would silently drop
/// whatever a newer writer added, which is the one thing a raw dump exists not
/// to do.
public enum Events {

    public struct Options: Sendable {
        public var query = EventQuery()
        /// Print what the store holds and where, instead of the events.
        public var showStatus = false

        public init() {}
    }

    public static func run(_ options: Options) async -> Int32 {
        let store = EventStore.shared

        if options.showStatus {
            let coverage = await store.coverage(kind: "request")
            let problems = await store.schemaProblems()
            print("store:    \(EventStore.defaultFileURL().path)")
            print("size:     \(ByteFormat.string(await store.databaseBytes()))")
            let installs = await store.coverage(kind: "install")
            print("requests: \(coverage.count)   (pruned by the policy below)")
            print("installs: \(installs.count)   (the download ledger; never pruned)")
            if let oldest = coverage.oldest, let newest = coverage.newest {
                print("covering: \(Self.stamp.string(from: oldest)) → \(Self.stamp.string(from: newest))")
            }
            print("keeping:  \(await store.retentionDays) days or "
                  + "\(ByteFormat.string(await store.retentionBytes)), whichever binds first")
            for problem in problems { print("problem:  \(problem)") }
            return 0
        }

        // The home directory is abbreviated on the way out. An install event's
        // `appID` is a bundle path, and on a real machine a third of them sit
        // under `/Users/<name>/Applications`, so a dump framed as something to
        // pipe elsewhere would carry the account name in every one of them —
        // while the same command advertises that query strings are never
        // recorded. The payload is otherwise emitted exactly as stored.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for row in await store.rawRows(options.query) {
            print(row.json.replacingOccurrences(of: home, with: "~"))
        }
        return 0
    }

    /// `--since` accepts an ISO-8601 instant or a relative `30m` / `6h` / `7d`.
    ///
    /// Relative first because that is what anyone actually types, and absolute
    /// because a bug report wants a fixed window. Returns nil for anything else
    /// so the caller can refuse rather than silently dump everything — a `--since`
    /// that quietly means "no filter" when it is mistyped is how a one-screen
    /// command turns into a million lines.
    public static func parseSince(_ text: String, now: Date = Date()) -> Date? {
        if let iso = ISO8601DateFormatter.duoEvent.date(from: text) { return iso }
        let plain = ISO8601DateFormatter()
        if let iso = plain.date(from: text) { return iso }
        guard let unit = text.last, let amount = Double(text.dropLast()), amount >= 0 else {
            return nil
        }
        switch unit {
        case "m": return now.addingTimeInterval(-amount * 60)
        case "h": return now.addingTimeInterval(-amount * 3600)
        case "d": return now.addingTimeInterval(-amount * 86_400)
        default:  return nil
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
