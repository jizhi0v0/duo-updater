import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// What a revalidation is booked as (#889).
///
/// When `URLCache` holds a copy it has to revalidate, the platform reports two
/// transactions for the one URL — the cache lookup and the conditional request
/// that went out. Both used to be recorded, so every revalidation counted as a
/// cache hit *and* as two requests. These tests drive the real loading system
/// against a loopback server so the metrics are the platform's own, then feed
/// them through ``RequestMetricsRecorder/events(from:task:purpose:appID:)``.
///
/// Each case first pins the transaction shape it depends on. Without that, a
/// platform that stopped reporting the lookup would pass the "one row" checks
/// for the wrong reason.
@Suite(.serialized)
struct RequestCacheConsultationTests {

    /// Loopback HTTP/1.1 server with three routes:
    ///
    /// - `/feed.xml` — `ETag` + `Cache-Control: no-cache`, so a cached copy must
    ///   be revalidated; answers 304 to a matching `If-None-Match`.
    /// - `/fresh.xml` — `max-age=3600`, so a second fetch under the protocol
    ///   policy is answered from cache without a request.
    /// - `/moved` — a cacheable 301 to `/feed.xml`.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "RequestCacheConsultationTests.Server")
        private final class Log: @unchecked Sendable {
            let lock = NSLock()
            var hits: [String] = []
            var conditional = 0
        }
        private let log = Log()
        let port: UInt16

        /// Paths requested over the network, in order.
        var hits: [String] { log.lock.withLock { log.hits } }
        /// Requests that carried `If-None-Match`.
        var conditional: Int { log.lock.withLock { log.conditional } }

        init() throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let log = self.log
            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                    let text = String(decoding: data ?? Data(), as: UTF8.self)
                    let path = text.split(separator: " ", maxSplits: 2).dropFirst().first
                        .map(String.init) ?? "/"
                    let conditional = text.lowercased().contains("if-none-match: \"v1\"")
                    log.lock.withLock {
                        log.hits.append(path)
                        if conditional { log.conditional += 1 }
                    }

