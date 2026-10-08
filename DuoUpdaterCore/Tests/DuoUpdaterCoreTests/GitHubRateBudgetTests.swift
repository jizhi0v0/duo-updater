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

    /// 2026-10-08 10:00:00 UTC, the window's end in every answer.
    static let reset: TimeInterval = 1_791_453_600

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
        #expect(budget.latest == nil)
        for _ in 0..<2 {
            var request = URLRequest(url: server.url("/releases"))
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            _ = try await session.data(
                for: request, delegate: RequestMetricsRecorder(.versionCheck, store: events, rateBudget: budget))
        }
        for _ in 0..<100 where budget.latest?.remaining != 58 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(budget.latest == GitHubRateBudget(limit: 60, remaining: 58, reset: Date(timeIntervalSince1970: Self.reset)))
    }

    /// Answers finish out of order. Mutations: keep the last one seen whatever
    /// its count; let a late answer from an ended window replace a newer one.
    @Test func whichReadingIsKept() {
        let hour = Date(timeIntervalSince1970: Self.reset)
        let now = GitHubRateBudget(limit: 60, remaining: 30, reset: hour)
        // The same window: the lower count is the later answer.
        #expect(GitHubRateBudget.keeping(now, .init(limit: 60, remaining: 31, reset: hour)) == now)
        #expect(GitHubRateBudget.keeping(now, .init(limit: 60, remaining: 29, reset: hour)).remaining == 29)
        // A new window replaces it; the ended one's late answer does not.
        let next = GitHubRateBudget(limit: 60, remaining: 59, reset: hour.addingTimeInterval(3600))
        #expect(GitHubRateBudget.keeping(now, next) == next)
        #expect(GitHubRateBudget.keeping(next, now) == next)
        // A token: another budget, whatever its count.
        let token = GitHubRateBudget(limit: 5000, remaining: 4990, reset: hour.addingTimeInterval(-600))
        #expect(GitHubRateBudget.keeping(now, token) == token)
        #expect(GitHubRateBudget.keeping(nil, now) == now)
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
