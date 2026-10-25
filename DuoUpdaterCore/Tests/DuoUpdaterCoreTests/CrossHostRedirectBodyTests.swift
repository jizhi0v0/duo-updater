import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// A 307/308 keeps the method AND the body, so a POST that is redirected to
/// another host is re-sent there in full. Alcove's POSTs carry the licence key
/// and instance id (`AlcoveUpdateSource.issueToken`, `AlcoveLicenseService`), and
/// `CrossHostCredentialStripper` only dropped headers.
///
/// Not detectable by looking at `request.httpBody`: in the delegate callback the
/// body is nil and travels as `httpBodyStream`, which is why the guard keys on the
/// method. `127.0.0.1` and `localhost` are different hosts to the delegate and the
/// same loopback listener to the OS.
@Suite(.serialized)
struct CrossHostRedirectBodyTests {

    /// `/cross` redirects to `localhost` (another host), `/same` to the same host.
    /// `/landing` records the method and whether a body arrived.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "CrossHostRedirectBodyTests.Server")
        private let lock = NSLock()
        private var _landings: [String] = []
        private var _port: UInt16 = 0
        var port: UInt16 { lock.withLock { _port } }
        /// "METHOD" or "METHOD+body" per request that reached `/landing`.
        var landings: [String] { lock.withLock { _landings } }

        private let status: String

        init(redirectStatus: Int) throws {
            self.status = redirectStatus == 308 ? "308 Permanent Redirect" : "307 Temporary Redirect"
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: self?.queue ?? .main)
                self?.read(conn, buffered: Data())
            }
            listener.start(queue: queue)
            var resolved: UInt16?
            for _ in 0..<500 {
                if let p = listener.port?.rawValue, p != 0 { resolved = p; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let bound = resolved else { throw URLError(.cannotConnectToHost) }
            lock.withLock { _port = bound }
        }

        func stop() { listener.cancel() }

        /// Read until the headers and, when `Content-Length` says so, the whole
        /// body are in: a POST's body can arrive in a segment of its own.
        private func read(_ conn: NWConnection, buffered: Data) {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                var all = buffered
                all.append(data ?? Data())
                let text = String(decoding: all, as: UTF8.self)
                let halves = text.components(separatedBy: "\r\n\r\n")
                let declared = halves[0].components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                let haveBody = halves.dropFirst().joined(separator: "\r\n\r\n").utf8.count
                let headersDone = halves.count > 1
                // A body replayed from a stream goes out chunked, ending in `0\r\n\r\n`.
                let chunked = halves[0].lowercased().contains("transfer-encoding: chunked")
                let chunkedDone = text.hasSuffix("0\r\n\r\n") && haveBody > 0
                if (!headersDone || haveBody < declared || (chunked && !chunkedDone)),
                   !isComplete, error == nil {
                    self?.read(conn, buffered: all)
                    return
                }
                let reply = self?.reply(to: all) ?? Data()
                conn.send(content: reply, completion: .contentProcessed { _ in conn.cancel() })
            }
        }

        private func reply(to data: Data) -> Data {
            let text = String(decoding: data, as: UTF8.self)
            let line = text.components(separatedBy: "\r\n").first ?? ""
            let parts = line.split(separator: " ").map(String.init)
            let method = parts.first ?? "?"
            let path = parts.dropFirst().first ?? "/"
            switch path {
            case "/cross":
                return Self.response(status, extra: "Location: http://localhost:\(port)/landing\r\n")
            case "/same":
                return Self.response(status, extra: "Location: http://127.0.0.1:\(port)/landing\r\n")
            case "/landing":
                let body = text.components(separatedBy: "\r\n\r\n").dropFirst().joined()
                lock.withLock { _landings.append(body.isEmpty ? method : "\(method)+body") }
                return Self.response("200 OK", body: "landed")
            default:
                return Self.response("404 Not Found")
            }
        }

        private static func response(_ status: String, body: String = "", extra: String = "") -> Data {
            let bytes = Data(body.utf8)
            let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(bytes.count)\r\n"
                + "Cache-Control: no-store\r\n" + extra + "Connection: close\r\n\r\n"
            return Data(header.utf8) + bytes
        }
    }

    private func session() -> URLSession {
        URLSession(configuration: .ephemeral,
                   delegate: CrossHostCredentialStripper(loginWalls: []), delegateQueue: nil)
    }

    private func post(_ url: URL, using session: URLSession) async throws -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"license_key":"LICENSE-KEY-FOR-TEST"}"#.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    @Test(arguments: [307, 308])
    func aPostIsNotResentToAnotherHost(status: Int) async throws {
        let server = try Server(redirectStatus: status)
        defer { server.stop() }
        let session = session()
        defer { session.invalidateAndCancel() }

        let code = try await post(URL(string: "http://127.0.0.1:\(server.port)/cross")!, using: session)

        #expect(code == status, "the redirect is returned, not followed")
        #expect(server.landings.isEmpty, "the body must not reach the other host: \(server.landings)")
    }

    /// The same redirect to the same host is an ordinary one and stays followed:
    /// the guard is about crossing hosts, not about POST.
    @Test(arguments: [307, 308])
    func aPostIsStillFollowedOnTheSameHost(status: Int) async throws {
        let server = try Server(redirectStatus: status)
        defer { server.stop() }
        let session = session()
        defer { session.invalidateAndCancel() }

        let code = try await post(URL(string: "http://127.0.0.1:\(server.port)/same")!, using: session)

        #expect(code == 200)
        #expect(server.landings == ["POST+body"])
    }

    /// GET and HEAD carry no body: the cross-host hop is followed as before.
    @Test(arguments: ["GET", "HEAD"])
    func aReadIsStillFollowedAcrossHosts(method: String) async throws {
        let server = try Server(redirectStatus: 307)
        defer { server.stop() }
        let session = session()
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/cross")!)
        request.httpMethod = method
        let (_, response) = try await session.data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(server.landings == [method])
    }
}
