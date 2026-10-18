import AppKit
import DuoUpdaterCore
import Foundation
import Network
import Testing
import WebKit

/// Drives the real `DownloadJob` against a loopback server that drops the first
/// transfer partway, then answers WebKit's resume.
///
/// WebKit finishes a resumed download whatever the server answers: measured
/// 2026-10-15 against a local server, a resume refused with a 203-byte error
/// page ended in `downloadDidFinish`, no error, and the page written over the
/// whole file. On the real Apple CDN the same shape came back as "download ok"
/// 203 bytes past the resume point, and the archive then failed its signature
/// check. Only the size the first response declared can tell the two apart.
@Suite(.serialized)
@MainActor
struct DownloadJobResumeServerTests {

    @Test func aResumeTheServerAnswersInFullLandsTheWholeFile() async throws {
        let server = try await ResumeProbeServer.start(resume: .partialContent)
        defer { server.stop() }
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var authorized = false
        let job = Self.job(into: directory, server: server, onAuthorized: { authorized = true })

        let result = try await Self.run(job, from: server.url)

        #expect(try Data(contentsOf: result.fileURL) == server.body)
        #expect(authorized)
        // One resume, from wherever WebKit had written to: it can trail the
        // bytes the server sent.
        #expect(server.rangeRequests.count == 1)
    }

    @Test func aResumeAnsweredWithAnErrorPageIsAFailureNotAnArchive() async throws {
        let server = try await ResumeProbeServer.start(resume: .forbiddenPage)
        defer { server.stop() }
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var authorized = false
        let job = Self.job(into: directory, server: server, onAuthorized: { authorized = true })

        do {
            let result = try await Self.run(job, from: server.url)
            Issue.record(Comment(rawValue: "a refused resume came back as a \(result.bytesDownloaded)-byte archive"))
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == "com.duoupdater.app.XcodeDownload")
            #expect(nsError.code == -5)
        }
        // The error page never counts as a download that authorized the session.
        #expect(!authorized)
        // One resume, from wherever WebKit had written to: it can trail the
        // bytes the server sent.
        #expect(server.rangeRequests.count == 1)
    }

    // MARK: - Helpers

    private static func job(
        into directory: URL, server: ResumeProbeServer, onAuthorized: @escaping () -> Void
    ) -> DownloadJob {
        // A throwaway store and no-op session hooks: nothing here may touch the
        // real Apple sign-in, whose save writes the Keychain.
        DownloadJob(
            dataStore: .nonPersistent(),
            directory: directory,
            // The drop waits for WebKit to have the cut bytes — see `dropCut()`.
            progress: { fraction in
                if fraction >= Double(ResumeProbeServer.cut) / Double(ResumeProbeServer.length) {
                    server.dropCut()
                }
            },
            onExpired: {},
            onAuthorized: { onAuthorized() })
    }

    /// Runs the job with a deadline, so a WebKit that never calls back fails
    /// the test instead of hanging the suite.
    private static func run(_ job: DownloadJob, from url: URL) async throws -> XcodeArchiveDownload {
        let task = Task { try await job.run(authorizedURL: url) }
        let deadline = Task {
            try await Task.sleep(for: .seconds(30))
            task.cancel()
        }
        defer { deadline.cancel() }
        return try await task.value
    }

    private static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadJobResume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// A one-file HTTP server on loopback. The first GET declares the full length,
/// sends `cut` bytes and drops the connection on `dropCut()`; a GET with `Range`
/// is answered per `resume`.
final class ResumeProbeServer: @unchecked Sendable {
    enum ResumeAnswer {
        /// 206 with the rest of the file.
        case partialContent
        /// 403 with a 203-byte HTML page.
        case forbiddenPage
    }

    static let length = 4 * 1024 * 1024
    static let cut = 1024 * 1024

    let body: Data
    private let resume: ResumeAnswer
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ResumeProbeServer")
    private let lock = NSLock()
    private var ranges: [String] = []
    private var cutConnection: NWConnection?

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/Xcode_probe.xip")! }

    var rangeRequests: [String] {
        lock.lock(); defer { lock.unlock() }
        return ranges
    }

    private init(resume: ResumeAnswer) throws {
        self.resume = resume
        self.body = Data((0..<Self.length).map { UInt8(truncatingIfNeeded: ($0 / 65536) &+ $0) })
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    static func start(resume: ResumeAnswer) async throws -> ResumeProbeServer {
        let server = try ResumeProbeServer(resume: resume)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Called on `queue` only, so this needs no lock of its own.
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            server.listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready:
                    once.done = true
                    continuation.resume()
                case .failed(let error):
                    once.done = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            server.listener.newConnectionHandler = { [weak server] connection in
                server?.accept(connection)
            }
            server.listener.start(queue: server.queue)
        }
        return server
    }

    func stop() {
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection, buffered: Data())
    }

    private func readRequest(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffered = buffered
            if let data { buffered.append(data) }
            if let end = buffered.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffered[..<end.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
            } else if error == nil, !isComplete {
                self.readRequest(connection, buffered: buffered)
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let range = head.split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("range:") }
            .map { $0.dropFirst("range:".count).trimmingCharacters(in: .whitespaces) }
        guard let range else {
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
                + "Content-Length: \(Self.length)\r\nAccept-Ranges: bytes\r\nETag: \"probe-1\"\r\n\r\n"
            lock.lock(); cutConnection = connection; lock.unlock()
            connection.send(content: Data(header.utf8) + body.prefix(Self.cut), completion: .contentProcessed { _ in })
            return
        }
        lock.lock(); ranges.append(range); lock.unlock()
        let start = Int(range.dropFirst("bytes=".count).split(separator: "-").first ?? "") ?? 0
        switch resume {
        case .partialContent:
            let rest = body.suffix(from: start)
            let header = "HTTP/1.1 206 Partial Content\r\nContent-Type: application/octet-stream\r\n"
                + "Content-Range: bytes \(start)-\(Self.length - 1)/\(Self.length)\r\n"
                + "Content-Length: \(rest.count)\r\nETag: \"probe-1\"\r\nConnection: close\r\n\r\n"
            send(Data(header.utf8) + rest, on: connection)
        case .forbiddenPage:
            var page = Data("<html><head><title>403 Forbidden</title></head><body><h1>Forbidden</h1></body></html>".utf8)
            page.append(Data(repeating: 0x20, count: 203 - page.count))
            let header = "HTTP/1.1 403 Forbidden\r\nContent-Type: text/html\r\n"
                + "Content-Length: \(page.count)\r\nConnection: close\r\n\r\n"
            send(Data(header.utf8) + page, on: connection)
        }
    }

    /// Resets the first transfer mid-body, the way a proxy or CDN dropping it
    /// does. Called once WebKit's progress shows it has all `cut` bytes, not
    /// after a fixed wait: a reset throws away whatever the client has not read
    /// yet, and a 0.3 s wait under load (`make test` among other sessions,
    /// 2026-10-18) let it lose all of them. WebKit then resumed from 0 bytes —
    /// a plain GET, cut again — and that second download sometimes never
    /// called back, so the test sat out its deadline.
    func dropCut() {
        lock.lock()
        let connection = cutConnection
        cutConnection = nil
        lock.unlock()
        guard let connection else { return }
        queue.async { connection.forceCancel() }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
