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
        private let status: String
        private let headers: [String: String]
        private let queue = DispatchQueue(label: "OneShotHTTPServer")
        let port: UInt16

        init(
            body: Data,
            status: String = "200 OK",
            headers: [String: String] = [:]
        ) throws {
            self.body = body
            self.status = status
            self.headers = headers
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: .any)
            self.listener = listener
            let queue = self.queue

            // Handler must be set BEFORE start so the very first connection is served.
            listener.newConnectionHandler = { [body, status, headers] conn in
                conn.start(queue: queue)
                // Read the request (we don't parse it — any request gets the body).
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    var header = "HTTP/1.1 \(status)\r\n"
                    var responseHeaders = headers
                    responseHeaders["Content-Type"] = responseHeaders["Content-Type"] ?? "application/octet-stream"
                    responseHeaders["Content-Length"] = responseHeaders["Content-Length"] ?? "\(body.count)"
                    responseHeaders["Connection"] = responseHeaders["Connection"] ?? "close"
                    for (field, value) in responseHeaders.sorted(by: { $0.key < $1.key }) {
                        header += "\(field): \(value)\r\n"
                    }
                    header += "\r\n"
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

    /// A loopback server that simulates a flaky transfer: the **first** request
    /// (no `Range`) gets a `200` declaring the full `Content-Length` but only the
    /// first `truncateAt` bytes, then the socket is slammed shut — exactly the
    /// premature close URLSession surfaces as a transient `-1005`. Every request
    /// that carries `Range: bytes=<start>-` gets a proper `206` with the remainder,
    /// so the downloader's resume can carry the file to completion.
    private final class RangeResumeServer: @unchecked Sendable {
        private let listener: NWListener
        private let body: Data
        private let truncateAt: Int
        private let queue = DispatchQueue(label: "RangeResumeServer")
        let port: UInt16

        init(body: Data, truncateAt: Int) throws {
            self.body = body
            self.truncateAt = truncateAt
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let total = body.count

            listener.newConnectionHandler = { [body, truncateAt] conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { reqData, _, _, _ in
                    let request = String(data: reqData ?? Data(), encoding: .utf8) ?? ""
                    let rangeStart = Self.parseRangeStart(request)

                    if let start = rangeStart {
                        // Resume request → serve the remainder as a clean 206.
                        let chunk = body.subdata(in: start..<total)
                        var header = "HTTP/1.1 206 Partial Content\r\n"
                        header += "Content-Range: bytes \(start)-\(total - 1)/\(total)\r\n"
                        header += "Content-Length: \(chunk.count)\r\n"
                        header += "Accept-Ranges: bytes\r\n"
                        header += "Connection: close\r\n\r\n"
                        var response = Data(header.utf8)
                        response.append(chunk)
                        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
                    } else {
                        // First request → declare the full size but cut it short.
                        var header = "HTTP/1.1 200 OK\r\n"
                        header += "Content-Length: \(total)\r\n"
                        header += "Accept-Ranges: bytes\r\n"
                        header += "Connection: close\r\n\r\n"
                        var response = Data(header.utf8)
                        response.append(body.subdata(in: 0..<truncateAt))
                        // Slam the connection shut mid-body: the client has received
                        // fewer bytes than Content-Length → a transient failure.
                        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
                    }
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

        /// Pull `<start>` out of a `Range: bytes=<start>-` request line, if present.
        private static func parseRangeStart(_ request: String) -> Int? {
            for line in request.split(separator: "\r\n") {
                let lower = line.lowercased()
                guard lower.hasPrefix("range:"),
                      let eq = line.firstIndex(of: "="),
                      let dash = line[line.index(after: eq)...].firstIndex(of: "-") else { continue }
                let digits = line[line.index(after: eq)..<dash].trimmingCharacters(in: .whitespaces)
                return Int(digits)
            }
            return nil
        }

        func stop() { listener.cancel() }
    }

    @Test func downloaderResumesAfterMidTransferDrop() async throws {
        // 200 KB body, dropped at 80 KB on the first pass; the resume fetches the
        // remaining 120 KB via Range and the two halves must reassemble exactly.
        let body = Data((0..<200_000).map { UInt8($0 & 0xFF) })
        let server = try RangeResumeServer(body: body, truncateAt: 80_000)
        defer { server.stop() }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        let file = try await downloader.download(url)

        // The reassembled file is byte-for-byte the original.
        #expect((try? Data(contentsOf: file)) == body)
        // Traffic counts the 80 KB first pass plus the 120 KB resume — the full
        // body, with no double-counting (resume appended rather than restarting).
        #expect(downloader.bytesDownloaded == Int64(body.count))
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

    /// A `Downloader` must be fully released once its download returns.
    ///
    /// `URLSession(configuration:delegate:delegateQueue:)` keeps a **strong**
    /// reference to its delegate until the session is invalidated — and the
    /// delegate here is the `Downloader`, which also owns the session. That's a
    /// cycle ARC can't break, so a session held for the object's lifetime leaked
    /// the downloader, the session, and its delegate queue on **every install**,
    /// for the whole life of a menu-bar process that runs for weeks. `download`
    /// now scopes the session to one call and invalidates it on exit; this pins
    /// that, because reverting to a lifetime session still passes every other
    /// test in this file.
    @Test func downloaderIsReleasedAfterDownload() async throws {
        let body = Data((0..<4096).map { UInt8($0 & 0xFF) })
        let server = try OneShotHTTPServer(body: body)
        defer { server.stop() }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-lifetime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        weak var weakDownloader: Downloader?
        do {
            let downloader = Downloader(destinationDir: workDir) { _ in }
            weakDownloader = downloader
            _ = try await downloader.download(url)
        }
        // `finishTasksAndInvalidate` releases the delegate asynchronously on the
        // session's own queue, so give it a beat before asserting.
        try await Task.sleep(for: .milliseconds(500))
        #expect(weakDownloader == nil, "Downloader leaked — its URLSession was never invalidated")
    }

    @Test func downloaderRefusesInsecureRemoteRedirect() async throws {
        let server = try OneShotHTTPServer(
            body: Data(),
            status: "302 Found",
            headers: ["Location": "http://example.com/payload.zip"]
        )
        defer { server.stop() }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-redirect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/redirect")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        do {
            _ = try await downloader.download(url)
            Issue.record("expected insecure redirect to be refused")
        } catch is SecureScheme.SchemeError {
            // Expected.
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func downloaderConfinesSuggestedFilenameToDestinationDirectory() async throws {
        #expect(Downloader.safeSuggestedFilename("../outside.bin") == "outside.bin")
        #expect(Downloader.safeSuggestedFilename("/tmp/outside.bin") == "outside.bin")
        #expect(Downloader.safeSuggestedFilename("..") == "download")

        let body = Data("payload".utf8)
        let server = try OneShotHTTPServer(
            body: body,
            headers: ["Content-Disposition": #"attachment; filename="../outside.bin""#]
        )
        defer { server.stop() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-filename-\(UUID().uuidString)", isDirectory: true)
        let workDir = root.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = root.appendingPathComponent("outside.bin")
        try Data("sentinel".utf8).write(to: outside)

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        let file = try await downloader.download(url)

        #expect(file.deletingLastPathComponent().standardizedFileURL.path == workDir.standardizedFileURL.path)
        #expect((try? Data(contentsOf: outside)) == Data("sentinel".utf8))
        #expect((try? Data(contentsOf: file)) == body)
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
