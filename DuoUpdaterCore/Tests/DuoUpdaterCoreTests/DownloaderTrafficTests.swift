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

    /// A loopback server that simulates a flaky transfer. By default the **first**
    /// request (no `Range`) gets a `200` declaring the full `Content-Length` but
    /// only the first `truncateAt` bytes, then the socket is slammed shut — exactly
    /// the premature close URLSession surfaces as a transient `-1005` — and every
    /// request that carries `Range: bytes=<start>-` gets a proper `206` with the
    /// remainder, so the downloader's resume can carry the file to completion.
    ///
    /// The other answer shapes are the ones #225 measured being finalized as a
    /// complete download: a `206` that ignores the range and re-sends the whole
    /// object, a `206` that serves less than the remainder and closes cleanly, a
    /// `206` with no `Content-Range` at all, and a proxy that answers an unranged
    /// GET with `206`. Every request head is recorded so a test can check what
    /// the downloader actually sent (`Range`, `If-Range`).
    private final class RangeResumeServer: @unchecked Sendable {
        enum FirstAnswer {
            /// `200` declaring the full length, `at` bytes on the wire, then the
            /// connection is dropped.
            case truncated(at: Int)
            /// `206` + `Content-Range: bytes 0-(N-1)/N` + the whole body, closed
            /// cleanly: an always-206 proxy answering a request with no `Range`.
            case wholeBodyAs206
        }

        enum RangeAnswer {
            /// Honest `206` with the remainder.
            case remainder
            /// `206` + `Content-Range: bytes 0-(N-1)/N` + the whole body: the
            /// server ignored the range but still said 206.
            case wholeBodyAs206
            /// `200` + the whole body: the server ignored the range and said so.
            case wholeBodyAs200
            /// Honest `Content-Range` and `Content-Length`, but at most `limit`
            /// bytes of the remainder, closed cleanly. `0` produces the RFC-invalid
            /// `bytes N-(N-1)/total`.
            case capped(Int)
            /// The remainder, but with no `Content-Range` header.
            case withoutContentRange
        }

        private let listener: NWListener
        private let queue = DispatchQueue(label: "RangeResumeServer")
        let port: UInt16

        /// Raw request heads in arrival order. Read after `download` returns.
        var requests: [String] { log.requests }
        private let log: RequestLog

        /// Appended to on the server queue, read from the test — a separate
        /// object because `init` cannot capture `self` before `port` is set.
        final class RequestLog: @unchecked Sendable {
            private let lock = NSLock()
            private var _requests: [String] = []
            var requests: [String] { lock.withLock { _requests } }
            func record(_ request: String) { lock.withLock { _requests.append(request) } }
        }

        /// How long to let the truncated body sit on the wire before killing the
        /// connection — see the send site below. Generous for loopback (delivery
        /// takes single-digit milliseconds) so a loaded CI box doesn't reintroduce
        /// the race, and paid only once per run.
        static let dropDelay: TimeInterval = 0.25

        init(
            body: Data,
            first: FirstAnswer,
            range: RangeAnswer = .remainder,
            firstHeaders: [String: String] = [:]
        ) throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let log = RequestLog()
            self.log = log
            let queue = self.queue
            let total = body.count

            listener.newConnectionHandler = { [body, first, range, firstHeaders] conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { reqData, _, _, _ in
                    let request = String(data: reqData ?? Data(), encoding: .utf8) ?? ""
                    log.record(request)

                    func send(_ head: [String], _ payload: Data, dropAfter: TimeInterval? = nil) {
                        var response = Data((head.joined(separator: "\r\n") + "\r\n\r\n").utf8)
                        response.append(payload)
                        conn.send(content: response, completion: .contentProcessed { _ in
                            if let dropAfter {
                                queue.asyncAfter(deadline: .now() + dropAfter) { conn.cancel() }
                            } else {
                                conn.cancel()
                            }
                        })
                    }
                    func partial(_ chunk: Data, from start: Int, contentRange: Bool = true) {
                        var head = ["HTTP/1.1 206 Partial Content"]
                        if contentRange {
                            head.append("Content-Range: bytes \(start)-\(start + chunk.count - 1)/\(total)")
                        }
                        head += ["Content-Length: \(chunk.count)", "Accept-Ranges: bytes", "Connection: close"]
                        send(head, chunk)
                    }

                    if let start = Self.parseRangeStart(request) {
                        switch range {
                        case .remainder:
                            partial(body.subdata(in: start..<total), from: start)
                        case .wholeBodyAs206:
                            partial(body, from: 0)
                        case .wholeBodyAs200:
                            send(["HTTP/1.1 200 OK", "Content-Length: \(total)",
                                  "Accept-Ranges: bytes", "Connection: close"], body)
                        case .capped(let limit):
                            partial(body.subdata(in: start..<min(total, start + limit)), from: start)
                        case .withoutContentRange:
                            partial(body.subdata(in: start..<total), from: start, contentRange: false)
                        }
                        return
                    }

                    switch first {
                    case .wholeBodyAs206:
                        partial(body, from: 0)
                    case .truncated(let at):
                        // First request → declare the full size but cut it short.
                        var head = ["HTTP/1.1 200 OK", "Content-Length: \(total)",
                                    "Accept-Ranges: bytes", "Connection: close"]
                        for (field, value) in firstHeaders.sorted(by: { $0.key < $1.key }) {
                            head.append("\(field): \(value)")
                        }
                        // Drop the connection mid-body: the client has received fewer
                        // bytes than Content-Length → a transient failure it resumes from.
                        //
                        // The teardown is deliberately NOT immediate. `.contentProcessed`
                        // only means Network.framework accepted the bytes for
                        // transmission — not that the peer consumed them — so cancelling
                        // straight from that callback raced URLSession's delivery of the
                        // partial body to its delegate. Losing that race means
                        // `didReceive data:` never fires, the partial file stays empty,
                        // every resume re-requests from byte 0, and the test fails: it did
                        // so ~7 times out of 8. (Real drops don't look like this — bytes
                        // have been flowing for seconds before a proxy resets — so the
                        // race was an artifact of the fixture, not a defect in
                        // `Downloader`.) Letting the bytes land first reproduces the real
                        // shape: data delivered, *then* the connection dies.
                        send(head, body.subdata(in: 0..<at), dropAfter: Self.dropDelay)
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

        /// The value of header `name` in a recorded request head, if present.
        static func header(_ name: String, in request: String) -> String? {
            for line in request.split(separator: "\r\n") {
                guard let colon = line.firstIndex(of: ":"),
                      line[..<colon].lowercased() == name.lowercased() else { continue }
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            return nil
        }

        /// Pull `<start>` out of a `Range: bytes=<start>-` request line, if present.
        private static func parseRangeStart(_ request: String) -> Int? {
            guard let value = header("Range", in: request),
                  let eq = value.firstIndex(of: "="),
                  let dash = value[value.index(after: eq)...].firstIndex(of: "-") else { return nil }
            return Int(value[value.index(after: eq)..<dash].trimmingCharacters(in: .whitespaces))
        }

        func stop() { listener.cancel() }
    }

    /// Collects every fraction handed to `onProgress`, from whichever queue.
    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _fractions: [Double] = []
        var fractions: [Double] { lock.withLock { _fractions } }
        func record(_ fraction: Double) { lock.withLock { _fractions.append(fraction) } }
    }

    private func makeWorkDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The 200 KB body every resume test serves, dropped at 80 KB on the first pass.
    private static let resumeBody = Data((0..<200_000).map { UInt8($0 & 0xFF) })
    private static let resumeDropAt = 80_000

    @Test func downloaderResumesAfterMidTransferDrop() async throws {
        // 200 KB body, dropped at 80 KB on the first pass; the resume fetches the
        // remaining 120 KB via Range and the two halves must reassemble exactly.
        let body = Self.resumeBody
        let server = try RangeResumeServer(body: body, first: .truncated(at: Self.resumeDropAt))
        defer { server.stop() }
        let workDir = try makeWorkDir("resume")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        let file = try await downloader.download(url)

        // The reassembled file is byte-for-byte the original.
        #expect((try? Data(contentsOf: file)) == body)
        // Traffic counts the 80 KB first pass plus the 120 KB resume — the full
        // body, with no double-counting (resume appended rather than restarting).
        #expect(downloader.bytesDownloaded == Int64(body.count))
        #expect(server.requests.count == 2)
        #expect(RangeResumeServer.header("Range", in: server.requests[1]) == "bytes=\(Self.resumeDropAt)-")
    }

    /// The installer download also lands in the event store.
    ///
    /// `bytesDownloaded` above and this are two different accounts of one
    /// transfer and are *supposed* to disagree: that one is body bytes for the
    /// per-app ``TrafficStore``, this one is network activity per host with
    /// headers and every attempt included. Pinned because the store's whole claim
    /// is that it sees all of our traffic, and the installer bytes are the largest
    /// part of it — a `Downloader` that quietly stopped reporting would leave the
    /// summary looking plausible and reading low by two orders of magnitude.
    @Test func downloaderFilesTheTransferInTheEventStore() async throws {
        let body = Self.resumeBody
        let server = try RangeResumeServer(body: body, first: .truncated(at: Self.resumeDropAt))
        defer { server.stop() }
        let workDir = try makeWorkDir("events")
        defer { try? FileManager.default.removeItem(at: workDir) }
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()
                    .appendingPathComponent(storeURL.lastPathComponent + suffix))
            }
        }
        let store = EventStore(fileURL: storeURL, flushEventCount: 1,
                               flushDelay: .milliseconds(10))

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir, store: store) { _ in }
        // Inside an attribution scope, because the installers are the biggest
        // rows in the log and this class is the one path that does NOT go
        // through `countedData`: it is its own session delegate, and the metrics
        // callback runs on the delegate queue where the task-local reads back as
        // nil. It captures the value in `download` instead — silently, if that
        // capture is ever dropped, which is what this asserts.
        try await RequestAttribution.withApp("/Applications/Amp.app") {
            _ = try await downloader.download(url)
        }

        // Both attempts, since both really crossed the network.
        for _ in 0..<100 {
            if await store.appendedCount >= 2 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        await store.flush()
        let events = await store.events(EventQuery(limit: 100)).compactMap(\.request)
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.purpose == .install })
        #expect(events.allSatisfy { $0.host == "127.0.0.1" })
        #expect(events.allSatisfy { $0.appID == "/Applications/Amp.app" },
                "the download rows must name the app they were for")
        // And the rollup the events fed, in the same transaction: headers on top
        // of the body, and never less than it.
        let total = await store.totals().totals.first
        #expect((total?.bytesReceived ?? 0) > Int64(body.count))
    }

    // MARK: - #225: a 206 is only a resume if its Content-Range says so

    /// The parser the 206 branch stands on. The first six rows are what real
    /// CDNs answered a ranged GET with on 2026-09-01 (GitHub's Azure blob,
    /// Docker, Google, Mozilla, Microsoft PRSS, iTerm2's Apache) — all the
    /// canonical form, so no production resume path changes. The rest are the
    /// RFC 9110 §14.4 edges: `*/total` is the 416 form and has no first-pos to
    /// join on; last below first, or a total at or below last, is invalid and
    /// "MUST NOT" be recombined; `*` for the total is legal and leaves the
    /// total unknown. The same table runs against an independent Python port.
    @Test func contentRangeParserAgreesWithTheTable() {
        typealias CR = Downloader.ContentRange
        let table: [(String, CR?)] = [
            ("bytes 1000-1999/13292644", CR(first: 1000, last: 1999, total: 13_292_644)),
            ("bytes 1000-1999/583525084", CR(first: 1000, last: 1999, total: 583_525_084)),
            ("bytes 1000-1999/277180860", CR(first: 1000, last: 1999, total: 277_180_860)),
            ("bytes 1000-1999/159402262", CR(first: 1000, last: 1999, total: 159_402_262)),
            ("bytes 1000-1999/317264221", CR(first: 1000, last: 1999, total: 317_264_221)),
            ("bytes 1000-1999/45124064", CR(first: 1000, last: 1999, total: 45_124_064)),
            ("bytes 80000-199999/200000", CR(first: 80_000, last: 199_999, total: 200_000)),
            ("bytes 0-199999/200000", CR(first: 0, last: 199_999, total: 200_000)),
            ("bytes 80000-80000/200000", CR(first: 80_000, last: 80_000, total: 200_000)),
            ("bytes 0-0/1", CR(first: 0, last: 0, total: 1)),
            ("bytes 80000-199999/*", CR(first: 80_000, last: 199_999, total: nil)),
            ("BYTES 80000-199999/200000", CR(first: 80_000, last: 199_999, total: 200_000)),
            ("  bytes 80000-199999/200000  ", CR(first: 80_000, last: 199_999, total: 200_000)),
            ("bytes 80000-79999/200000", nil),
            ("bytes */200000", nil),
            ("bytes 80000-199999/199999", nil),
            ("items 80000-199999/200000", nil),
            ("bytes=80000-199999/200000", nil),
            ("bytes 80000-199999", nil),
            ("", nil),
        ]
        for (value, expected) in table {
            #expect(Downloader.parseContentRange(value) == expected, "\(value)")
        }
    }

    /// The server ignores the range but still answers `206`, with
    /// `Content-Range: bytes 0-(N-1)/N` and the whole object. Before #225 that
    /// whole object was appended onto the 80 KB partial and a 280 KB file was
    /// finalized as success. A first-byte-pos of 0 now means what it says — this
    /// is the whole thing — and the partial is discarded, exactly as for a `200`.
    @Test func downloaderRestartsWhenRangeIsAnsweredFromByteZeroAs206() async throws {
        let body = Self.resumeBody
        let server = try RangeResumeServer(
            body: body, first: .truncated(at: Self.resumeDropAt), range: .wholeBodyAs206)
        defer { server.stop() }
        let workDir = try makeWorkDir("restart206")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let progress = ProgressLog()
        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { progress.record($0) }
        let file = try await downloader.download(url)

        #expect((try? Data(contentsOf: file)) == body)
        // Traffic is what was actually pulled: the 80 KB first pass plus the
        // 200 KB re-send, including the 80 KB that were thrown away.
        #expect(downloader.bytesDownloaded == Int64(Self.resumeDropAt + body.count))
        #expect(server.requests.count == 2)
        // Restarting from zero mid-download must not push the bar past 100% or
        // below 0, and the download must still end at 100%.
        let fractions = progress.fractions
        #expect(fractions.allSatisfy { (0.0...1.0).contains($0) })
        #expect(fractions.last == 1.0)
    }

    /// The same shape as a `200` — the branch that was already careful. Pinned
    /// so the 206 work above cannot regress it: the partial is discarded, the
    /// file is whole, and the traffic count includes the discarded bytes.
    @Test func downloaderRestartsWhenRangeIsAnsweredAs200() async throws {
        let body = Self.resumeBody
        let server = try RangeResumeServer(
            body: body, first: .truncated(at: Self.resumeDropAt), range: .wholeBodyAs200)
        defer { server.stop() }
        let workDir = try makeWorkDir("restart200")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let progress = ProgressLog()
        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { progress.record($0) }
        let file = try await downloader.download(url)

        #expect((try? Data(contentsOf: file)) == body)
        #expect(downloader.bytesDownloaded == Int64(Self.resumeDropAt + body.count))
        #expect(server.requests.count == 2)
        let fractions = progress.fractions
        #expect(fractions.allSatisfy { (0.0...1.0).contains($0) })
        #expect(fractions.last == 1.0)
    }

    /// A `206` without `Content-Range` is malformed (RFC 9110 §15.3.7.1: a
    /// single-part 206 MUST carry one). Without it there is no way to know where
    /// the bytes belong: appending them is the double-append in #225, writing
    /// them from zero is a different corruption. Rejected on the spot and not
    /// retried — the same request would draw the same answer.
    @Test func downloaderRejectsPartialContentWithoutContentRange() async throws {
        let body = Self.resumeBody
        let server = try RangeResumeServer(
            body: body, first: .truncated(at: Self.resumeDropAt), range: .withoutContentRange)
        defer { server.stop() }
        let workDir = try makeWorkDir("nocontentrange")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        do {
            _ = try await downloader.download(url)
            Issue.record("a 206 without Content-Range was finalized as a complete download")
        } catch let error as Downloader.DownloadError {
            guard case .badPartialContent = error else {
                Issue.record("unexpected DownloadError: \(error)"); return
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        // One resume, then it stopped: not transient.
        #expect(server.requests.count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: workDir.path).isEmpty)
    }

    /// The server honours the range but hands back less than the remainder — an
    /// honest `Content-Range`, an honest `Content-Length`, a clean close. Before
    /// #225 the 130 KB file was finalized as success. Now a clean close with
    /// fewer bytes on disk than the declared total is a transient failure, and
    /// the next attempt asks for the rest from the new offset, until the file is
    /// whole.
    @Test func downloaderKeepsResumingWhenRangeAnswersAreShort() async throws {
        let body = Self.resumeBody
        let server = try RangeResumeServer(
            body: body, first: .truncated(at: Self.resumeDropAt), range: .capped(50_000))
        defer { server.stop() }
        let workDir = try makeWorkDir("shortranges")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let progress = ProgressLog()
        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { progress.record($0) }
        let file = try await downloader.download(url)

        #expect((try? Data(contentsOf: file)) == body)
        #expect(downloader.bytesDownloaded == Int64(body.count))
        // 80 KB, then 50 KB + 50 KB + 20 KB: four requests, each resuming from
        // exactly where the previous one stopped.
        let ranges = server.requests.map { RangeResumeServer.header("Range", in: $0) }
        #expect(ranges == [nil, "bytes=80000-", "bytes=130000-", "bytes=180000-"])
        // No restart happened, so progress never goes backwards.
        let fractions = progress.fractions
        #expect(fractions == fractions.sorted())
        #expect(fractions.last == 1.0)
    }

    /// The retry budget still bounds the short-answer loop: a server that always
    /// gives one more byte ends in a thrown error after `maxAttempts`, not in a
    /// truncated file finalized as success, and not in an unbounded loop.
    @Test func downloaderGivesUpOnShortRangesAfterMaxAttempts() async throws {
        let body = Self.resumeBody
        let server = try RangeResumeServer(
            body: body, first: .truncated(at: Self.resumeDropAt), range: .capped(1))
        defer { server.stop() }
        let workDir = try makeWorkDir("shortforever")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        do {
            _ = try await downloader.download(url)
            Issue.record("a short download was finalized as success")
        } catch let error as Downloader.DownloadError {
            guard case .lengthMismatch(let received, let expected) = error else {
                Issue.record("unexpected DownloadError: \(error)"); return
            }
            // 80 000 from the first pass plus one byte per resume.
            #expect(received == Int64(Self.resumeDropAt + 4))
            #expect(expected == Int64(body.count))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        // The first attempt plus four resumes: maxAttempts is 5.
        #expect(server.requests.count == 5)
        #expect(try FileManager.default.contentsOfDirectory(atPath: workDir.path).isEmpty)
    }

    /// A `206` carrying zero bytes says `Content-Range: bytes 80000-79999/200000`,
    /// which RFC 9110 §14.4 calls invalid (last-pos below first-pos) and says a
    /// recipient "MUST NOT attempt to recombine". Rejected immediately rather
    /// than spent on four more identical resumes.
    @Test func downloaderRejectsAnEmptyRangeAnswer() async throws {
        let body = Self.resumeBody
        let server = try RangeResumeServer(
            body: body, first: .truncated(at: Self.resumeDropAt), range: .capped(0))
        defer { server.stop() }
        let workDir = try makeWorkDir("emptyrange")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        do {
            _ = try await downloader.download(url)
            Issue.record("an 80 KB partial was finalized as the 200 KB download")
        } catch let error as Downloader.DownloadError {
            guard case .badPartialContent = error else {
                Issue.record("unexpected DownloadError: \(error)"); return
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(server.requests.count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: workDir.path).isEmpty)
    }

    /// A proxy that answers an unranged GET with `206` + `Content-Range: bytes
    /// 0-(N-1)/N` is handing over the whole object. Before #225 that was
    /// `httpStatus(206)`, which is not retried — a permanent failure for every
    /// download through that proxy. It is a fresh body now.
    @Test func downloaderAcceptsPartialContentForAnUnrangedRequest() async throws {
        let body = Self.resumeBody
        let server = try RangeResumeServer(body: body, first: .wholeBodyAs206)
        defer { server.stop() }
        let workDir = try makeWorkDir("always206")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        let file = try await downloader.download(url)

        #expect((try? Data(contentsOf: file)) == body)
        #expect(downloader.bytesDownloaded == Int64(body.count))
        #expect(server.requests.count == 1)
    }

    /// A resume carries `If-Range` with the validator the first response gave,
    /// so a CDN that replaced the object between attempts answers `200` (which
    /// discards the partial) instead of splicing two builds together. RFC 9110
    /// §13.1.5: a strong ETag; never a weak (`W/`) one; `Last-Modified` only when
    /// there is no ETag at all. The first request, which has no `Range`, must not
    /// carry it either.
    @Test func downloaderSendsIfRangeOnlyWithAStrongValidator() async throws {
        struct Case {
            let headers: [String: String]
            let expected: String?
            let why: String
        }
        let lastModified = "Wed, 15 Nov 1995 04:58:08 GMT"
        let cases = [
            Case(headers: ["ETag": "\"v1\""], expected: "\"v1\"", why: "strong ETag"),
            Case(headers: ["ETag": "\"v1\"", "Last-Modified": lastModified], expected: "\"v1\"",
                 why: "strong ETag wins over Last-Modified"),
            Case(headers: ["Last-Modified": lastModified], expected: lastModified,
                 why: "Last-Modified when there is no ETag"),
            Case(headers: ["ETag": "W/\"v1\""], expected: nil, why: "weak ETag alone"),
            Case(headers: ["ETag": "W/\"v1\"", "Last-Modified": lastModified], expected: nil,
                 why: "weak ETag: the client has an entity tag, so no date either"),
            Case(headers: [:], expected: nil, why: "no validator"),
        ]
        for c in cases {
            let body = Self.resumeBody
            let server = try RangeResumeServer(
                body: body, first: .truncated(at: Self.resumeDropAt), firstHeaders: c.headers)
            defer { server.stop() }
            let workDir = try makeWorkDir("ifrange")
            defer { try? FileManager.default.removeItem(at: workDir) }

            let url = URL(string: "http://127.0.0.1:\(server.port)/blob.bin")!
            let downloader = Downloader(destinationDir: workDir) { _ in }
            let file = try await downloader.download(url)

            #expect((try? Data(contentsOf: file)) == body, "\(c.why)")
            let requests = server.requests
            #expect(requests.count == 2, "\(c.why)")
            #expect(RangeResumeServer.header("If-Range", in: requests[0]) == nil, "\(c.why)")
            #expect(RangeResumeServer.header("If-Range", in: requests[1]) == c.expected, "\(c.why)")
        }
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

    /// `finalHost` must reflect the host that actually SERVED the bytes — the
    /// host written in the URL (or the appcast enclosure) can be a redirect
    /// shim (GitHub → objects.githubusercontent.com). The per-install host gate
    /// keys on this, so a redirect must not hide the real server.
    @Test func downloaderReportsPostRedirectHost() async throws {
        let body = Data("payload".utf8)
        let target = try OneShotHTTPServer(body: body)
        defer { target.stop() }
        let source = try OneShotHTTPServer(
            body: Data(),
            status: "302 Found",
            headers: ["Location": "http://localhost:\(target.port)/payload.bin"]
        )
        defer { source.stop() }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-finalhost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let url = URL(string: "http://127.0.0.1:\(source.port)/redirect")!
        let downloader = Downloader(destinationDir: workDir) { _ in }
        let file = try await downloader.download(url)

        #expect((try? Data(contentsOf: file)) == body)
        #expect(downloader.finalHost == "localhost")
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
