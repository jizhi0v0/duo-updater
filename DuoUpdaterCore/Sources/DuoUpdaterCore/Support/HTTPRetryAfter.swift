import Foundation
import CryptoKit

/// Retry-After's two wire forms (RFC 9110 §§5.6.7, 10.2.3). This only limits
/// retries a caller already permits; it never makes a response retryable.
enum HTTPRetryAfter {
    /// Process-lifetime only. A test injects its own store/clock without changing
    /// the application-wide singleton or another concurrently running case.
    @TaskLocal static var cooldowns: CooldownStore = .shared

    static func delaySeconds(_ response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        guard !value.isEmpty else { return nil }
        if value.utf8.allSatisfy({ (48...57).contains($0) }) {
            guard let seconds = TimeInterval(value), seconds.isFinite else { return nil }
            return seconds
        }
        guard now.timeIntervalSince1970.isFinite, let date = httpDate(value, now: now) else { return nil }
        let delay = date.timeIntervalSince(now)
        return delay.isFinite ? max(0, delay) : nil
    }

    /// A long requested wait ends this round instead of holding a scan slot or
    /// sending early. The caller still sleeps its entire configured pause.
    static func permitsRetry(_ response: HTTPURLResponse, after pause: Duration, now: Date = Date()) -> Bool {
        guard let asked = delaySeconds(response, now: now) else { return true }
        let components = pause.components
        let available = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return asked <= max(0, available)
    }

    private static let shortWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let longWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func captures(_ value: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range == NSRange(value.startIndex..., in: value)
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: value).map { String(value[$0]) }
        }
    }

    /// ReleaseDate deliberately accepts RSS/ISO spellings beyond HTTP-date.
    /// Keep the HTTP grammar here strict rather than allowing those spellings
    /// to silently acquire Retry-After semantics.
    private static func httpDate(_ value: String, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday: String
        let day: String
        let month: String
        let yearText: String
        let time: [String]
        let obsoleteYear: Bool
        if let parts = captures(value, pattern:
            #"^([A-Z][a-z]{2}), ([0-9]{2}) ([A-Z][a-z]{2}) ([0-9]{4}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT$"#) {
            weekday = parts[0]; day = parts[1]; month = parts[2]; yearText = parts[3]
            time = Array(parts[4...6]); obsoleteYear = false
        } else if let parts = captures(value, pattern:
            #"^([A-Z][a-z]+), ([0-9]{2})-([A-Z][a-z]{2})-([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT$"#) {
            weekday = parts[0]; day = parts[1]; month = parts[2]; yearText = parts[3]
            time = Array(parts[4...6]); obsoleteYear = true
        } else if let parts = captures(value, pattern:
            #"^([A-Z][a-z]{2}) ([A-Z][a-z]{2}) ( [1-9]|[0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) ([0-9]{4})$"#) {
            weekday = parts[0]; month = parts[1]; day = parts[2].trimmingCharacters(in: .whitespaces)
            time = Array(parts[3...5]); yearText = parts[6]; obsoleteYear = false
        } else { return nil }
        let weekdays = obsoleteYear ? longWeekdays : shortWeekdays
        guard let weekdayIndex = weekdays.firstIndex(of: weekday),
              let monthIndex = months.firstIndex(of: month),
              let dayNumber = Int(day), let statedYear = Int(yearText),
              let hour = Int(time[0]), let minute = Int(time[1]), let second = Int(time[2]),
              (1...31).contains(dayNumber), (0...23).contains(hour),
              (0...59).contains(minute), (0...60).contains(second)
        else { return nil }
        let currentYear = calendar.component(.year, from: now)
        var year = obsoleteYear
            ? currentYear + (statedYear - currentYear % 100 + 100) % 100 : statedYear
        func makeDate(_ year: Int) -> Date? {
            guard (1...9999).contains(year) else { return nil }
            let fields = DateComponents(
                year: year, month: monthIndex + 1, day: dayNumber,
                hour: hour, minute: minute, second: min(second, 59))
            guard let date = calendar.date(from: fields) else { return nil }
            let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            guard actual.year == year, actual.month == monthIndex + 1, actual.day == dayNumber,
                  actual.hour == hour, actual.minute == minute, actual.second == min(second, 59)
            else { return nil }
            return date
        }
        if obsoleteYear {
            // RFC 850 dates more than 50 years in the future mean the most
            // recent past year with the same final two digits.
            guard let boundary = calendar.date(byAdding: .year, value: 50, to: now) else { return nil }
            let fields = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: boundary)
            let limit = [fields.year!, fields.month!, fields.day!, fields.hour!, fields.minute!, fields.second!]
            if limit.lexicographicallyPrecedes([year, monthIndex + 1, dayNumber, hour, minute, second]) {
                year -= 100
            }
        }
        guard let date = makeDate(year) else { return nil }
        guard calendar.component(.weekday, from: date) == weekdayIndex + 1 else { return nil }
        // Date has no leap-second representation; the following instant is the
        // conservative retry deadline for a stated second 60.
        return second == 60 ? date.addingTimeInterval(1) : date
    }
}

extension HTTPRetryAfter {
    /// Remembers explicit Retry-After failures across check rounds that reuse a
    /// session. This is intentionally narrower than countedData: GitHub's API
    /// keeps its credential-aware GitHubRateLimitGate and 401 fallback intact.
    /// No body, raw URL, raw credentials or persistent state is retained.
    final class CooldownStore: @unchecked Sendable {
        static let shared = CooldownStore()

