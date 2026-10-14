import Foundation

/// Whether GitHub's REST API may be asked again — closed, per credential, from
/// the moment an answer says the budget is spent until GitHub says it may be
/// asked again, so nothing we send in between is a request made while rate
/// limited.
///
/// **Why.** GitHub's documentation (docs.github.com/en/rest/using-the-rest-api/
/// rate-limits-for-the-rest-api, read verbatim 2026-10-14): "If you exceed your
/// primary rate limit, you will receive a 403 or 429 response, and the
/// x-ratelimit-remaining header will be 0. You should not retry your request
/// until after the time specified by the x-ratelimit-reset header." For a
/// secondary limit: "If the retry-after response header is present, you should
/// not retry your request until after that many seconds has elapsed. If the
/// x-ratelimit-remaining header is 0, you should not retry your request until
/// after the time … specified by the x-ratelimit-reset header. Otherwise, wait
/// for at least one minute before retrying. If your request continues to fail
/// due to a secondary rate limit, wait for an exponentially increasing amount
/// of time between retries". And: "Continuing to make requests while you are
/// rate limited may result in the banning of your integration." Measured on
/// 2026-10-14 in the app's own request log: with the budget spent, every
/// five-minute tick asked again for every GitHub-tracked app and tool — 381
/// answers of 403 in half an hour.
///
/// **Per credential.** A token's budget and the anonymous one are apart, so one
/// spent leaves the other open. A token replaced is a new budget
/// (`reopen(_:)`).
///
/// **Conservative.** A token's requests can be counted against two hourly
/// windows at once (`GitHubRateBudget`); any answer that says one is spent
/// closes the credential until that answer's reset. Better to wait out a
/// window that another endpoint still had room in than to ask one that has
/// none.
public enum GitHubRateLimitGate {
    /// Whose budget a request spends: one sent with a token, or one without.
    public enum Credential: String, Sendable, Hashable, Codable, CaseIterable {
        case token
        case anonymous
    }

    /// Why the gate is closed, for the log and for a row's wording.
    public enum Reason: Sendable, Equatable, Codable {
        /// The primary budget is spent (`x-ratelimit-remaining: 0`).
        case exhausted
        /// A secondary limit; `strike` counts the refusals in a row, 1 for the first.
        case secondary(strike: Int)
    }

    /// A closed gate: no request on the credential before `until`.
    public struct Closure: Sendable, Equatable, Codable {
        public let until: Date
        public let reason: Reason
        public init(until: Date, reason: Reason) {
            self.until = until
            self.reason = reason
        }
    }

    /// The shortest wait after a secondary limit that named none: "wait for at
    /// least one minute before retrying".
    public static let secondaryFloor: TimeInterval = 60
    /// The longest a secondary limit's doubling may reach. GitHub sets none;
    /// an hour is the primary budget's own window, past which a doubling only
    /// stretches the outage without making a request any safer.
    public static let secondaryCeiling: TimeInterval = 3600

