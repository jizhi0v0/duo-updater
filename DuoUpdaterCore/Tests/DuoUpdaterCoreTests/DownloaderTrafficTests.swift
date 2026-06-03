import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// `Downloader.bytesDownloaded` is the to-the-byte source of every traffic stat,
/// so it must equal the exact number of bytes received. These tests pin that
/// against a loopback HTTP server (the streaming `didWriteData` path) and a
/// `file://` source (the file-size backstop), with no external network.
///
/// Serialized: the loopback-server test is sensitive to scheduling latency, and
/// running it alongside the rest of the (heavily network-bound, parallel) suite
/// once let the server starve and the download time out. Serializing this small
/// suite keeps its own two tests from competing with each other; the server now
/// also runs on dedicated queues so it isn't starved by the shared global pool.
@Suite(.serialized)
struct DownloaderTrafficTests {

    /// A throwaway loopback HTTP/1.1 server that serves one fixed body to the first
    /// request, then stops. Returns the port it bound to.
    ///
    /// All Network.framework callbacks run on a **dedicated serial queue**, not the
    /// shared `.global()` concurrent pool: under a saturated test run the global
    /// pool's threads are all blocked on other tests' I/O, which delayed this
    /// server's accept/receive/send long enough for the client download to time
    /// out (-1001). A private queue can't be starved that way.
    private final class OneShotHTTPServer: @unchecked Sendable {
        private let listener: NWListener
        private let body: Data
        private let queue = DispatchQueue(label: "OneShotHTTPServer")
        let port: UInt16

        init(body: Data) throws {
            self.body = body
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: .any)
            self.listener = listener
            let queue = self.queue

            // Handler must be set BEFORE start so the very first connection is served.
            listener.newConnectionHandler = { [body] conn in
                conn.start(queue: queue)
                // Read the request (we don't parse it — any request gets the body).
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    let header = """
                    HTTP/1.1 200 OK\r
                    Content-Type: application/octet-stream\r
                    Content-Length: \(body.count)\r
                    Connection: close\r
                    \r

                    """
                    var response = Data(header.utf8)
                    response.append(body)
                    conn.send(content: response, completion: .contentProcessed { _ in
                        conn.cancel()
                    })
                }
            }

            listener.start(queue: queue)
            // Spin briefly until the OS assigns a concrete port we can dial.
            var resolved: UInt16?
            for _ in 0..<500 {
                if let p = listener.port?.rawValue, p != 0 { resolved = p; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let p = resolved else { throw URLError(.cannotConnectToHost) }
            self.port = p
        }

        func stop() { listener.cancel() }
    }

    @Test func downloaderCountsExactBytesOverHTTP() async throws {
        // A body whose size isn't a round number, to catch any off-by-anything.
        let body = Data((0..<123_457).map { UInt8($0 & 0xFF) })
        let server = try OneShotHTTPServer(body: body)
        defer { server.stop() }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-traffic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        let file = try await downloader.download(url)

        let onDisk = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? -1
        #expect(onDisk == body.count)
        // The reported traffic equals the body size exactly.
        #expect(downloader.bytesDownloaded == Int64(body.count))
    }

    @Test func downloaderBackstopsByteCountFromFileSize() async throws {
        // A file:// source typically fires no didWriteData; the on-disk size backstop
        // must still produce an exact, non-zero byte count.
        let body = Data((0..<4096).map { _ in UInt8(7) })
        let srcDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: srcDir) }
        let src = srcDir.appendingPathComponent("payload.bin")
        try body.write(to: src)

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-dst-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let downloader = Downloader(destinationDir: workDir) { _ in }
        _ = try await downloader.download(src)
        #expect(downloader.bytesDownloaded == Int64(body.count))
    }
}
