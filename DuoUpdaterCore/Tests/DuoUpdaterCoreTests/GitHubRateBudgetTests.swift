import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// Where Settings ▸ GitHub's budget readout comes from: the rate-limit headers
/// of the last API answer that crossed the network, never a cached copy's.
///
/// Driven through the real loading system against a loopback server, as
/// `RequestCacheConsultationTests` is, so the transactions are the platform's
/// own. The server stands in for `api.github.com` through `isAPI`.
@Suite(.serialized)
struct GitHubRateBudgetTests {

    /// The window's end in every answer: an hour from now, whole seconds as the
    /// header has it, so a window the store is handed is still running.
    static let reset: TimeInterval = (Date().timeIntervalSince1970 + 3600).rounded(.down)

    /// Loopback HTTP/1.1 server. Each answer to `/releases` spends one of 60:
    /// - `/releases` — `ETag` + `Cache-Control: no-cache`, 304 to a matching
    ///   `If-None-Match`, as GitHub's API answers;
    /// - `/fresh` — `max-age=3600`, so a second fetch is answered from cache alone;
    /// - `/search` — the `search` budget, not `core`.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "GitHubRateBudgetTests.Server")
        private final class Count: @unchecked Sendable {
            let lock = NSLock()
            var spent = 0
        }
        private let count = Count()
        let port: UInt16

