import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// Stopping "Update All" has to stop the bytes.
///
/// A `URLSessionTask` is not part of the Swift task tree, so cancelling the task
/// that awaits a download used to leave the transfer running: a 2 GB package
/// stopped at 5% carried on to 100% — up to five times over, since the retry
/// backoff was a `try?` that swallowed the cancellation too — and only the
/// coordinator's check before the apply step noticed anything.
///
/// Driven against a loopback server that answers with headers and then simply
/// stops sending, which is what "a transfer in flight" looks like from the client
/// side, with no external network and no dependence on how fast this machine is.
@Suite struct DownloaderCancellationTests {

    /// Sends a response head declaring a large body, then a few bytes, then holds
    /// the connection open forever. Every request head is recorded so a test can
    /// tell "the transfer was stopped" from "the transfer was re-issued".
    ///
    /// All callbacks run on a dedicated serial queue rather than the shared global
    /// pool, for the reason `DownloaderTrafficTests` documents: under a saturated
    /// run the global pool's threads are all blocked on other tests' I/O and this
    /// server would be starved.
    private final class StallingHTTPServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "StallingHTTPServer")
        private let state = State()
        let port: UInt16

        /// Request heads, and the live connections — held so the framework does not
        /// tear down a connection we are deliberately never finishing.
        final class State: @unchecked Sendable {
            private let lock = NSLock()
            private var _requests: [String] = []
            private var _connections: [NWConnection] = []
            var requestCount: Int { lock.withLock { _requests.count } }
            func record(_ request: String) { lock.withLock { _requests.append(request) } }
            func hold(_ conn: NWConnection) { lock.withLock { _connections.append(conn) } }
            func closeAll() {
                let conns = lock.withLock { _connections }
                for conn in conns { conn.cancel() }
            }
        }

        init(declaredTotal: Int, prefix: Data) throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let state = self.state

            listener.newConnectionHandler = { conn in
                state.hold(conn)
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                    state.record(String(data: data ?? Data(), encoding: .utf8) ?? "")
                    let head = [
                        "HTTP/1.1 200 OK",
                        "Content-Length: \(declaredTotal)",
                        "Accept-Ranges: bytes",
                        "Connection: keep-alive",
                    ].joined(separator: "\r\n") + "\r\n\r\n"
                    var response = Data(head.utf8)
                    response.append(prefix)
                    // No completion work: the rest of the body never arrives and the
                    // connection is never closed, so the client stays mid-transfer
                    // until something cancels it.
                    conn.send(content: response, completion: .contentProcessed { _ in })
                }
            }
            listener.start(queue: queue)
            var resolved: UInt16?
            for _ in 0..<500 {
                if let p = listener.port?.rawValue, p != 0 { resolved = p; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let p = resolved else { throw URLError(.cannotConnectToHost) }
            self.port = p
        }

        var requestCount: Int { state.requestCount }
        func stop() {
            state.closeAll()
            listener.cancel()
        }
    }

    private enum Settled: Sendable, Equatable {
        case cancelled
        case otherError(String)
        case completed
        case neverStopped
    }

    /// How long the download is given to notice the cancellation. Not a measurement
    /// of how fast it reacts — it reacts immediately — but a bound that separates
    /// "stopped" from "ran on", which otherwise means waiting out URLSession's
    /// 60 s timeout five times. Generous enough that a loaded 3-core runner cannot
    /// turn a working stop into a red test (see the repo's note on wall-clock
    /// bounds in a parallel suite).
    private static let stopBudget: Duration = .seconds(20)

    @Test func cancellingTheTaskStopsAnInFlightDownload() async throws {
        let server = try StallingHTTPServer(declaredTotal: 50_000_000, prefix: Data(count: 4096))
        defer { server.stop() }
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        let download = Task { try await downloader.download(url) }

        // Wait for the request to actually reach the server: cancelling before the
        // transfer is in flight would test the easy half.
        for _ in 0..<1000 {
            if server.requestCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.requestCount == 1, "the download never reached the server")

        download.cancel()

        let settled = await withTaskGroup(of: Settled.self) { group in
            group.addTask {
                do {
                    _ = try await download.value
                    return .completed
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return .otherError(String(describing: error))
                }
            }
            group.addTask {
                try? await Task.sleep(for: Self.stopBudget)
                return .neverStopped
            }
            let first = await group.next() ?? .neverStopped
            group.cancelAll()
            return first
        }

        // `CancellationError`, not URLSession's `-999`: every caller up the chain
        // (`InstallCoordinator`, then `installAll`) reads a stop as a stop rather
        // than as a download failure with a red error on the row.
        #expect(settled == .cancelled)
        // And it stopped rather than resuming: a retry would have re-issued the GET
        // with a `Range` header.
        #expect(server.requestCount == 1)
    }
}
