import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// Every request `countedBytes` starts is recorded once, however the caller
/// leaves the stream.
///
/// A bytes task reports its metrics only when it completes, and one that is
/// cancelled — or released — before anything asked its iterator for a byte
/// never completes: it sits in `.canceling` and the request never reaches the
/// ledger. The early exits in `VendorProbeSource`'s range reads and
/// `UvRelease.readHead` are exactly those shapes. These drive the real loading
/// system against a loopback server and count what lands in a scratch store.
@Suite(.serialized)
struct CountedBytesRecordingTests {

    /// Loopback HTTP/1.1 server: `/big` is a 200 with a body far larger than any
    /// case here reads; `/stall` promises that body, sends 64 KiB of it and then
    /// holds the connection open, so the task cannot finish on its own; `/moved`
    /// is a 302 to another host; anything else is a 404 with a short body.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "CountedBytesRecordingTests.Server")
        /// `/stall` connections, held open until the server goes.
        private final class Held: @unchecked Sendable {
            let lock = NSLock()
            var connections: [NWConnection] = []
        }
        private let held = Held()
        let port: UInt16
        static let bigLength = 4 * 1024 * 1024

        init() throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let held = self.held
            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                    let text = String(decoding: data ?? Data(), as: UTF8.self)
                    let path = text.split(separator: " ", maxSplits: 2).dropFirst().first
                        .map(String.init) ?? "/"
                    var header: String
                    let payload: Data
                    if path == "/stall" {
                        held.lock.withLock { held.connections.append(conn) }
                        header = "HTTP/1.1 200 OK\r\nContent-Length: \(Self.bigLength)\r\n\r\n"
                        conn.send(content: Data(header.utf8) + Data(repeating: 0x61, count: 64 * 1024),
                                  completion: .contentProcessed { _ in })
                        return
                    } else if path == "/big" {
                        payload = Data(repeating: 0x61, count: Self.bigLength)
                        header = "HTTP/1.1 200 OK\r\n"
                    } else if path == "/moved" {
                        payload = Data(repeating: 0x63, count: 20)
                        header = "HTTP/1.1 302 Found\r\nLocation: https://elsewhere.invalid/\r\n"
                    } else {
                        payload = Data(repeating: 0x62, count: 20)
                        header = "HTTP/1.1 404 Not Found\r\n"
                    }
                    header += "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
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

        deinit {
            listener.cancel()
            held.lock.withLock { held.connections.forEach { $0.cancel() } }
        }

        func request(_ path: String) -> URLRequest {
            URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        }
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

    /// The request rows in `store` once `expected` have arrived, or after two
    /// seconds — then another beat, so a late duplicate would be counted too.
    private static func rows(in store: EventStore, expecting expected: Int) async throws -> [RequestEvent] {
        var rows: [RequestEvent] = []
        for _ in 0..<200 {
            await store.flush()
            rows = await store.events().compactMap(\.request)
            if rows.count >= expected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(300))
        await store.flush()
        return await store.events().compactMap(\.request)
    }

    private static let session = URLSession(configuration: .ephemeral)

