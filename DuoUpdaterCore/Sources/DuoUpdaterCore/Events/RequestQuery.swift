import Foundation

/// What the request log is being asked for, parsed out of one text field.
///
/// The window's search field, its filter chips and `duo events` all compile to
/// this one type, so a question asked in the GUI and the same question asked at
/// the shell cannot answer differently — the chips are literally tokens
/// (`status:fail`), not a second filtering path that happens to look similar.
///
/// **Parsing never fails.** A half-typed token is a normal state of the field, so
/// anything unrecognised degrades to free text rather than throwing: `stat` is a
/// word to look for, and only becomes a filter at `status:`. What it must not do
/// is degrade *silently* — an unknown key would otherwise widen the result set
/// while looking like it narrowed it — so those land in ``ignoredKeys`` for the
/// caller to show.
///
/// ## Grammar
///
/// - `host:github.com`, `app:Zed`, `purpose:check`, `status:403` — substring or
///   exact depending on the key; repeating a key means OR.
/// - `size>10MB`, `size<1KB`, `took>5s` — one bound each, last one wins.
/// - Anything else is free text, matched against host and path. Several words
///   are AND, so they narrow the way a reader expects.
/// - Quoting (`host:"a b"`) keeps spaces; there is no escaping beyond that.
public struct RequestQuery: Sendable, Equatable {

    /// A status term. `fail` and `cache` are not HTTP codes but are what people
    /// actually look for, and `problem` is the one the failure chip binds to.
    public enum StatusTerm: Sendable, Equatable, Hashable {
        /// One exact code.
        case code(Int)
        /// A class of codes: `4xx`.
        case family(Int)
        /// No answer at all — a transport error or a cancellation.
        case failed
        /// Answered locally; nothing crossed the network.
        case cache
        /// Anything a person would call wrong: no answer, or an answer ≥ 400.
        ///
        /// Deliberately wider than ``failed``. A 403 from a rate-limited GitHub
        /// is the single most common reason an app stops updating, and it is not
        /// a transport failure — a panel that called only transport errors
        /// "problems" would report zero on the day everything broke.
        case problem
    }

    public var hosts: [String] = []
    public var apps: [String] = []
    public var purposes: [RequestPurpose] = []
    /// Which writer's rows to count. The window seeds this with `.app` so a
    /// `duo verify` sweep — 150 diagnostic requests in one go — cannot be read as
    /// what the background updater costs.
    public var clients: [RequestClient] = []
    public var statuses: [StatusTerm] = []
    public var text: [String] = []
    public var minBytes: Int64?
    public var maxBytes: Int64?
    public var minDuration: TimeInterval?
    public var since: Date?
    public var until: Date?

    /// Keys that looked like filters and are not. Shown, never swallowed.
    public var ignoredKeys: [String] = []

    /// Which column the log is ordered by.
    ///
    /// Part of the query rather than of the view because the ordering decides
    /// *which* rows the capped page contains, not just how they are arranged:
    /// "the 500 newest" and "the 500 largest" are different sets, and a view that
    /// sorted its own page would silently show the newest 500 re-shuffled while
    /// claiming to show the largest.
    public enum Sort: String, Sendable, CaseIterable {
        case time, size, duration

        var column: String {
            switch self {
            case .time:     return "at"
            case .size:     return "bytes_in"
            case .duration: return RequestQuery.durationMicros
            }
        }
    }

    public var sort: Sort = .time
    public var ascending = false


    /// Collapse the hops of one fetch into a single row.
    ///
    /// `URLSessionTaskMetrics` reports one transaction per hop, and a revalidated
    /// feed is two of them — the cache consultation (0 bytes, never touched the
    /// network) and the network load, sharing a task id. Counting those as two
    /// requests is what makes one update read as five.
    ///
    /// Off everywhere at the moment: the window shows every transaction, and
    /// `duo events` is a raw dump that must stay per-hop regardless. Kept
    /// because the machinery behind it — the task grouping — is what lets the
    /// headline figures count fetches while the list shows transactions, and
    /// what a "collapse" toggle would switch on.
    public var collapseHops = false

    public init() {}

    public var isEmpty: Bool {
        hosts.isEmpty && apps.isEmpty && purposes.isEmpty && statuses.isEmpty
            && text.isEmpty && minBytes == nil && maxBytes == nil
            && minDuration == nil && since == nil && until == nil
    }

    // MARK: - Parsing