        private struct Key: Hashable {
            let session: UUID
            let method: String
            let endpoint: Data
            let credential: Data
        }
        private struct Entry {
            let status: Int
            let until: TimeInterval
        }
        private final class SessionIdentity {
            weak var session: URLSession?
            let nonce = UUID()
            init(_ session: URLSession) { self.session = session }
        }
        private struct RequestIdentity {
            let method: String
            let endpoint: Data
            let credential: Data
        }

        private let lock = NSLock()
        private let now: @Sendable () -> Date
        private var sessions: [ObjectIdentifier: SessionIdentity] = [:]
        private var entries: [Key: Entry] = [:]

        init(now: @escaping @Sendable () -> Date = Date.init) { self.now = now }

        func permitsRetry(_ response: HTTPURLResponse, after pause: Duration) -> Bool {
            HTTPRetryAfter.permitsRetry(response, after: pause, now: now())
        }

        /// A cached failure carries only its HTTP status. Returning it does not
        /// call countedData, book another transfer, or fabricate a success/body
        /// that could enter a source's conditional-response cache.
        func failure(for request: URLRequest, in session: URLSession) -> HTTPURLResponse? {
            guard let url = request.url, let identity = identity(for: request, in: session) else { return nil }
            let instant = now().timeIntervalSince1970
            let entry: Entry? = lock.withLock {
                purge(at: instant)
                guard let registered = sessions[ObjectIdentifier(session)], registered.session === session else { return nil }
                return entries[Key(session: registered.nonce, method: identity.method,
                                   endpoint: identity.endpoint, credential: identity.credential)]
            }
            guard let entry else { return nil }
            return HTTPURLResponse(url: url, statusCode: entry.status, httpVersion: "HTTP/1.1", headerFields: nil)
        }

        func observe(_ response: HTTPURLResponse, for request: URLRequest, in session: URLSession) {
            guard [429, 500, 502, 503, 504].contains(response.statusCode),
                  response.url.map({ !ChangelogService.isGitHubAPI($0) }) ?? true,
                  let identity = identity(for: request, in: session)
            else { return }
            let date = now()
            guard date.timeIntervalSince1970.isFinite,
                  let delay = HTTPRetryAfter.delaySeconds(response, now: date), delay > 0
            else { return }
            let instant = date.timeIntervalSince1970
            let sum = instant + delay
            // Never convert untrusted seconds to integer nanoseconds/Duration.
            // Saturating finite arithmetic also handles a huge finite header.
            let deadline = sum.isFinite ? sum : TimeInterval.greatestFiniteMagnitude
            lock.withLock {
                purge(at: instant)
                let object = ObjectIdentifier(session)
                let registered: SessionIdentity
                if let existing = sessions[object], existing.session === session {
                    registered = existing
                } else {
                    registered = SessionIdentity(session)
                    sessions[object] = registered
                }
                let key = Key(session: registered.nonce, method: identity.method,
                              endpoint: identity.endpoint, credential: identity.credential)
                // An already-in-flight answer must not shorten a longer wait
                // learned from a sibling request for the same identity.
                if let existing = entries[key], existing.until >= deadline { return }
                entries[key] = Entry(status: response.statusCode, until: deadline)
            }
        }

        /// Lazy expiry releases every expired entry on the next store access.
        /// Weak sessions own no resources here, and UUID nonces prevent a new
        /// object at a reused address from inheriting an old session's failure.
        private func purge(at instant: TimeInterval) {
            let live = Set(sessions.values.filter { $0.session != nil }.map(\.nonce))
            entries = entries.filter { $0.value.until > instant && live.contains($0.key.session) }
            let retained = Set(entries.keys.map(\.session))
            sessions = sessions.filter { $0.value.session != nil && retained.contains($0.value.nonce) }
        }

        private func identity(for request: URLRequest, in session: URLSession) -> RequestIdentity? {
            let method = (request.httpMethod ?? "GET").uppercased()
            guard method == "GET" || method == "HEAD", let url = request.url,
                  !ChangelogService.isGitHubAPI(url)
            else { return nil }
            // Only standard explicit authentication headers define credential
            // identity. Revalidation, tracing and Range headers may vary between
            // rounds without bypassing the deadline. Custom vendor account/API
            // headers conservatively share this endpoint's wait; they are not
            // claimed to be independently identified here.
            let fields: Set<String> = ["authorization", "cookie", "proxy-authorization"]
            var credentials: [String: String] = [:]
            for (key, value) in session.configuration.httpAdditionalHeaders ?? [:] {
                guard let name = key as? String, fields.contains(name.lowercased()) else { continue }
                credentials[name.lowercased()] = value as? String ?? String(describing: value)
            }
            for (name, value) in request.allHTTPHeaderFields ?? [:] where fields.contains(name.lowercased()) {
                credentials[name.lowercased()] = value
            }
            let canonical = credentials.sorted { $0.key < $1.key }.map { name, value in
                "\(name.utf8.count):\(name)\(value.utf8.count):\(value)"
            }.joined()
            return RequestIdentity(
                method: method, endpoint: Data(SHA256.hash(data: Data(url.absoluteString.utf8))),
                credential: Data(SHA256.hash(data: Data(canonical.utf8))))
        }

        /// Exposes only a count for deterministic expiry/resource tests.
        var entryCount: Int {
            let instant = now().timeIntervalSince1970
            return lock.withLock { purge(at: instant); return entries.count }
        }
    }
}