    /// Refuses every redirect, as `URLSession.updates` refuses one off a
    /// confined request's site: the caller gets the redirect response itself.
    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? { nil }
    }
    private static let refusingSession = URLSession(
        configuration: .ephemeral, delegate: RefuseRedirects(), delegateQueue: nil)

    @Test("Cancelled before reading a byte: recorded once, as cancelled")
    func cancelledBeforeReading() async throws {
        let server = try Server()
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        for path in ["/big", "/missing"] {
            let (stream, _) = try await Self.session.countedBytes(
                for: server.request(path), purpose: .versionCheck, store: store)
            stream.task.cancel()
        }

        let rows = try await Self.rows(in: store, expecting: 2)
        #expect(rows.map(\.path).sorted() == ["/big", "/missing"])
        #expect(rows.allSatisfy { $0.errorCode == NSURLErrorCancelled })
    }

    @Test("Never read and never cancelled: recorded once")
    func abandoned() async throws {
        let server = try Server()
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        for path in ["/big", "/missing"] {
            _ = try await Self.session.countedBytes(
                for: server.request(path), purpose: .versionCheck, store: store)
        }

        let rows = try await Self.rows(in: store, expecting: 2)
        #expect(rows.map(\.path).sorted() == ["/big", "/missing"])
        let missing = try #require(rows.first { $0.path == "/missing" })
        #expect(missing.status == 404)
    }

    @Test("A refused redirect left unread: recorded once")
    func refusedRedirectUnread() async throws {
        let server = try Server()
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        do {
            let (_, response) = try await Self.refusingSession.countedBytes(
                for: server.request("/moved"), purpose: .versionCheck, store: store)
            try #require((response as? HTTPURLResponse)?.statusCode == 302)
        }

        let rows = try await Self.rows(in: store, expecting: 1)
        #expect(rows.count == 1)
        #expect(rows.first?.status == 302)
        #expect(rows.first?.path == "/moved")
    }

    @Test("Broken out of after a few bytes: recorded once, with what was received")
    func brokenOutOf() async throws {
        let server = try Server()
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        let (stream, _) = try await Self.session.countedBytes(
            for: server.request("/big"), purpose: .versionCheck, store: store)
        var read = 0
        for try await _ in stream {
            read += 1
            if read == 16 { break }
        }

        let rows = try await Self.rows(in: store, expecting: 1)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.status == 200)
        // At least what the loop consumed came off the wire. No upper bound: on
        // loopback under a busy parallel suite the whole body can land before
        // the cancel does.
        #expect(row.responseBodyBytes >= 16)
    }

    @Test("Cancelled mid-read and left by a throw: recorded once")
    func cancelledMidRead() async throws {
        struct Bail: Error {}
        let server = try Server()
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        do {
            let (stream, _) = try await Self.session.countedBytes(
                for: server.request("/big"), purpose: .versionCheck, store: store)
            var read = 0
            for try await _ in stream {
                read += 1
                if read == 16 { stream.task.cancel(); throw Bail() }
            }
        } catch is Bail {}

        let rows = try await Self.rows(in: store, expecting: 1)
        #expect(rows.count == 1)
        #expect(rows.first?.errorCode == NSURLErrorCancelled)
    }

    @Test("A read that throws: recorded once, with nothing left to settle")
    func readThrows() async throws {
        let server = try Server()
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        var thrown: Error?
        do {
            let (stream, _) = try await Self.session.countedBytes(
                // `/stall`, not `/big`: a body that can land in full before the
                // cancel would end the loop normally and never throw.
                for: server.request("/stall"), purpose: .versionCheck, store: store)
            var read = 0
            do {
                for try await _ in stream {
                    read += 1
                    if read == 16 { stream.task.cancel() }
                }
            } catch { thrown = error }
            // The iterator saw the failure, so the task has finished on its own —
            // the case `settle()` skips.
            #expect(stream.task.state == .completed)
        }

        #expect((thrown as? URLError)?.code == .cancelled)
        let rows = try await Self.rows(in: store, expecting: 1)
        #expect(rows.count == 1)
        #expect(rows.first?.errorCode == NSURLErrorCancelled)
    }

    @Test("Read to the end: recorded once, not again when the stream is released")
    func drained() async throws {
        let server = try Server()
        let (store, url) = Self.store()
        defer { Self.remove(url) }

        var read = 0
        do {
            let (stream, _) = try await Self.session.countedBytes(
                for: server.request("/missing"), purpose: .versionCheck, store: store)
            for try await _ in stream { read += 1 }
        }

        let rows = try await Self.rows(in: store, expecting: 1)
        #expect(read == 20)
        #expect(rows.count == 1)
        #expect(rows.first?.status == 404)
        #expect(rows.first?.responseBodyBytes == 20)
        #expect(rows.first?.errorCode == nil)
    }
}