    /// What the window asks, as opposed to what the user typed.
    ///
    /// Scoped to this app's own rows unless the text says otherwise: a
    /// `duo verify` sweep is ~150 diagnostic requests in one go, and folding
    /// those into the strip is how it starts misreporting what the background
    /// updater costs. Typing any `client:` token — including `client:all` —
    /// hands the decision back to the reader.
    public static func window(_ input: String) -> RequestQuery {
        var query = parse(input)
        // Asked of the parsed tokens, not of the raw string: a path containing
        // the literal `client:` — which is ordinary free text — would otherwise
        // suppress the default and quietly fold `duo`'s rows into every figure.
        let mentionsClient = tokenize(input).contains {
            $0.lowercased().hasPrefix("client:")
        }
        if !mentionsClient { query.clients = [.app] }
        return query
    }

    public static func parse(_ input: String) -> RequestQuery {
        var query = RequestQuery()
        for token in tokenize(input) {
            query.absorb(token)
        }
        return query
    }

    /// Splits on whitespace, keeping double-quoted runs together. Quotes may open
    /// after the colon (`host:"a b"`) because that is where a value with a space
    /// would be typed.
    public static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false
        for character in input {
            if character == "\"" {
                quoted.toggle()
            } else if character.isWhitespace, !quoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private mutating func absorb(_ token: String) {
        // Comparison keys first: `size>10MB` has no colon, so a colon-split would
        // read the whole thing as free text and quietly stop filtering.
        if let (key, comparison, value) = Self.splitComparison(token) {
            // `size>banana` parses to nothing. Reported rather than dropped: it
            // is pinned as an ordinary capsule, so left unreported it looks
            // exactly like a filter that is working while the list quietly
            // fails to narrow. Asked of *this* token's own field — a first
            // version checked whether all three bounds were nil, so
            // `size>10MB took>abc` reported nothing because the size had
            // already landed.
            switch (key, comparison) {
            case ("size", ">"):
                minBytes = Self.bytes(value)
                if minBytes == nil { ignoredKeys.append(token) }
            case ("size", "<"):
                maxBytes = Self.bytes(value)
                if maxBytes == nil { ignoredKeys.append(token) }
            case ("took", ">"):
                minDuration = Self.seconds(value)
                if minDuration == nil { ignoredKeys.append(token) }
            default:
                ignoredKeys.append(token)
            }
            return
        }
        guard let colon = token.firstIndex(of: ":"), colon != token.startIndex else {
            if !token.isEmpty { text.append(token) }
            return
        }
        let key = String(token[token.startIndex..<colon]).lowercased()
        let value = String(token[token.index(after: colon)...])
        // A bare key is what the field looks like mid-type, right before the
        // completion menu offers its values. Not a filter yet, and not an error.
        guard !value.isEmpty else { return }
        switch key {
        case "host": hosts.append(value)
        case "app": apps.append(value)
        case "purpose":
            if let purpose = Self.purpose(value) { purposes.append(purpose) }
            else { ignoredKeys.append(token) }
        case "client":
            if value.lowercased() == "all" { clients = [] }
            else if let client = RequestClient(rawValue: value.lowercased()) {
                clients.append(client)
            } else { ignoredKeys.append(token) }
        case "status":
            if let status = Self.status(value) { statuses.append(status) }
            else { ignoredKeys.append(token) }
        default:
            // A pasted URL is the common case and a perfectly good thing to
            // search for; anything else shaped like `word:value` is a filter
            // somebody meant to write. Left as free text it matches nothing and
            // silently empties the result — a narrowing that never happened,
            // reported as "no such requests".
            if Self.looksLikeAKey(key), !value.hasPrefix("//") {
                ignoredKeys.append(token)
            } else {
                text.append(token)
            }
        }
    }

    /// Whether a `word:` prefix was meant as a filter key.
    ///
    /// The one thing that must not trip this is a pasted URL: its "key" is the
    /// scheme and its value opens with `//`, which no filter value does.
    static func looksLikeAKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 12
            && key.allSatisfy { $0.isLetter || $0 == "-" || $0 == "_" }
    }

    private static func splitComparison(_ token: String) -> (String, String, String)? {
        for comparison in [">", "<"] where token.contains(comparison) {
            let parts = token.components(separatedBy: comparison)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            let key = parts[0].lowercased()
            guard key == "size" || key == "took" else { return nil }
            return (key, comparison, parts[1])
        }
        return nil
    }

    /// Friendly names first, raw enum values accepted too. The window shows
    /// "Update checks" and `duo events --purpose versionCheck` has always taken
    /// the raw value; both have to keep working.
    static func purpose(_ value: String) -> RequestPurpose? {
        switch value.lowercased() {
        case "download", "downloads", "install", "installs": return .install
        case "check", "checks", "versioncheck": return .versionCheck
        case "notes", "changelog", "releasenotes": return .changelog
        case "image", "images", "changelogimage": return .changelogImage
        case "catalog", "brew", "homebrew": return .catalog
        case "self", "selfupdate", "duo": return .selfUpdate
        case "other": return .other
        default:
            return RequestPurpose.allCases.first { $0.rawValue.lowercased() == value.lowercased() }
        }
    }