                    let body = Data(repeating: 0x61, count: 500)
                    var header: String
                    var payload = Data()
                    switch path {
                    case "/feed.xml" where conditional:
                        header = "HTTP/1.1 304 Not Modified\r\nETag: \"v1\"\r\n"
                        header += "Cache-Control: no-cache\r\n"
                    case "/feed.xml":
                        header = "HTTP/1.1 200 OK\r\nETag: \"v1\"\r\n"
                        header += "Cache-Control: no-cache\r\n"
                        header += "Content-Length: \(body.count)\r\n"
                        payload = body
                    case "/fresh.xml":
                        header = "HTTP/1.1 200 OK\r\nCache-Control: max-age=3600\r\n"
                        header += "Content-Length: \(body.count)\r\n"
                        payload = body
                    case "/moved":
                        header = "HTTP/1.1 301 Moved Permanently\r\n"
                        header += "Location: /feed.xml\r\nCache-Control: max-age=3600\r\n"
                        header += "Content-Length: 0\r\n"
                    default:
                        header = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n"
                    }
                    header += "Connection: close\r\n\r\n"
                    conn.send(content: Data(header.utf8) + payload,
                              completion: .contentProcessed { _ in conn.cancel() })
                }
            }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 5) == .success,
                  let bound = listener.port?.rawValue
            else { throw URLError(.cannotConnectToHost) }
            self.port = bound
        }

        deinit { listener.cancel() }

        func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
    }

    /// Captures the platform's metrics for one task.
    private final class Capture: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var _metrics: URLSessionTaskMetrics?
        private var _task: URLSessionTask?
        var metrics: URLSessionTaskMetrics? { lock.withLock { _metrics } }
        var task: URLSessionTask? { lock.withLock { _task } }

        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            lock.withLock { _metrics = metrics; _task = task }
        }
    }

    /// A session with its own memory cache, like `URLSession.updates`.
    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: config)
    }

    /// Fetch once and return the events the recorder would file for it.
    private static func fetch(
        _ url: URL, on session: URLSession, policy: URLRequest.CachePolicy
    ) async throws -> (shape: [URLSessionTaskMetrics.ResourceFetchType], events: [RequestEvent]) {
        var request = URLRequest(url: url)
        request.cachePolicy = policy
        let capture = Capture()
        _ = try await session.data(for: request, delegate: capture)
        // Delivered before `data(for:)` resumes (see `RequestMetricsRecorder`),
        // but not worth a flaky failure if that ever slips by a tick.
        for _ in 0..<100 where capture.metrics == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let metrics = try #require(capture.metrics)
        return (metrics.transactionMetrics.map(\.resourceFetchType),
                RequestMetricsRecorder.events(
                    from: metrics, task: capture.task, purpose: .versionCheck))
    }

    private static func store() -> (EventStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        return (EventStore(
            fileURL: url, retentionDays: 30, retentionBytes: 64 * 1024 * 1024,
            flushEventCount: 1, flushDelay: .milliseconds(10),
            pruneInterval: .seconds(3600), now: Date.init), url)
    }

    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix))
        }
    }

    @Test("A revalidation is one network request, not a cache hit plus a request")
    func revalidationIsOneNetworkRequest() async throws {
        let server = try Server()
        let session = Self.session()
        let policy = URLRequest.versionFeedCachePolicy

        let first = try await Self.fetch(server.url("/feed.xml"), on: session, policy: policy)
        let second = try await Self.fetch(server.url("/feed.xml"), on: session, policy: policy)

        // The fixture: the second fetch really was a lookup followed by a
        // conditional request that the server answered.
        try #require(second.shape == [.localCache, .networkLoad])
        try #require(server.hits == ["/feed.xml", "/feed.xml"])
        try #require(server.conditional == 1)

        #expect(first.events.count == 1)
        #expect(second.events.count == 1)
        let row = try #require(second.events.first)
        #expect(row.fetchType == .networkLoad)
        #expect(row.fromCache == false)
        #expect(row.status == 304)
        // The platform's transaction index, not a renumbering.
        #expect(row.hopIndex == 1)

        // And the lifetime ledger agrees: two fetches, one 304, no cache hit.
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        for event in first.events + second.events {
            await store.append(DuoEvent(date: Date(), payload: .request(event)))
        }
        await store.flush()
        let total = try #require(await store.totals().totals.first)
        #expect(total.requests == 2)
        #expect(total.cachedRequests == 0)
        #expect(total.notModified == 1)
        #expect(total.failures == 0)

        // The window's headline figures read the same rows.
        let summary = await store.requestSummary()
        #expect(summary.requests == 2)
        #expect(summary.cached == 0)
    }

    @Test("A fetch answered from cache without asking stays a cache hit")
    func genuineCacheHitIsStillRecorded() async throws {
        let server = try Server()
        let session = Self.session()

        _ = try await Self.fetch(server.url("/fresh.xml"), on: session, policy: .useProtocolCachePolicy)
        let second = try await Self.fetch(
            server.url("/fresh.xml"), on: session, policy: .useProtocolCachePolicy)

        try #require(second.shape == [.localCache])
        try #require(server.hits == ["/fresh.xml"])

        let row = try #require(second.events.first)
        #expect(second.events.count == 1)
        #expect(row.fromCache)
    }

    @Test("A redirect served from cache is kept; only its target's lookup is dropped")
    func cachedRedirectHopIsKept() async throws {
        let server = try Server()
        let session = Self.session()

        _ = try await Self.fetch(server.url("/moved"), on: session, policy: .useProtocolCachePolicy)
        let second = try await Self.fetch(
            server.url("/moved"), on: session, policy: .useProtocolCachePolicy)

        // The redirect never left the machine; its target was revalidated.
        try #require(second.shape == [.localCache, .localCache, .networkLoad])
        try #require(server.hits == ["/moved", "/feed.xml", "/feed.xml"])

        #expect(second.events.map(\.path) == ["/moved", "/feed.xml"])
        #expect(second.events.map(\.fetchType) == [.localCache, .networkLoad])
        #expect(second.events.map(\.status) == [301, 304])
        #expect(second.events.map(\.hopIndex) == [0, 2])
    }
}
