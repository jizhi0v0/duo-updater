import Testing
import Foundation
import Network
import SQLite3
@testable import DuoUpdaterCore

/// The event store: what it keeps, what it refuses to conflate, what it throws
/// away on purpose — and the two things that cannot be checked by reading code,
/// namely that `URLSessionTaskMetrics` arrive at all for the way this app
/// fetches, and that a query string never reaches disk.
@Suite(.serialized)
struct EventStoreTests {

    // MARK: - Fixtures

    private static func event(
        host: String = "example.com", path: String = "/feed",
        purpose: RequestPurpose = .versionCheck, client: RequestClient = .app,
        status: Int? = 200, fetchType: RequestEvent.FetchType = .networkLoad,
        received: Int64 = 1000, sent: Int64 = 200, at: Date = Date()
    ) -> DuoEvent {
        DuoEvent(date: at, client: client, payload: .request(RequestEvent(
            purpose: purpose, method: "GET", scheme: "https", host: host, port: nil,
            path: path, taskID: UUID(), hopIndex: 0, redirectCount: 0,
            status: status, fetchType: fetchType,
            requestHeaderBytes: 0, requestBodyBytes: sent,
            responseHeaderBytes: 0, responseBodyBytes: received,
            fetchStart: at, responseEnd: at)))
    }

