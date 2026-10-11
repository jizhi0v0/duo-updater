import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// `SparkleAppcastSource.probeEnclosure` against a loopback server, for the one
/// property the decision-half fixtures cannot show: that a server ignoring
/// `Range` does not get read. Every case names the mutation it catches.
@Suite(.serialized)
struct SparkleEnclosureProbeTests {

    /// Loopback HTTP/1.1 server. `/whole` ignores `Range` the way the servers
    /// that motivated the cap do: a 200 promising 40 MB, of which it sends
    /// 64 KiB and then holds the connection open — so a reader that does not
    /// stop on its own waits out the request timeout. `/ranged` honours the
    /// range with one byte. Anything else is a 404. The first request's text is
    /// kept, so its headers can be checked.
    private final class Server: @unchecked Sendable {
        /// What the handler writes to, apart from `self` so it can be captured
        /// before `init` finishes.
        private final class State: @unchecked Sendable {
            let lock = NSLock()
            var held: [NWConnection] = []
            var requests: [String] = []
        }
        private let listener: NWListener
        private let queue = DispatchQueue(label: "SparkleEnclosureProbeTests.Server")
        private let state = State()
        let port: UInt16

        init() throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let state = self.state
            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                    let text = String(decoding: data ?? Data(), as: UTF8.self)
                    state.lock.withLock { state.requests.append(text) }
                    let path = text.split(separator: " ", maxSplits: 2).dropFirst().first
                        .map(String.init) ?? "/"
                    switch path {
                    case "/whole":
                        state.lock.withLock { state.held.append(conn) }
                        let header = "HTTP/1.1 200 OK\r\nContent-Length: \(40 * 1024 * 1024)\r\n\r\n"
                        conn.send(content: Data(header.utf8) + Data(repeating: 0x61, count: 64 * 1024),
                                  completion: .contentProcessed { _ in })
                    case "/ranged":
                        let header = "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes 0-0/41943040\r\n"
                            + "Content-Length: 1\r\nConnection: close\r\n\r\na"
                        conn.send(content: Data(header.utf8),
                                  completion: .contentProcessed { _ in conn.cancel() })
                    default:
                        let header = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n"
                            + "Connection: close\r\n\r\nnot found"
                        conn.send(content: Data(header.utf8),
                                  completion: .contentProcessed { _ in conn.cancel() })
                    }
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
            state.lock.withLock { state.held.forEach { $0.cancel() } }
        }

        func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
        var firstRequest: String { state.lock.withLock { state.requests.first ?? "" } }
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

    private let source = SparkleAppcastSource(session: URLSession(configuration: .ephemeral))

    /// The server ignores the range and starts sending 40 MB. The probe reads
    /// one byte of it and answers.
    ///
    /// Mutation: drop the `break` at the cap. The loop then reads the 64 KiB
    /// sent, waits for the rest until the request times out, and answers with
    /// 65536 bytes read.
    @Test func aServerIgnoringTheRangeIsReadOneByteAndCountsAsAnswered() async throws {
        let server = try Server()
        let (store, file) = Self.store()
        defer { Self.remove(file) }
        let answer = await source.probeEnclosure(server.url("/whole"), store: store)
        #expect(answer == .answered(status: 200, bytesRead: 1))

        // The request a one-click install would make, plus the range.
        let request = server.firstRequest.lowercased()
        #expect(request.contains("range: bytes=0-0"))
        #expect(request.contains("user-agent: duoupdater/0.1"))
        #expect(request.contains("accept-encoding: identity"))
    }

    /// Mutation: read the body of a 4xx too. The 404 then reports the error
    /// page's bytes as read, which the probe has no use for.
    @Test func aRangedAnswerAndARefusalAreReportedAsTheyCame() async throws {
        let server = try Server()
        let (store, file) = Self.store()
        defer { Self.remove(file) }
        #expect(await source.probeEnclosure(server.url("/ranged"), store: store)
            == .answered(status: 206, bytesRead: 1))
        #expect(await source.probeEnclosure(server.url("/gone"), store: store)
            == .answered(status: 404, bytesRead: 0))
    }

    /// Mutation: report a transport failure as an answer. Nothing listens on
    /// loopback port 9 (discard), so the connection is refused.
    @Test func noServerIsNoAnswer() async throws {
        let (store, file) = Self.store()
        defer { Self.remove(file) }
        let answer = await source.probeEnclosure(
            URL(string: "http://127.0.0.1:9/whole")!, store: store)
        guard case .noAnswer = answer else {
            Issue.record("expected no answer, got \(answer)")
            return
        }
    }
}