        init() throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let count = self.count
            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                    let text = String(decoding: data ?? Data(), as: UTF8.self)
                    let path = text.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
                    let conditional = text.lowercased().contains("if-none-match: \"v1\"")
                    let left = count.lock.withLock { count.spent += 1; return 60 - count.spent }
                    func budget(_ resource: String, limit: Int = 60) -> String {
                        "x-ratelimit-resource: \(resource)\r\nx-ratelimit-limit: \(limit)\r\n"
                            + "x-ratelimit-remaining: \(left)\r\nx-ratelimit-reset: \(Int(GitHubRateBudgetTests.reset))\r\n"
                    }
                    let body = Data("{\"tag_name\":\"v1.0.0\"}".utf8)
                    var header: String
                    var payload = Data()
                    switch path {
                    case "/releases" where conditional:
                        header = "HTTP/1.1 304 Not Modified\r\nETag: \"v1\"\r\nCache-Control: no-cache\r\n" + budget("core")
                    case "/releases":
                        header = "HTTP/1.1 200 OK\r\nETag: \"v1\"\r\nCache-Control: no-cache\r\n" + budget("core")
                        header += "Content-Length: \(body.count)\r\n"
                        payload = body
                    case "/fresh":
                        header = "HTTP/1.1 200 OK\r\nCache-Control: max-age=3600\r\n" + budget("core")
                        header += "Content-Length: \(body.count)\r\n"
                        payload = body
                    case "/search":
                        header = "HTTP/1.1 200 OK\r\n" + budget("search", limit: 10)
                        header += "Content-Length: \(body.count)\r\n"
                        payload = body
                    default:
                        header = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n"
                    }
                    header += "Connection: close\r\n\r\n"
                    conn.send(content: Data(header.utf8) + payload, completion: .contentProcessed { _ in conn.cancel() })
                }
            }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 5) == .success, let bound = listener.port?.rawValue
            else { throw URLError(.cannotConnectToHost) }
            self.port = bound
        }

        deinit { listener.cancel() }

        func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
    }

    private final class Capture: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var _metrics: URLSessionTaskMetrics?
        var metrics: URLSessionTaskMetrics? { lock.withLock { _metrics } }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            lock.withLock { _metrics = metrics }
        }
    }

    /// A session with its own memory cache, like `URLSession.updates`.
    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: config)
    }

    private static let loopback: @Sendable (URL) -> Bool = { $0.host == "127.0.0.1" }

    private static func fetch(
        _ url: URL, on session: URLSession, policy: URLRequest.CachePolicy = URLRequest.versionFeedCachePolicy
    ) async throws -> (response: HTTPURLResponse, metrics: URLSessionTaskMetrics) {
        var request = URLRequest(url: url)
        request.cachePolicy = policy
        let capture = Capture()
        let (_, response) = try await session.data(for: request, delegate: capture)
        for _ in 0..<100 where capture.metrics == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        return (try #require(response as? HTTPURLResponse), try #require(capture.metrics))
    }

    /// A revalidation's budget is the 304's, not the cached copy's. The fixture
    /// first pins the premise: the lookup transaction carries the stored
    /// response's count. (What `data(for:)` returns carried the 304's here —
    /// the platform merged its headers in — which nothing relies on.)
    @Test func aRevalidationReadsTheNetworkAnswer() async throws {
        let server = try Server()
        let session = Self.session()
        let first = try await Self.fetch(server.url("/releases"), on: session)
        #expect(GitHubRateBudget.reading(from: first.metrics, isAPI: Self.loopback)
            == GitHubRateBudget(limit: 60, remaining: 59, reset: Date(timeIntervalSince1970: Self.reset)))

        let second = try await Self.fetch(server.url("/releases"), on: session)
        let transactions = second.metrics.transactionMetrics
        try #require(transactions.map(\.resourceFetchType) == [.localCache, .networkLoad])
        let cached = transactions[0].response as? HTTPURLResponse
        try #require(cached?.value(forHTTPHeaderField: "x-ratelimit-remaining") == "59")

        #expect(GitHubRateBudget.reading(from: second.metrics, isAPI: Self.loopback)?.remaining == 58)
    }

    /// A fetch answered from cache alone asked nobody: no reading. Mutation: drop
    /// the `networkLoad` filter (the cached copy's 59 comes back).
    @Test func aCacheHitIsNoReading() async throws {
        let server = try Server()
        let session = Self.session()
        _ = try await Self.fetch(server.url("/fresh"), on: session, policy: .useProtocolCachePolicy)
        let second = try await Self.fetch(server.url("/fresh"), on: session, policy: .useProtocolCachePolicy)
        try #require(second.metrics.transactionMetrics.map(\.resourceFetchType) == [.localCache])
        #expect(GitHubRateBudget.reading(from: second.metrics, isAPI: Self.loopback) == nil)
    }

    /// Only the API's `core` budget. Mutations: drop the resource check; drop
    /// `isAPI`.
    @Test func onlyTheAPIsCoreBudget() async throws {
        let server = try Server()
        let session = Self.session()
        let search = try await Self.fetch(server.url("/search"), on: session)
        #expect(GitHubRateBudget.reading(from: search.metrics, isAPI: Self.loopback) == nil)
        let elsewhere = try await Self.fetch(server.url("/releases"), on: session)
        #expect(GitHubRateBudget.reading(from: elsewhere.metrics, isAPI: { _ in false }) == nil)
    }

    /// Every `countedData` fetch's metrics reach the store, through the
    /// recorder. Mutation: drop `rateBudget.observe(metrics)`.
    @Test func theRecorderFeedsTheStore() async throws {
        let server = try Server()
        let session = Self.session()
        let budget = GitHubRateBudget.Store(isAPI: Self.loopback)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID().uuidString).sqlite")
        let events = EventStore(
            fileURL: file, retentionDays: 30, retentionBytes: 64 * 1024 * 1024,
            flushEventCount: 1, flushDelay: .milliseconds(10), pruneInterval: .seconds(3600), now: Date.init)
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: file.path + suffix)
            }
        }
        #expect(budget.current(at: Date()).isEmpty && budget.lastReset == nil)
        for _ in 0..<2 {
            var request = URLRequest(url: server.url("/releases"))
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            _ = try await session.data(
                for: request, delegate: RequestMetricsRecorder(.versionCheck, store: events, rateBudget: budget))
        }
        for _ in 0..<100 where budget.current(at: Date()).first?.remaining != 58 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(budget.current(at: Date())
            == [GitHubRateBudget(limit: 60, remaining: 58, reset: Date(timeIntervalSince1970: Self.reset))])
    }

    /// A change in Settings empties the card until the new credentials answer,
    /// and an answer to a request made under the old ones is not kept.
    /// Mutations: drop the generation guard in `record`; drop the generation
    /// check in `current(at:)` and `lastReset`; keep the windows in `record`
    /// when the generation has moved on.
    @Test func aCredentialChangeKeepsOnlyTheNewCredentialsAnswers() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let credentials = GitHubCredentials()
        let store = GitHubRateBudget.Store(isAPI: { _ in false }, credentials: credentials)
        let token = GitHubRateBudget(limit: 5000, remaining: 4200, reset: now.addingTimeInterval(600))
        let before = credentials.generation
        store.record(token, now: now, generation: before)
        #expect(store.current(at: now) == [token])

        credentials.changed()
        #expect(store.current(at: now).isEmpty)
        #expect(store.lastReset == nil, "the card reads \"No answer from GitHub yet\"")
        // The old round's request answers after the change.
        store.record(GitHubRateBudget(limit: 5000, remaining: 4100, reset: token.reset), now: now, generation: before)
        #expect(store.current(at: now).isEmpty && store.lastReset == nil)

        let anonymous = GitHubRateBudget(limit: 60, remaining: 59, reset: now.addingTimeInterval(3600))
        store.record(anonymous, now: now, generation: credentials.generation)
        #expect(store.current(at: now) == [anonymous])

        // Another token on the same limit as the first: the first's window does
        // not come back beside it.
        let first = credentials.generation
        store.record(token, now: now, generation: first)
        credentials.changed()
        let other = GitHubRateBudget(limit: 5000, remaining: 4999, reset: now.addingTimeInterval(1800))
        store.record(other, now: now, generation: credentials.generation)
        #expect(store.current(at: now) == [other])
    }

    /// The recorder tags the request with the generation it was made under —
    /// when it was made, not when its metrics arrive, and the pinned one inside a
    /// round still checking with an older token. Mutations: read the generation
    /// in the metrics callback instead of at init; ignore `pinnedGeneration`.
    @Test func theRecorderTagsTheGenerationTheRequestWasMadeUnder() async throws {
        let server = try Server()
        let session = Self.session()
        let credentials = GitHubCredentials()
        let budget = GitHubRateBudget.Store(isAPI: Self.loopback, credentials: credentials)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID().uuidString).sqlite")
        let events = EventStore(
            fileURL: file, retentionDays: 30, retentionBytes: 64 * 1024 * 1024,
            flushEventCount: 1, flushDelay: .milliseconds(10), pruneInterval: .seconds(3600), now: Date.init)
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: file.path + suffix)
            }
        }
        func fetch(_ recorder: RequestMetricsRecorder) async throws {
            var request = URLRequest(url: server.url("/fresh"))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            _ = try await session.data(for: request, delegate: recorder)
            // The metrics callback can trail the response by a moment.
            try await Task.sleep(for: .milliseconds(200))
        }

        // Made before the change, answered after it.
        let early = RequestMetricsRecorder(.versionCheck, store: events, rateBudget: budget)
        let old = credentials.generation
        credentials.changed()
        try await fetch(early)
        #expect(budget.current(at: Date()).isEmpty)

        // Made after the change, inside a round pinned to the old generation.
        let pinned = GitHubCredentials.$pinnedGeneration.withValue(old) {
            RequestMetricsRecorder(.versionCheck, store: events, rateBudget: budget)
        }
        try await fetch(pinned)
        #expect(budget.current(at: Date()).isEmpty)

        // Made under the credentials in use: kept.
        try await fetch(RequestMetricsRecorder(.versionCheck, store: events, rateBudget: budget))
        for _ in 0..<100 where budget.current(at: Date()).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(budget.current(at: Date()).map(\.limit) == [60])
    }

    /// Within one window answers finish out of order: the lower count is kept.
    /// Mutation: keep the last one seen whatever its count.
    @Test func withinAWindowTheLowerCountIsKept() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let hour = now.addingTimeInterval(1800)
        let kept = [GitHubRateBudget(limit: 60, remaining: 30, reset: hour)]
        #expect(GitHubRateBudget.keeping(kept, .init(limit: 60, remaining: 31, reset: hour), now: now) == kept)
        #expect(GitHubRateBudget.keeping(kept, .init(limit: 60, remaining: 29, reset: hour), now: now).map(\.remaining)
            == [29])
        #expect(GitHubRateBudget.keeping([], kept[0], now: now) == kept)
    }

    /// A token's two windows (observed 2026-10-08: one for `releases/latest`,
    /// one for the rest) are both kept, earliest reset first, whichever answers
    /// last. Mutation: let a different reset replace the window kept (the old
    /// single-reading rule).
    @Test func twoWindowsOfOneLimitAreBothKept() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let early = GitHubRateBudget(limit: 5000, remaining: 4200, reset: now.addingTimeInterval(600))
        let late = GitHubRateBudget(limit: 5000, remaining: 3945, reset: now.addingTimeInterval(1800))
        #expect(GitHubRateBudget.keeping([early], late, now: now) == [early, late])
        #expect(GitHubRateBudget.keeping([late], early, now: now) == [early, late])
        // Each keeps its own lower count.
        let lower = GitHubRateBudget(limit: 5000, remaining: 4100, reset: early.reset)
        #expect(GitHubRateBudget.keeping([early, late], lower, now: now) == [lower, late])
    }

    /// A token added or removed is another budget: every window kept goes.
    /// Mutation: drop the `limit` filter.
    @Test func anotherLimitDropsEveryWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let kept = [GitHubRateBudget(limit: 5000, remaining: 4200, reset: now.addingTimeInterval(600)),
                    GitHubRateBudget(limit: 5000, remaining: 3945, reset: now.addingTimeInterval(1800))]
        let anonymous = GitHubRateBudget(limit: 60, remaining: 59, reset: now.addingTimeInterval(3600))
        #expect(GitHubRateBudget.keeping(kept, anonymous, now: now) == [anonymous])
    }

    /// A window whose reset has passed is dropped, and a late answer from one is
    /// not kept. Mutations: drop the `isCurrent` filter on the windows kept; keep
    /// an ended `seen`.
    @Test func endedWindowsAreDropped() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ended = GitHubRateBudget(limit: 5000, remaining: 12, reset: now.addingTimeInterval(-1))
        let running = GitHubRateBudget(limit: 5000, remaining: 4999, reset: now.addingTimeInterval(3600))
        #expect(GitHubRateBudget.keeping([ended], running, now: now) == [running])
        #expect(GitHubRateBudget.keeping([running], ended, now: now) == [running])
    }

    /// At most `windowCap`, the ones that end soonest dropped first. Mutations:
    /// drop the cap; keep the earliest instead of the latest.
    @Test func theWindowsAreCapped() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let windows = (1...4).map { GitHubRateBudget(limit: 5000, remaining: 100 * $0, reset: now.addingTimeInterval(Double(600 * $0))) }
        let kept = windows.dropLast().reduce(into: [GitHubRateBudget]()) { $0 = GitHubRateBudget.keeping($0, $1, now: now) }
        #expect(kept == Array(windows.prefix(3)))
        #expect(GitHubRateBudget.keeping(kept, windows[3], now: now) == Array(windows.suffix(3)))
    }

    /// The store: running windows only, and, once all have ended, when the
    /// budget last refilled — not "nothing seen". Mutations: drop the
    /// `isCurrent` filter in `current(at:)`; overwrite the windows with an empty
    /// list when an ended answer arrives.
    @Test func theStoreSaysWhatIsRunningAndWhenItLastRefilled() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = GitHubRateBudget.Store(isAPI: { _ in false })
        #expect(store.current(at: now).isEmpty && store.lastReset == nil)
        let early = GitHubRateBudget(limit: 5000, remaining: 4200, reset: now.addingTimeInterval(600))
        let late = GitHubRateBudget(limit: 5000, remaining: 3945, reset: now.addingTimeInterval(1800))
        store.record(late, now: now)
        store.record(early, now: now)
        #expect(store.current(at: now) == [early, late])
        #expect(store.current(at: now.addingTimeInterval(900)) == [late])
        let after = now.addingTimeInterval(2000)
        #expect(store.current(at: after).isEmpty)
        #expect(store.lastReset == late.reset)
        // A late answer from an ended window leaves that answer standing.
        store.record(GitHubRateBudget(limit: 5000, remaining: 1, reset: now.addingTimeInterval(1900)), now: after)
        #expect(store.lastReset == late.reset)
    }

    /// Under a fifth left is low, a fifth is not. Mutation: `<` → `<=`.
    @Test func aFifthLeftIsTheWarning() {
        let reset = Date(timeIntervalSince1970: Self.reset)
        #expect(GitHubRateBudget(limit: 5000, remaining: 999, reset: reset).isRunningLow)
        #expect(!GitHubRateBudget(limit: 5000, remaining: 1000, reset: reset).isRunningLow)
        #expect(GitHubRateBudget(limit: 60, remaining: 11, reset: reset).isRunningLow)
        #expect(!GitHubRateBudget(limit: 60, remaining: 12, reset: reset).isRunningLow)
    }

    /// Past its reset a count is no longer what is left. Mutation: always true.
    @Test func aReadingEndsWithItsWindow() {
        let hour = Date(timeIntervalSince1970: Self.reset)
        let budget = GitHubRateBudget(limit: 60, remaining: 3, reset: hour)
        #expect(budget.isCurrent(at: hour.addingTimeInterval(-1)))
        #expect(!budget.isCurrent(at: hour))
        #expect(!budget.isCurrent(at: hour.addingTimeInterval(60)))
    }
}