    /// A store on a temp file. Flushes immediately (`flushEventCount: 1`) unless a
    /// case says otherwise, so nothing has to wait on the coalescing timer.
    private static func store(
        retentionDays: Int = 30, retentionBytes: Int64 = 64 * 1024 * 1024,
        flushEventCount: Int = 1, pruneInterval: Duration = .seconds(3600),
        now: @escaping @Sendable () -> Date = Date.init
    ) -> (EventStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        return (EventStore(
            fileURL: url, retentionDays: retentionDays, retentionBytes: retentionBytes,
            flushEventCount: flushEventCount, flushDelay: .milliseconds(10),
            pruneInterval: pruneInterval, now: now), url)
    }

    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix))
        }
    }

    // MARK: - Totals

    @Test("Totals split by client, purpose and host — never merged across them")
    func totalsKeyOnAllThreeDimensions() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        await store.append(Self.event(host: "github.com", purpose: .versionCheck))
        await store.append(Self.event(host: "github.com", purpose: .changelog))
        await store.append(Self.event(host: "github.com", purpose: .versionCheck, client: .cli))
        await store.append(Self.event(host: "api.github.com", purpose: .versionCheck))
        await store.flush()

        let totals = await store.totals().totals
        #expect(totals.count == 4)
        // The whole point of the split: one host answers several purposes, and
        // `duo`'s own sweep must stay separable from the app's background checks.
        #expect(totals.allSatisfy { $0.requests == 1 })
    }

    @Test("304, cache hit and transport failure are counted apart from plain requests")
    func cheapAndFailedRequestsAreDistinguished() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        await store.append(Self.event(status: 200, received: 5000))
        await store.append(Self.event(status: 304, received: 300))
        await store.append(Self.event(status: nil, fetchType: .localCache, received: 0, sent: 0))
        await store.append(Self.event(status: nil, received: 0, sent: 0))
        await store.flush()

        let total = await store.totals().totals.first
        #expect(total?.requests == 4)
        #expect(total?.notModified == 1)
        #expect(total?.cachedRequests == 1)
        // A cache hit has no status either, and counting it as a failure would
        // report a perfectly healthy revalidating session as half broken.
        #expect(total?.failures == 1)
        #expect(total?.networkRequests == 3)
        #expect(total?.bytesReceived == 5300)
    }

    @Test("Rollups collapse one dimension at a time and keep the byte total intact")
    func rollupsPreserveTheTotal() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        await store.append(Self.event(host: "a.example.com", purpose: .versionCheck, received: 100))
        await store.append(Self.event(host: "a.example.com", purpose: .changelog, received: 200))
        await store.append(Self.event(host: "b.example.com", purpose: .versionCheck, received: 400))
        // A `duo` row that must not leak into the app's numbers.
        await store.append(Self.event(host: "a.example.com", client: .cli, received: 8000))
        await store.flush()

        let snapshot = await store.totals()
        #expect(snapshot.byPurpose(client: .app).reduce(0) { $0 + $1.bytesReceived } == 700)
        #expect(snapshot.byHost(client: .app).reduce(0) { $0 + $1.bytesReceived } == 700)
        #expect(snapshot.byHost(client: .app).first?.host == "b.example.com")   // heaviest first
        #expect(snapshot.byPurpose(client: .app).map(\.purpose) == [.versionCheck, .changelog])
        #expect(snapshot.byPurpose(client: nil).reduce(0) { $0 + $1.bytesReceived } == 8700)
    }

    @Test("Totals and events survive a restart, and the totals outlive pruned events")
    func totalsOutliveTheEventsTheyCameFrom() async {
        let (store, url) = Self.store(retentionDays: 7)
        defer { Self.remove(url) }

        let old = Date().addingTimeInterval(-30 * 86_400)
        await store.append(Self.event(host: "cdn.example.com", received: 4242, at: old))
        await store.flush()

        // Reopening runs retention once, which is what removes the old event.
        let reopened = EventStore(fileURL: url, retentionDays: 7, flushEventCount: 1,
                                  flushDelay: .milliseconds(10))
        await reopened.append(Self.event(host: "cdn.example.com", received: 8))
        await reopened.flush()

        let totals = await reopened.totals().totals
        #expect(totals.count == 1)
        // Both transfers are still accounted for…
        #expect(totals.first?.bytesReceived == 4250)
        #expect(totals.first?.requests == 2)
        // …but only the recent one is still tellable. That gap is the design, not
        // a discrepancy: totals are kept forever, events are not.
        let events = await reopened.events(EventQuery(limit: 100))
        #expect(events.count == 1)
        #expect(events.first?.request?.bytesReceived == 8)
    }

    // MARK: - Round trip

    @Test("A fully-populated request event round-trips through the store unchanged")
    func requestEventRoundTripsWholeValue() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        // Inside the retention window, and carrying a sub-second fraction that is
        // not a round number of milliseconds: that fraction is what pins the
        // timestamp encoding. A whole-second encoding collapses every phase
        // interval to zero, and a millisecond one loses most of them.
        // `storageResolution` is the microsecond truncation the store stores, so
        // this compares like with like rather than asserting a precision nothing
        // claims to keep.
        let base = Date().addingTimeInterval(-60).addingTimeInterval(0.250_837)
        // Each offset normalised too: adding a Double to a Double lands off the
        // microsecond grid, so comparing against an un-normalised sum would be
        // testing floating-point addition rather than the store.
        func t(_ offset: TimeInterval) -> Date {
            DuoEvent.storageResolution(base.addingTimeInterval(offset))
        }
        // Every optional populated, every value distinct: compared as a whole
        // value rather than field by field, so a field dropped from the type (or
        // from its CodingKeys) fails here instead of going unnoticed.
        let request = RequestEvent(
            purpose: .install, method: "POST", scheme: "https", host: "dl.example.com",
            port: 8443, path: "/a/b.dmg", taskID: UUID(), hopIndex: 2, redirectCount: 3,
            status: 206, errorDomain: NSURLErrorDomain, errorCode: -1001,
            fetchType: .serverPush, reusedConnection: true, proxyConnection: true,
            cellular: true, expensive: true, constrained: true, multipath: true,
            domainResolution: .https, networkProtocol: "h2",
            localAddress: "192.0.2.5", localPort: 51234,
            remoteAddress: "198.51.100.9", remotePort: 8443,
            tlsVersion: 0x0304, tlsCipherSuite: 0x1301,
            requestHeaderBytes: 11, requestBodyBytes: 12,
            requestBodyBytesBeforeEncoding: 13, responseHeaderBytes: 14,
            responseBodyBytes: 15, responseBodyBytesAfterDecoding: 16,
            byteSource: .declared,
            fetchStart: t(0), domainLookupStart: t(0.000_001),
            domainLookupEnd: t(0.000_042), connectStart: t(0.001),
            secureConnectionStart: t(0.002), secureConnectionEnd: t(0.003),
            connectEnd: t(0.004), requestStart: t(0.005),
            requestEnd: t(0.006), responseStart: t(0.007),
            responseEnd: t(0.008))

        await store.append(DuoEvent(date: t(0), client: .app, payload: .request(request)))
        await store.flush()

        let read = await store.events(EventQuery(limit: 10)).first
        #expect(read?.request == request)
        #expect(read?.client == .app)
        #expect(request.tlsVersionName == "TLSv1.3")
    }

    @Test("An unknown kind survives read and write byte for byte")
    func unknownKindIsPassedThrough() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        // What a newer app's event looks like to this build.
        let json = #"{"future":true,"note":"hello","nested":{"a":[1,2,3]}}"#
        await store.append(DuoEvent(payload: .unknown(kind: "install", json: json)))
        await store.flush()

        let rows = await store.rawRows(EventQuery(limit: 10))
        #expect(rows.first?.kind == "install")
        // Byte for byte. Laundering it through a shape this build understands is
        // exactly what the passthrough exists to prevent.
        #expect(rows.first?.payloadJSON == json)

        let decoded = await store.events(EventQuery(limit: 10)).first
        #expect(decoded?.payload == .unknown(kind: "install", json: json))
    }

    @Test("A known kind whose payload does not parse degrades to unknown, not to nothing")
    func unparseablePayloadOfAKnownKindIsKept() {
        // What a row written by a newer app looks like to an older `duo`: the kind
        // is familiar, the payload is not. Dropping it would turn "I cannot read
        // this" into "this never happened".
        let row = EventRow(
            id: UUID(), date: Date(), client: .app, kind: "request",
            payloadJSON: #"{"purpose":"versionCheck"}"#)
        let event = DuoEvent(row: row)
        #expect(event != nil)
        #expect(event?.request == nil)
        #expect(event?.kind == "request")
        if case .unknown(_, let json)? = event?.payload {
            #expect(json == row.payloadJSON)
        } else {
            Issue.record("expected the row to be kept as an unknown payload")
        }
    }

    @Test("A raw payload that is not a JSON object is refused rather than stored")
    func nonObjectRawPayloadIsRefused() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        // Only a hand-built value can get here — a decoded one came from a real
        // row — which is why it is refused rather than trusted.
        await store.append(DuoEvent(payload: .unknown(kind: "bogus", json: "not json")))
        await store.flush()
        #expect(await store.rejectedCount == 1)
        #expect(await store.events(EventQuery(limit: 10)).isEmpty)
    }

    // MARK: - Retention

    @Test("Age retention drops events past the window and keeps the ones inside it")
    func ageRetentionDropsOldEvents() async {
        let (store, url) = Self.store(retentionDays: 7)
        defer { Self.remove(url) }

        let now = Date()
        await store.append(Self.event(host: "old.example.com", at: now.addingTimeInterval(-8 * 86_400)))
        await store.append(Self.event(host: "edge.example.com", at: now.addingTimeInterval(-6 * 86_400)))
        await store.append(Self.event(host: "new.example.com", at: now))
        await store.flush()

        let hosts = await store.events(EventQuery(limit: 100)).compactMap(\.request?.host)
        #expect(Set(hosts) == ["edge.example.com", "new.example.com"])
    }

    @Test("The byte budget prunes even when every event is inside the age window")
    func byteRetentionPrunesFreshEvents() async {
        // A tiny ceiling and no age pressure at all: without a size pass this
        // grows forever, and at realistic event sizes the age budget alone does
        // not bound the footprint of a machine that checks hourly.
        let (store, url) = Self.store(
            retentionDays: 3650, retentionBytes: 512 * 1024, flushEventCount: 500,
            pruneInterval: .zero)
        defer { Self.remove(url) }

        for index in 0..<4000 {
            await store.append(Self.event(host: "h\(index % 50).example.com", path: "/\(index)"))
        }
        await store.flush()
        // Prune runs once per process after a commit, so give it the second batch.
        await store.append(Self.event(host: "last.example.com"))
        await store.flush()

        let bytes = await store.databaseBytes()
        let count = await store.coverage().count
        #expect(count < 4000, "the size pass should have given up the oldest events")
        #expect(count >= EventStore.retentionFloor,
                "it should stop at the floor rather than emptying the store")
        // Totals are never pruned and must still account for every one of them.
        let requests = await store.totals().totals.reduce(0) { $0 + $1.requests }
        #expect(requests == 4001)
        #expect(bytes > 0)
    }

    @Test("A budget too small to meet leaves the newest events rather than emptying the store")
    func retentionNeverEmptiesTheStore() async {
        // One byte is unmeetable — an empty SQLite file with this schema is
        // already tens of kilobytes — so without a floor the size pass deletes
        // every row it can and the store then reports that nothing ever
        // happened. Keeping the newest events is strictly more useful than
        // keeping none, and "nothing recorded" is the one answer a log must not
        // give while it is still being written to.
        let (store, url) = Self.store(
            retentionDays: 3650, retentionBytes: 1, flushEventCount: 500,
            pruneInterval: .zero)
        defer { Self.remove(url) }

        for index in 0..<1000 { await store.append(Self.event(path: "/\(index)")) }
        await store.flush()

        #expect(await store.coverage().count == EventStore.retentionFloor)
        // And what survived is the newest end of the history, not an arbitrary slice.
        let newest = await store.events(EventQuery(limit: 1)).first?.request?.path
        #expect(newest == "/999")
    }

    @Test("Pruning never runs on the append path")
    func pruningStaysOffTheHotPath() async {
        let (store, url) = Self.store(flushEventCount: 1)
        defer { Self.remove(url) }

        for index in 0..<200 { await store.append(Self.event(path: "/\(index)")) }
        await store.flush()
        // Once per process, after a commit — not per event, and not per batch.
        #expect(await store.pruneRunCount == 1)
    }

    @Test("The vacuum mode is INCREMENTAL from the first table onwards")
    func vacuumModeIsSetBeforeTheSchema() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await store.append(Self.event())
        await store.flush()
        // `auto_vacuum` can only be set on an empty database. Get this wrong and
        // retention stops the file growing but never shrinks it, and the fix
        // afterwards is a full VACUUM.
        #expect(await store.schemaProblems().isEmpty)
    }

    @Test("Reset clears the events and the totals together")
    func resetClearsBothHalves() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        await store.append(Self.event())
        await store.flush()
        await store.reset()

        #expect(await store.totals().totals.isEmpty)
        #expect(await store.events(EventQuery(limit: 10)).isEmpty)
    }

    /// Emptying the store has to give the space back to the filesystem, not just
    /// to SQLite's free list.
    ///
    /// Found by running `duo requests reset` for real: it cleared every row, and
    /// the file stayed at 14 897 152 bytes with a `page_count` of 126 — 516 KB of
    /// actual content. `incremental_vacuum` had done its job and the truncation
    /// was sitting in the write-ahead log, because the checkpoint ran before it
    /// instead of after. One checkpoint afterwards brought the file to exactly
    /// 516 096 bytes.
    @Test("Reset returns the space to the filesystem, not just to the free list")
    func resetShrinksTheFileOnDisk() async {
        let (store, url) = Self.store(flushEventCount: 5000)
        defer { Self.remove(url) }

        for index in 0..<3000 { await store.append(Self.event(path: "/\(index)")) }
        await store.flush()
        let grown = await store.databaseBytes()
        #expect(grown > 1_000_000, "the store did not grow enough for this to prove anything")

        await store.reset()

        #expect(await store.coverage().count == 0)
        let shrunk = await store.databaseBytes()
        #expect(shrunk < grown / 4,
                "emptied the store but kept \(shrunk) of \(grown) bytes on disk")
    }

    // MARK: - Querying

    @Test("Filters narrow in SQL, and the tail is the newest matches in order")
    func queriesFilterAndTail() async {
        let (store, url) = Self.store(flushEventCount: 500)
        defer { Self.remove(url) }

        let base = Date().addingTimeInterval(-3600)
        for index in 0..<100 {
            await store.append(Self.event(
                host: index.isMultiple(of: 2) ? "even.example.com" : "odd.example.com",
                path: "/\(index)",
                purpose: index < 50 ? .versionCheck : .changelog,
                at: base.addingTimeInterval(Double(index))))
        }
        await store.flush()

        let tail = await store.events(EventQuery(limit: 5))
        #expect(tail.count == 5)
        #expect(tail.map { $0.request?.path } == ["/95", "/96", "/97", "/98", "/99"])

        let evens = await store.events(EventQuery(host: "even.example.com", limit: 1000))
        #expect(evens.count == 50)

        let changelog = await store.events(EventQuery(purpose: .changelog, limit: 1000))
        #expect(changelog.count == 50)

        let recent = await store.events(
            EventQuery(since: base.addingTimeInterval(90), limit: 1000))
        #expect(recent.count == 10)
    }

    @Test("Events sharing a timestamp come back in the order they were written")
    func tiesBreakOnInsertionOrder() async {
        let (store, url) = Self.store(flushEventCount: 10)
        defer { Self.remove(url) }

        // Two writers on one machine, or one fan-out with a coarse clock, can
        // produce the same instant twice. Ordering then falls to the tiebreaker,
        // and the id is a random UUID — so without an insertion-order tiebreak
        // "what happened last" would come back differently between runs.
        let instant = Date()
        for index in 0..<6 {
            await store.append(Self.event(path: "/\(index)", at: instant))
        }
        await store.flush()

        let paths = await store.events(EventQuery(limit: 10)).compactMap(\.request?.path)
        #expect(paths == ["/0", "/1", "/2", "/3", "/4", "/5"])
    }

    // MARK: - The halves that have to be measured

    /// Loopback HTTP/1.1 server. `redirectFirst` answers the first request with a
    /// 302 to `localhost` (a different host string, same port), so a redirect can
    /// be exercised without a second listener.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "EventStoreTests.Server")
        let port: UInt16
        let body = Data(repeating: 0x61, count: 3000)

        init(redirectFirst: Bool) throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let body = self.body
            final class State: @unchecked Sendable {
                let lock = NSLock()
                var didRedirect = false
            }
            let state = State()
            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    let redirect = state.lock.withLock { () -> Bool in
                        guard redirectFirst, !state.didRedirect else { return false }
                        state.didRedirect = true
                        return true
                    }
                    let listenPort = listener.port?.rawValue ?? 0

                    var header: String
                    var payload = Data()
                    if redirect {
                        header = "HTTP/1.1 302 Found\r\n"
                        header += "Location: http://localhost:\(listenPort)/final\r\n"
                        header += "Content-Length: 0\r\n"
                    } else {
                        header = "HTTP/1.1 200 OK\r\n"
                        header += "Content-Type: text/plain\r\n"
                        header += "Content-Length: \(body.count)\r\n"
                        payload = body
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
    }

    /// The load-bearing measurement, and the reason this test is worth its weight.
    ///
    /// Everything on `URLSession.updates` is fetched with `data(for:)`, and
    /// `NSURLSession.h` warns that a completion-handler task does not get "the
    /// delegate methods for response and data delivery" — which is exactly why
    /// `willCacheResponse` is dead on that session (see
    /// `CredentialCacheDelegateBypassTests`). The metrics callback is declared on
    /// `NSURLSessionTaskDelegate` instead and is not covered by that sentence, but
    /// nothing about the tree would *show* it if that ever changed: the store
    /// would simply record nothing, every total would read zero, and the summary
    /// would say the updater used no network at all. This is the test that fails
    /// instead.
    @Test("Metrics arrive for a completion-handler fetch, with timings, address and wire bytes")
    func metricsAreDeliveredForDataForRequest() async throws {
        let server = try Server(redirectFirst: false)
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/feed.xml")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        _ = try await session.countedData(for: request, purpose: .versionCheck, store: store)

        let event = try #require(await Self.settle(store).first?.request)
        #expect(event.host == "127.0.0.1")
        #expect(event.path == "/feed.xml")
        #expect(event.status == 200)
        #expect(event.purpose == .versionCheck)
        #expect(event.fromCache == false)
        #expect(event.remoteAddress != nil)
        #expect(event.hopIndex == 0)
        // The timings are the half a counter could never have kept.
        #expect(event.fetchStart != nil)
        #expect(event.responseEnd != nil)
        #expect((event.duration ?? -1) >= 0)
        // Strictly greater than the body: response headers are counted too, which
        // is what makes a sweep of 304s show up as a real cost instead of zero.
        #expect(event.bytesReceived > Int64(server.body.count))
        #expect(event.bytesSent > 0)
    }

    /// A per-task delegate must not displace the session delegate.
    ///
    /// `URLSession.updates` installs `CrossHostCredentialStripper` as its session
    /// delegate to drop `Authorization` on a cross-host redirect — a security
    /// boundary, and one that vanishes silently if attaching a metrics delegate to
    /// each task were to take the session delegate out of the redirect path.
    /// Nothing would fail; the header would just start travelling.
    @Test("Attaching a per-task recorder leaves the session delegate handling redirects")
    func perTaskDelegateDoesNotDisplaceTheSessionDelegate() async throws {
        final class RedirectSpy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
            private let seen = NSLock()
            private var _count = 0
            var count: Int { seen.withLock { _count } }
            func urlSession(
                _ session: URLSession, task: URLSessionTask,
                willPerformHTTPRedirection response: HTTPURLResponse,
                newRequest request: URLRequest,
                completionHandler: @escaping (URLRequest?) -> Void
            ) {
                seen.withLock { _count += 1 }
                completionHandler(request)
            }
        }

        let server = try Server(redirectFirst: true)
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        let spy = RedirectSpy()
        let session = URLSession(configuration: .ephemeral, delegate: spy, delegateQueue: nil)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/start")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        _ = try await session.countedData(for: request, purpose: .versionCheck, store: store)

        #expect(spy.count == 1)

        // And both hops are booked, because both hosts really were contacted —
        // sharing one task id, so the pair can be read back as one fetch.
        let events = await Self.settle(store, atLeast: 2).compactMap(\.request)
        #expect(events.count == 2)
        #expect(Set(events.map(\.host)) == ["127.0.0.1", "localhost"])
        #expect(events.map(\.hopIndex) == [0, 1])
        #expect(Set(events.map(\.taskID)).count == 1)
        #expect(events.first?.status == 302)
        #expect(events.last?.status == 200)
    }

    /// The only guard on the privacy boundary, and it asserts against the bytes on
    /// disk rather than the decoded value — the question is what a backup contains,
    /// not what this type says it contains.
    ///
    /// Nothing else in the tree fetches a URL with a query, so without this the
    /// whole write path is unexercised on the one input that matters: a vendor
    /// activation key rides in a query string (see `CredentialBearingURL`).
    @Test("A query string never reaches disk")
    func queryStringsAreNotRecorded() async throws {
        let server = try Server(redirectFirst: false)
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(server.port)/feed.xml?license=SUPERSECRET")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        _ = try await session.countedData(for: request, purpose: .versionCheck, store: store)

        let event = try #require(await Self.settle(store).first?.request)
        #expect(event.path == "/feed.xml")
        #expect(event.url == "http://127.0.0.1:\(server.port)/feed.xml")

        let onDisk = try #require(try? Data(contentsOf: url))
        let wal = (try? Data(contentsOf: url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + "-wal"))) ?? Data()
        for blob in [onDisk, wal] {
            #expect(blob.range(of: Data("SUPERSECRET".utf8)) == nil,
                    "a query string reached the database file")
        }
    }

    /// The fix for events lost at process exit, pinned at the point that made
    /// them recoverable.
    ///
    /// `duo` reads `EventStore.hasRecorded` the instant its command returns and
    /// exits. When the delegate callback filed events with `Task { await … }`,
    /// that flag could still be false — the Task created, not yet run — so the
    /// flush was skipped and the request was never recorded. Nothing failed and
    /// nothing logged; the count was simply low.
    @Test("Events are recorded before the fetch that produced them returns")
    func eventsAreStagedBeforeTheFetchResumes() async throws {
        let server = try Server(redirectFirst: false)
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/feed.xml")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        _ = try await session.countedData(for: request, purpose: .versionCheck, store: store)

        // No polling and no sleeping: this is exactly what `duo` gets to see at
        // exit, so anything asynchronous here is the bug.
        await store.flush()
        #expect(await store.coverage().count == 1)
        #expect(EventStore.hasRecorded)
    }

    /// A commit that cannot open its transaction must keep the events, not drop
    /// them — and must not fall back to writing them one autocommitted statement
    /// at a time, which is how an event lands without its rollup.
    @Test("A busy database defers the batch instead of losing it")
    func aBusyDatabaseDefersTheBatch() async throws {
        let (store, url) = Self.store(flushEventCount: 1)
        defer { Self.remove(url) }

        // The first append creates the schema, so the blocker below contends with
        // a real database rather than a missing one.
        await store.append(Self.event(host: "first.example.com"))
        await store.flush()

        // A second connection holding the write lock, exactly as a concurrent
        // `duo verify` sweep would.
        var blocker: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &blocker, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(blocker) }
        sqlite3_exec(blocker, "PRAGMA busy_timeout=0;", nil, nil, nil)
        #expect(sqlite3_exec(blocker, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK)

        let contended = EventStore(fileURL: url, flushEventCount: 1,
                                   flushDelay: .milliseconds(10), busyTimeoutMilliseconds: 50)
        await contended.append(Self.event(host: "deferred.example.com"))
        await contended.flush()
        // Nothing landed while the lock was held…
        #expect(await contended.coverage().count == 1)

        sqlite3_exec(blocker, "ROLLBACK;", nil, nil, nil)

        // …and the event was still there to be written once it was released.
        await contended.flush()
        let hosts = await contended.events(EventQuery(limit: 10)).compactMap(\.request?.host)
        #expect(hosts.contains("deferred.example.com"),
                "the batch was dropped rather than deferred")
    }

    /// The test suite must not write into the developer's own store.
    ///
    /// It did: after one `make test` the real database held 1643 `cli` events,
    /// 252 of them to `127.0.0.1` and 48 to `example.com` — a host nothing ever
    /// contacted — and those rows are in the never-pruned totals for good.
    @Test("A test process never writes to the real event store")
    func testProcessesGetTheirOwnStore() {
        let previous = ProcessInfo.processInfo.environment["DUO_STATE_DIR"]
        unsetenv("DUO_STATE_DIR")
        defer { if let previous { setenv("DUO_STATE_DIR", previous, 1) } }

        #expect(EventStore.isTestProcess, "this suite is running in one")
        let path = EventStore.defaultFileURL().path
        #expect(!path.contains("Application Support"),
                "the suite would write into the user's own store at \(path)")
        // An explicit override still wins — the escape hatch every other store
        // honours must not be shadowed by the test-process guard.
        setenv("DUO_STATE_DIR", "/tmp/duo-state-test", 1)
        #expect(EventStore.defaultFileURL().path
                == "/tmp/duo-state-test/com.duoupdater.app/events.sqlite")
    }

    /// The retention ceiling and the reported size must mean the on-disk
    /// footprint, which in WAL mode is three files.
    ///
    /// Measured on the real store while writing this: 2 686 976 bytes of database
    /// against 951 752 bytes of `-wal`, i.e. the main file alone is 36% low. A
    /// budget enforced against the smaller half is not the budget the doc comment
    /// claims, and `duo events --status` would print a size `du` contradicts.
    @Test("The reported size counts the write-ahead log, not just the database")
    func sizeIncludesTheWriteAheadLog() async {
        let (store, url) = Self.store(flushEventCount: 5000, pruneInterval: .seconds(3600))
        defer { Self.remove(url) }
        // Two rounds. The first commit is also this process's one prune, which
        // checkpoints and empties the log; the pages that matter are the ones
        // written after it, while no further prune is due.
        await store.append(Self.event(path: "/warmup"))
        await store.flush()
        for index in 0..<2000 { await store.append(Self.event(path: "/\(index)")) }
        await store.flush()

        func bytes(_ suffix: String) -> Int64 {
            let path = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + suffix).path
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        let wal = bytes("-wal")
        #expect(wal > 0, "no write-ahead log to speak of; the case proves nothing")
        #expect(await store.databaseBytes() >= bytes("") + wal)
    }

    /// Metrics are delivered on the session's delegate queue and filed from a
    /// detached task, so a read taken the instant `countedData` returns can
    /// legitimately be empty. Polls rather than sleeping a fixed amount, so a slow
    /// machine does not turn into a flake.
    private static func settle(
        _ store: EventStore, atLeast expected: Int = 1
    ) async -> [DuoEvent] {
        for _ in 0..<100 {
            if await store.appendedCount >= expected { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        await store.flush()
        return await store.events(EventQuery(limit: 100))
    }
}