    static func status(_ value: String) -> StatusTerm? {
        let lowered = value.lowercased()
        switch lowered {
        case "fail", "failed", "failure", "failures": return .failed
        case "cache", "cached": return .cache
        case "problem", "problems", "error", "errors": return .problem
        default: break
        }
        if lowered.count == 3, lowered.hasSuffix("xx"), let family = Int(lowered.prefix(1)) {
            return .family(family)
        }
        guard let code = Int(lowered), (100..<600).contains(code) else { return nil }
        return .code(code)
    }

    /// `10MB`, `1.5 GB`, `900` (bare digits are bytes). Decimal units, matching
    /// what the window prints: a person filtering `size>1GB` against a row the
    /// window rendered as "1.02 GB" must get that row back.
    static func bytes(_ value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6),
                                         ("KB", 1e3), ("B", 1)]
        for (suffix, scale) in units where trimmed.hasSuffix(suffix) {
            let number = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            guard let magnitude = Double(number) else { return nil }
            return Int64(magnitude * scale)
        }
        guard let magnitude = Double(trimmed) else { return nil }
        return Int64(magnitude)
    }

    /// `5s`, `500ms`, `2.5` (bare numbers are seconds).
    static func seconds(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("ms") {
            return Double(trimmed.dropLast(2)).map { $0 / 1000 }
        }
        if trimmed.hasSuffix("s") {
            return Double(trimmed.dropLast(1))
        }
        return Double(trimmed)
    }

    // MARK: - Highlighting

    /// One coloured span of the query text, in **UTF-16 offsets** — what
    /// `NSTextStorage` indexes by, so the field can apply these directly.
    ///
    /// Here rather than in the field so the thing that decides "this is a key"
    /// is the thing that parses it. Two implementations of that judgement drift,
    /// and the way you find out is a token that paints like a filter and does
    /// not filter.
    public struct Highlight: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// `host:` — the key and its colon.
            case key
            /// What follows the key.
            case value
            /// A bare word, matched against host and path.
            case text
            /// Looks like a filter, is not one. Painted as a warning because the
            /// alternative is a token that silently widens the result set.
            case unknown
        }
        public let location: Int
        public let length: Int
        public let kind: Kind

        public init(location: Int, length: Int, kind: Kind) {
            self.location = location
            self.length = length
            self.kind = kind
        }
    }

    public static func highlights(_ input: String) -> [Highlight] {
        let ignored = Set(parse(input).ignoredKeys)
        var spans: [Highlight] = []
        var quoted = false
        var tokenStart: Int?
        var offset = 0

        func flush(end: Int) {
            guard let start = tokenStart else { return }
            tokenStart = nil
            let utf16 = Array(input.utf16)
            let token = String(decoding: utf16[start..<end], as: UTF16.self)
            spans += classify(token, at: start, ignored: ignored)
        }

        for character in input.unicodeScalars {
            let width = String(character).utf16.count
            if character == "\"" {
                quoted.toggle()
            } else if CharacterSet.whitespaces.contains(character), !quoted {
                flush(end: offset)
            } else if tokenStart == nil {
                tokenStart = offset
            }
            offset += width
        }
        flush(end: offset)
        return spans
    }

    private static func classify(
        _ token: String, at start: Int, ignored: Set<String>
    ) -> [Highlight] {
        let length = token.utf16.count
        // Quotes are stripped by the parser but drawn by the field, so a
        // quoted value's span has to cover them or the pill stops short of its
        // own closing quote.
        let bare = token.replacingOccurrences(of: "\"", with: "")
        if ignored.contains(bare) {
            return [Highlight(location: start, length: length, kind: .unknown)]
        }
        for separator in [":", ">", "<"] {
            guard let index = token.firstIndex(of: Character(separator)),
                  index != token.startIndex else { continue }
            let key = String(token[token.startIndex..<index]).lowercased()
            let known = ["host", "app", "purpose", "status", "client"].contains(key)
                || ((key == "size" || key == "took") && separator != ":")
            guard known else { break }
            let keyLength = String(token[token.startIndex...index]).utf16.count
            var spans = [Highlight(location: start, length: keyLength, kind: .key)]
            if keyLength < length {
                spans.append(Highlight(location: start + keyLength,
                                       length: length - keyLength, kind: .value))
            }
            return spans
        }
        return [Highlight(location: start, length: length, kind: .text)]
    }

    // MARK: - Compilation

    /// A value bound into a prepared statement. Bound rather than interpolated —
    /// host names and search words come from a text field the user controls.
    public enum SQLValue: Sendable, Equatable {
        case text(String)
        case int(Int64)
    }

    /// The `WHERE` body and its bindings, in order.
    ///
    /// Always scoped to `kind = 'request'`: install events live in the same table
    /// and describe a file on disk, not a socket, so folding them into a request
    /// filter would double every download and answer `status:` with nothing.
    public func sqlPredicate() -> (clause: String, values: [SQLValue]) {
        var clauses = ["kind = 'request'"]
        var values: [SQLValue] = []

        func anyOf(_ column: String, _ terms: [String], like: Bool) {
            guard !terms.isEmpty else { return }
            let parts = terms.map { _ in like ? "\(column) LIKE ?" : "\(column) = ?" }
            clauses.append("(" + parts.joined(separator: " OR ") + ")")
            values += terms.map { .text(like ? "%\($0)%" : $0) }
        }

        if !clients.isEmpty {
            clauses.append("(" + clients.map { _ in "client = ?" }.joined(separator: " OR ") + ")")
            values += clients.map { .text($0.rawValue) }
        }
        anyOf("host", hosts, like: true)
        anyOf("app_id", apps, like: true)

        if !purposes.isEmpty {
            clauses.append("(" + purposes.map { _ in "purpose = ?" }.joined(separator: " OR ") + ")")
            values += purposes.map { .text($0.rawValue) }
        }

        if !statuses.isEmpty {
            var parts: [String] = []
            for status in statuses {
                switch status {
                case let .code(code):
                    parts.append("status = ?")
                    values.append(.int(Int64(code)))
                case let .family(family):
                    parts.append("(status >= ? AND status < ?)")
                    values.append(.int(Int64(family) * 100))
                    values.append(.int(Int64(family) * 100 + 100))
                case .failed:
                    parts.append("(status IS NULL AND \(Self.notCached))")
                case .cache:
                    parts.append("NOT (\(Self.notCached))")
                case .problem:
                    parts.append("(status >= 400 OR (status IS NULL AND \(Self.notCached)))")
                }
            }
            clauses.append("(" + parts.joined(separator: " OR ") + ")")
        }

        if let minBytes {
            clauses.append("bytes_in >= ?")
            values.append(.int(minBytes))
        }
        if let maxBytes {
            clauses.append("bytes_in <= ?")
            values.append(.int(maxBytes))
        }
        if let minDuration {
            // Both ends are stored as integer microseconds, so this is integer
            // arithmetic in SQLite, not a float comparison. A row missing either
            // end yields NULL and is excluded, which is the honest answer to
            // "took longer than 5s" for a hop that was never timed.
            clauses.append("(\(Self.durationMicros)) >= ?")
            values.append(.int(Int64((minDuration * 1_000_000).rounded())))
        }
        for word in text {
            clauses.append("(host || COALESCE(json_extract(payload, '$.path'), '') LIKE ?)")
            values.append(.text("%\(word)%"))
        }
        if let since {
            clauses.append("at >= ?")
            values.append(.int(EventStore.micros(since)))
        }
        if let until {
            clauses.append("at <= ?")
            values.append(.int(EventStore.micros(until)))
        }
        return (clauses.joined(separator: " AND "), values)
    }

    /// `ORDER BY` for this query, ties broken by insertion order.
    ///
    /// `rowid` breaks ties rather than `id`: the id is a random UUID, so two
    /// events sharing a timestamp would come back in an order that changes
    /// between runs. A row whose duration could not be measured sorts last in
    /// either direction — `NULLS LAST` both ways, so "slowest first" does not
    /// open with a page of hops that were never timed.
    public var orderClause: String {
        let direction = ascending ? "ASC" : "DESC"
        let column = sort.column
        if sort == .time {
            return "ORDER BY at \(direction), rowid \(direction)"
        }
        return "ORDER BY (\(column)) IS NULL, (\(column)) \(direction), rowid DESC"
    }

    /// Cache hits carry no status of their own, so "no status" alone would read
    /// every cache hit as a failure. Asked of the payload rather than of a column
    /// because it has to hold for rows written before this view existed.
    /// Reads the denormalised column rather than the payload.
    ///
    /// It was `json_extract(payload, '$.fetchType') <> 'localCache'`, which no
    /// index can serve and which the summary asks of every row on every
    /// refresh: 0.29 s over 40,760 rows, every two seconds, on the actor that
    /// also has to service writes. ``EventStore`` backfills the column on
    /// migration, so no row is left NULL to be misread as "not from cache".
    static let notCached =
        "COALESCE(from_cache, json_extract(payload, '$.fetchType') = 'localCache', 0) = 0"

    static let durationMicros =
        "json_extract(payload, '$.responseEnd') - json_extract(payload, '$.fetchStart')"
}