    /// What an answer from `api.github.com` does to the gate: close it (and
    /// until when), or nothing. `headers` are matched case-insensitively.
    /// `strikesBefore` is how many secondary refusals came right before this
    /// one; `body` is read only to tell a secondary limit's 403 from any other.
    public static func closure(
        status: Int, headers: [String: String], body: Data?, strikesBefore: Int, now: Date
    ) -> Closure? {
        let header = { (name: String) in
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
                .trimmingCharacters(in: .whitespaces)
        }
        let resource = header("x-ratelimit-resource")?.lowercased()
        let remaining = header("x-ratelimit-remaining").flatMap(Int.init)
        let reset = header("x-ratelimit-reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        let retryAfter = header("retry-after").flatMap(TimeInterval.init)
        // Search and GraphQL keep budgets of their own; the app asks `core`.
        // An answer without the header is taken as `core`, the REST default.
        let isCore = resource == nil || resource == "core"

        // Spent, whatever the status: the next request would be refused. A
        // reset already past means the window has refilled.
        if isCore, remaining == 0, let reset, reset > now {
            return Closure(until: reset, reason: .exhausted)
        }
        guard status == 403 || status == 429 else { return nil }
        if let retryAfter, retryAfter > 0 {
            return Closure(until: now.addingTimeInterval(retryAfter), reason: .secondary(strike: strikesBefore + 1))
        }
        // A 403 is also a forbidden repository or a private one; only a 429 or
        // a body that names a rate limit is a limit with no header to wait by.
        let saysRateLimit = body.flatMap { String(data: $0, encoding: .utf8) }?
            .range(of: "rate limit", options: .caseInsensitive) != nil
        guard status == 429 || saysRateLimit else { return nil }
        let strike = strikesBefore + 1
        let wait = min(secondaryFloor * pow(2, Double(strike - 1)), secondaryCeiling)
        return Closure(until: now.addingTimeInterval(wait), reason: .secondary(strike: strike))
    }

    /// A request held back by the gate, never sent. Its description keeps the
    /// phrase "rate limit": `UpdateStatus.isRateLimitError` matches on it, so a
    /// row it fails shows as rate-limited, not as a failed or offline check
    /// (and is not retried as a transient network error).
    public struct Refused: LocalizedError, Sendable, Equatable {
        public let credential: Credential
        public let closure: Closure
        public var errorDescription: String? {
            "GitHub rate limit reached — paused until \(closure.until.formatted(date: .omitted, time: .shortened))"
        }
    }

    /// The gate `countedData` and `countedBytes` pass requests through by
    /// default: nil until a process that sends real requests turns it on with
    /// `activate()` — the app at launch, `duo` at start. Off otherwise, so a
    /// test process's stubbed GitHub is not probed or closed by another test;
    /// the gate's own tests hand theirs in. `scripts/check_github_gate.py`
    /// fails the build if either entry point stops calling `activate()`.
    public static var active: Store? { activeLock.withLock { activeStore } }
    nonisolated(unsafe) private static var activeStore: Store?
    private static let activeLock = NSLock()

    /// Turn the gate on for this process. Idempotent.
    public static func activate() {
        activeLock.withLock { activeStore = .shared }
    }

    /// Whether `error` is the gate holding a request back.
    public static func isRefusal(_ error: Error) -> Bool { error is Refused }

    /// One request's way through the gate: admitted (or refused, by throwing),
    /// then told what came back. Nil for a request the gate does not cover:
    /// not to the API, or the probe itself.
    struct Pass: Sendable {
        let gate: Store
        let credential: Credential
        let identity: Int
        let canary: Bool

        /// `send` sends the probe this request's credential calls for,
        /// ungated; nil when it got no answer.
        init?(
            admitting request: URLRequest, gate: Store?,
            probe send: @escaping @Sendable (URLRequest) async -> (Data, URLResponse)?
        ) async throws {
            guard let gate, let url = request.url, ChangelogService.isGitHubAPI(url), url.path != "/rate_limit"
            else { return nil }
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            credential = authorization == nil ? .anonymous : .token
            // A token's budget is the token's: switched to another and back,
            // it is the same entry — and either way, a new one is probed.
            identity = authorization.map { $0.hashValue } ?? 0
            self.gate = gate
            let probe = Self.probe(like: request)
            switch await gate.admit(credential, generation: identity, probe: {
                guard let (data, response) = await send(probe) else { return nil }
                return Self.answer(data, response)
            }) {
            case .refused(let closure): throw Refused(credential: credential, closure: closure)
            case .go(let canary): self.canary = canary
            }
        }

        func complete(_ data: Data?, _ response: URLResponse?) async {
            let http = response as? HTTPURLResponse
            let headers = (http?.allHeaderFields ?? [:]).reduce(into: [String: String]()) {
                if let key = $1.key as? String, let value = $1.value as? String { $0[key] = value }
            }
            // The body only names a secondary limit on a refusal.
            let refusal = http.map { $0.statusCode == 403 || $0.statusCode == 429 } ?? false
            await gate.complete(credential, generation: identity, canary: canary,
                                status: http?.statusCode, headers: headers, body: refusal ? data : nil)
        }

        /// `GET /rate_limit` with `request`'s credential.
        static func probe(like request: URLRequest) -> URLRequest {
            var probe = URLRequest(url: URL(string: "https://api.github.com/rate_limit")!)
            probe.timeoutInterval = 10
            for field in ["Authorization", "User-Agent"] {
                if let value = request.value(forHTTPHeaderField: field) { probe.setValue(value, forHTTPHeaderField: field) }
            }
            probe.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            return probe
        }

        /// The `core` budget a `/rate_limit` answer states; nil when it does not.
        static func answer(_ data: Data, _ response: URLResponse) -> ProbeAnswer? {
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let core = (root["resources"] as? [String: Any])?["core"] as? [String: Any],
                  let remaining = core["remaining"] as? Int,
                  let reset = (core["reset"] as? NSNumber)?.doubleValue
            else { return nil }
            return ProbeAnswer(remaining: remaining, reset: Date(timeIntervalSince1970: reset))
        }
    }

    /// What a probe of `GET /rate_limit` says of the `core` budget.
    public struct ProbeAnswer: Sendable, Equatable {
        public let remaining: Int
        public let reset: Date
        public init(remaining: Int, reset: Date) {
            self.remaining = remaining
            self.reset = reset
        }
    }

    /// What `Store.admit` says of one request.
    public enum Admission: Sendable, Equatable {
        /// Send it. `canary`: it is the one request let through after a probe;
        /// the others wait for its answer, so `Store.complete` must be told
        /// how it went, answered or not.
        case go(canary: Bool)
        /// Do not send it: the gate is closed until `closure.until`.
        case refused(GitHubRateLimitGate.Closure)
    }

    /// The process's gate. Every request to `api.github.com` asks `admit`
    /// before it goes out and tells `complete` how it went.
    ///
    /// Per credential, a gate is in one of these states:
    /// - **unknown** — nothing is known of the budget: at the process's first
    ///   request, after the token changed (a new budget, or an old one switched
    ///   back to), after a closure ended. The next request first probes
    ///   `GET /rate_limit` with the same credential: GitHub's documentation says
    ///   "Calling this endpoint does not count against your primary rate limit,
    ///   but it can count against your secondary rate limit", so it is asked
    ///   only at these moments, once, while every other request waits for it.
    /// - **canary** — the probe found room. It reads one of a token's windows
    ///   (`GitHubRateBudget`), and "the x-ratelimit-* headers are the
    ///   authoritative source … and may differ from values reported by the GET
    ///   /rate_limit endpoint", so one real request goes first and the rest wait
    ///   for its headers. At worst one request meets a spent budget.
    /// - **open** — requests go; any answer saying the budget is spent closes it.
    /// - **closed** — no request until the closure ends; then unknown again.
    public actor Store {
        public static let shared = Store()

        private enum Phase {
            case unknown
            case probing(Task<Void, Never>)
            /// `nil` until a request takes the canary's place, then its number.
            case canary(Int?)
            case open
            case closed(Closure)
        }

        private struct Entry {
            var phase: Phase = .unknown
            /// The credentials generation the entry describes (token only).
            var generation: Int
            var strikes = 0
            var heldBack = 0
        }

        /// Yields each time a credential closes or its closure ends, for a UI
        /// that shows until when (`closure(_:)` then says). It does not yield at
        /// the moment a closure's time passes — nothing happens then — so a UI
        /// also wakes itself at `until`.
        public nonisolated let changes: AsyncStream<Void>
        private let changed: AsyncStream<Void>.Continuation

        private var entries: [Credential: Entry] = [:]
        /// The requests waiting for each canary, by its number, until its
        /// answer — or the lack of one — releases them.
        private var canaryWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
        private var releasedCanaries: Set<Int> = []
        private var nextCanary = 0
        private let now: @Sendable () -> Date
        /// How long the others wait for a canary's answer before going anyway:
        /// a gate must never be what hangs a check.
        private let canaryPatience: Duration

        public init(now: @escaping @Sendable () -> Date = { Date() }, canaryPatience: Duration = .seconds(20)) {
            self.now = now
            self.canaryPatience = canaryPatience
            (changes, changed) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        }

        /// Whether a request on `credential` may go. `generation` is the
        /// credentials generation it is sent under (`GitHubCredentials`), 0
        /// for anonymous. `probe` asks `GET /rate_limit` with the same
        /// credential, bypassing the gate; nil when it could not be read.
        public func admit(
            _ credential: Credential, generation: Int,
            probe: @escaping @Sendable () async -> ProbeAnswer?
        ) async -> Admission {
            while true {
                var entry = current(credential, generation)
                switch entry.phase {
                case .open:
                    return .go(canary: false)
                case .closed(let closure):
                    if closure.until > now() {
                        entry.heldBack += 1
                        entries[credential] = entry
                        return .refused(closure)
                    }
                    Log.app.notice("GitHub API (\(credential.rawValue, privacy: .public)): closure ended; \(entry.heldBack, privacy: .public) request(s) were held back — probing before reopening")
                    entry.phase = .unknown
                    entry.heldBack = 0
                    entries[credential] = entry
                    changed.yield()
                case .unknown:
                    let task = Task { [now] in
                        let answer = await probe()
                        await self.probed(credential, generation: generation, answer: answer, at: now())
                    }
                    entry.phase = .probing(task)
                    entries[credential] = entry
                    await task.value
                case .probing(let task):
                    await task.value
                case .canary(nil):
                    nextCanary += 1
                    entry.phase = .canary(nextCanary)
                    entries[credential] = entry
                    return .go(canary: true)
                case .canary(let id?):
                    await waitForCanary(id, credential, generation)
                }
            }
        }

        /// Tell the gate how a request it let through went: its status,
        /// headers and body, or nil for each when no answer came (offline,
        /// cancelled).
        public func complete(
            _ credential: Credential, generation: Int, canary: Bool,
            status: Int?, headers: [String: String], body: Data?
        ) {
            var entry = current(credential, generation)
            let at = now()
            if let status {
                // A refusal while already closed answers a request that was in
                // flight when it closed, not a retry after waiting: the same
                // strike, so a burst does not double the wait once per request.
                let inForce: Bool
                if case .closed(let kept) = entry.phase { inForce = kept.until > at } else { inForce = false }
                let before = max(entry.strikes - (inForce ? 1 : 0), 0)
                if let closure = GitHubRateLimitGate.closure(
                    status: status, headers: headers, body: body, strikesBefore: before, now: at) {
                    if case .secondary(let strike) = closure.reason { entry.strikes = strike }
                    close(&entry, closure, credential, status: status)
                } else if (200..<400).contains(status) {
                    entry.strikes = 0
                }
            }
            // The canary's answer — or its failure to get one — releases the
            // others; open unless that answer closed the gate.
            if canary, case .canary(let id?) = entry.phase {
                entry.phase = .open
                release(id)
            }
            entries[credential] = entry
        }

        /// Until when each credential is closed now; one absent is open.
        public func pause() -> [Credential: Date] {
            var pause: [Credential: Date] = [:]
            for credential in Credential.allCases { pause[credential] = closure(credential)?.until }
            return pause
        }

        /// Whether either credential is closed now.
        public func isHoldingBack() -> Bool {
            Credential.allCases.contains { closure($0) != nil }
        }

        /// The closure in force on `credential`, for a row or a banner that
        /// wants to say until when. Nil when open or unknown.
        public func closure(_ credential: Credential) -> Closure? {
            guard case .closed(let closure) = entries[credential]?.phase, closure.until > now() else { return nil }
            return closure
        }

        private func current(_ credential: Credential, _ generation: Int) -> Entry {
            // Another token is another budget — or an old one switched back
            // to, whose state we no longer trust: start from unknown.
            if let entry = entries[credential], entry.generation == generation { return entry }
            let fresh = Entry(generation: generation)
            entries[credential] = fresh
            return fresh
        }

        private func probed(_ credential: Credential, generation: Int, answer: ProbeAnswer?, at: Date) {
            var entry = current(credential, generation)
            guard case .probing = entry.phase else { return }
            if let answer, answer.remaining == 0, answer.reset > at {
                close(&entry, Closure(until: answer.reset, reason: .exhausted), credential, status: nil)
            } else {
                // Room, or no answer (offline): one canary decides.
                entry.phase = .canary(nil)
            }
            entries[credential] = entry
        }

        private func waitForCanary(_ id: Int, _ credential: Credential, _ generation: Int) async {
            guard !releasedCanaries.contains(id) else { return }
            let patience = canaryPatience
            let timer = Task { [weak self] in
                try? await Task.sleep(for: patience)
                guard !Task.isCancelled else { return }
                await self?.canaryTimedOut(id, credential, generation)
            }
            await withCheckedContinuation { canaryWaiters[id, default: []].append($0) }
            timer.cancel()
        }

        private func release(_ id: Int) {
            releasedCanaries.insert(id)
            canaryWaiters.removeValue(forKey: id)?.forEach { $0.resume() }
        }

        private func canaryTimedOut(_ id: Int, _ credential: Credential, _ generation: Int) {
            guard !releasedCanaries.contains(id) else { return }
            var entry = current(credential, generation)
            if case .canary(let current?) = entry.phase, current == id {
                Log.app.notice("GitHub API (\(credential.rawValue, privacy: .public)): canary unanswered after \(Log.seconds(self.canaryPatience), privacy: .public) — opening")
                entry.phase = .open
                entries[credential] = entry
            }
            release(id)
        }

        private func close(_ entry: inout Entry, _ closure: Closure, _ credential: Credential, status: Int?) {
            // Answers to requests in flight together land one by one: keep the
            // latest end, never shorten a wait.
            if case .closed(let kept) = entry.phase, kept.until >= closure.until { return }
            if case .canary(let id?) = entry.phase { release(id) }
            if case .closed = entry.phase {} else { entry.heldBack = 0 }
            entry.phase = .closed(closure)
            changed.yield()
            let why = status.map { "status \($0)" } ?? "probe"
            Log.app.error("GitHub API (\(credential.rawValue, privacy: .public)) closed until \(closure.until.formatted(.iso8601), privacy: .public): \(String(describing: closure.reason), privacy: .public), \(why, privacy: .public)")
        }
    }
}
