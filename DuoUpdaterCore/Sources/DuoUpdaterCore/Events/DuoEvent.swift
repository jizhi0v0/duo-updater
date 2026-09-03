import Foundation

/// One thing DuoUpdater did, recorded in full, as it happened.
///
/// The store behind this is deliberately an **event log** and not a statistics
/// file. Aggregates answer only the questions you thought to ask when you wrote
/// them: a ``RequestTotal`` can say "2.1 MB went to formulae.brew.sh" and can
/// never say "and every one of those fetches re-resolved DNS", because the
/// summing threw that away at write time. Keeping the events means a later
/// question — a timeline, a per-host latency plot, "what happened right before
/// that failed install" — is a matter of reading the log rather than of shipping
/// a new counter and waiting a month for it to fill.
///
/// So the rule for this type is: **record everything the platform hands us, and
/// derive nothing at write time.** The only things deliberately dropped are
/// secrets (see ``RequestEvent/path``).
///
/// ## Envelope
///
/// Every event is five header fields plus one payload keyed by ``kind``. The
/// split matters for forward compatibility: a reader understands the header of
/// every row and only needs to understand the payloads it knows about. That is
/// not hypothetical — `duo` is installed separately from the app and is
/// routinely the older of the two, so it *will* meet events it has never heard
/// of. The header lives in real columns (``EventStore``), the payload in a JSON
/// column, which is what makes "add a field" free in both directions.
///
/// **Every payload field added after v1 must be `Optional`.** A non-optional
/// field missing from an older writer's row fails the payload decode, and the
/// whole event then degrades to ``Payload/unknown(kind:json:)`` — data that is
/// present and readable, silently reported as unintelligible.
public struct DuoEvent: Sendable, Hashable, Identifiable {

    /// Schema version of the envelope. Bumped only for a change a reader cannot
    /// absorb by ignoring an unknown field; adding a payload field is not one.
    public static let schemaVersion = 1

    public let id: UUID
    public let date: Date
    public let client: RequestClient
    public let payload: Payload

    /// The payloads this build understands, plus the door left open for the ones
    /// it does not.
    public enum Payload: Sendable, Hashable {
        case request(RequestEvent)
        /// A line whose `kind` this build has never heard of, kept as written.
        ///
        /// Not an error and not dropped: a newer app writes into the same log a
        /// possibly older `duo` reads, and a reader that threw on the first
        /// unfamiliar line would take the whole log down with it. The raw JSON is
        /// carried so a dump can still show it.
        case unknown(kind: String, json: String)

        public var kind: String {
            switch self {
            case .request: return "request"
            case .unknown(let kind, _): return kind
            }
        }
    }

    public var kind: String { payload.kind }

    public init(
        id: UUID = UUID(), date: Date = Date(),
        client: RequestClient = .current, payload: Payload
    ) {
        self.id = id
        self.date = date
        self.client = client
        self.payload = payload
    }

    /// Convenience for the only payload that exists today.
    public var request: RequestEvent? {
        if case .request(let event) = payload { return event }
        return nil
    }
}

// MARK: - Storage format

extension DuoEvent {

    /// Payload timestamps are **integer microseconds since the epoch**.
    ///
    /// Two encodings were tried and rejected, both for reasons that only show up
    /// in the intervals these timestamps exist to measure:
    ///
    /// - `.iso8601` truncates to whole seconds. A request event carries eleven
    ///   timestamps and the point of every one of them is the gap to the next;
    ///   on a reused connection those phases are sub-millisecond, so a
    ///   whole-second encoding does not round them, it collapses all of them to
    ///   zero — while leaving the fields looking present and readable.
    ///   `.withFractionalSeconds` gives milliseconds back and loses the rest.
    /// - `.secondsSince1970` writes a JSON float, and a `Double` near 1.8e9 does
    ///   not survive the text round trip in its last bits. Measured: a stored
    ///   event no longer compared equal to the one written.
    ///
    /// Microseconds as an integer are exact (1.8e15 is far inside both `Int64`
    /// and `Double`'s exact-integer range) and finer than anything `URLSession`
    /// reports. The consequence, which callers should know: **a `Date` read back
    /// is its microsecond truncation**, so a value built from a finer source is
    /// equal to itself only after a round trip.
    ///
    /// The human-readable timestamp is the envelope's `at`, which stays ISO-8601.
    static let microsecond = 1_000_000.0

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * microsecond).rounded()))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let micros = try decoder.singleValueContainer().decode(Int64.self)
            return Date(timeIntervalSince1970: Double(micros) / microsecond)
        }
        return decoder
    }

    /// A date as it will exist after a round trip through the store. For anyone
    /// comparing a value they just built against one they read back.
    public static func storageResolution(_ date: Date) -> Date {
        Date(timeIntervalSince1970:
                Double(Int64((date.timeIntervalSince1970 * microsecond).rounded())) / microsecond)
    }

    /// The payload, as the JSON that gets stored.
    ///
    /// An `.unknown` returns the JSON it was read as, byte for byte. Re-encoding
    /// it through a shape this build understands would silently drop whatever a
    /// newer writer added — which is the one thing the passthrough exists to
    /// prevent.
    public func payloadJSON() throws -> String {
        switch payload {
        case .request(let event):
            return String(decoding: try Self.encoder().encode(event), as: UTF8.self)
        case .unknown(_, let json):
            return json
        }
    }

    /// Rebuild an event from a stored row.
    ///
    /// A `kind` this build does not know, **and a known kind whose payload does
    /// not parse**, both become ``Payload/unknown(kind:json:)`` rather than
    /// nothing. The second case is the one that matters in practice: it is what a
    /// row written by a newer app looks like to an older `duo`, and dropping it
    /// would turn "I cannot read this" into "this never happened".
    public init?(row: EventRow) {
        let payload: Payload
        switch row.kind {
        case "request":
            if let data = row.payloadJSON.data(using: .utf8),
               let event = try? Self.decoder().decode(RequestEvent.self, from: data) {
                payload = .request(event)
            } else {
                payload = .unknown(kind: row.kind, json: row.payloadJSON)
            }
        default:
            payload = .unknown(kind: row.kind, json: row.payloadJSON)
        }
        self.init(id: row.id, date: row.date, client: row.client, payload: payload)
    }
}

public extension ISO8601DateFormatter {
    /// The one format events are timestamped in, with fractional seconds so two
    /// requests in the same second still order.
    // `ISO8601DateFormatter` is not marked `Sendable`, but formatting is
    // documented as thread-safe and this instance is never reconfigured after
    // construction. Reached once per row of a dump, so a per-call formatter would
    // be pure waste.
    public nonisolated(unsafe) static let duoEvent: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
