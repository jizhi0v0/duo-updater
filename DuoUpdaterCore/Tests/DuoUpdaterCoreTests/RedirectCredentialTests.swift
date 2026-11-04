import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// `CrossHostCredentialStripper` on a redirect that stays on its origin: the
/// platform hands every followed redirect a request without `Authorization`
/// (measured 2026-11-04: `api.github.com/repos/<slug>/…`, 301 to
/// `/repositories/<id>/…`, answered `x-ratelimit-limit: 60` with a Bearer sent),
/// and the session delegate puts it back — same host, port and scheme only. A
/// redirect that leaves the origin still loses it.
@Suite(.serialized)
struct RedirectCredentialTests {

    /// `/hop` answers `302` to `/landing` on the same host and port, or to
    /// `localhost:<port>` when `crossHost`; `/landing` records the
    /// `Authorization` header it was asked with.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "RedirectCredentialTests.Server")
        private let lock = NSLock()
        private let crossHost: Bool
        private var _port: UInt16 = 0
        private var _authorization: String?
        var port: UInt16 { lock.withLock { _port } }
        var landingAuthorization: String? { lock.withLock { _authorization } }

        init(crossHost: Bool) throws {
            self.crossHost = crossHost
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: self?.queue ?? .main)
                self?.receive(conn, buffer: Data())
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

        private func receive(_ conn: NWConnection, buffer: Data) {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if String(decoding: buffer, as: UTF8.self).contains("\r\n\r\n") {
                    self.reply(conn, to: buffer)
                } else {
                    self.receive(conn, buffer: buffer)
                }
            }
        }

        private func reply(_ conn: NWConnection, to data: Data) {
            let text = String(decoding: data, as: UTF8.self)
            let requestLine = text.components(separatedBy: "\r\n").first ?? ""
            let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let response: Data
            switch path {
            case "/hop":
                let host = crossHost ? "localhost" : "127.0.0.1"
                response = Self.response("302 Found", extra: "Location: http://\(host):\(port)/landing\r\n")
            case "/landing":
                lock.withLock { _authorization = Self.header("Authorization", in: text) }
                response = Self.response("200 OK", body: "landed")
            default:
                response = Self.response("404 Not Found")
            }
            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }

        private static func header(_ name: String, in text: String) -> String? {
            for line in text.components(separatedBy: "\r\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                guard line[..<colon].trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(name) == .orderedSame else { continue }
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            return nil
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

    private func request(_ server: Server) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/hop")!)
        request.setValue("Bearer placeholder-a", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The bug: a renamed repo's 301 cost the request its token, and the answer
    /// was counted — and refused — on the anonymous budget.
    ///
    /// Mutation: follow the redirect without putting `Authorization` back.
    @Test func aSameOriginRedirectKeepsTheAuthorization() async throws {
        let server = try Server(crossHost: false)
        defer { server.stop() }
        let (_, response) = try await session().data(for: request(server))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(server.landingAuthorization == "Bearer placeholder-a")
    }

    /// The security boundary is unchanged: a redirect to another host still
    /// reaches it without the header.
    ///
    /// Mutation: re-attach whatever the redirect's host, or compare only the
    /// scheme.
    @Test func aCrossHostRedirectStillDropsTheAuthorization() async throws {
        let server = try Server(crossHost: true)
        defer { server.stop() }
        let (_, response) = try await session().data(for: request(server))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(server.landingAuthorization == nil)
    }

    /// What counts as the same origin: host, port and scheme. A port change or
    /// an https → http downgrade is not the origin the credential was meant for.
    ///
    /// Mutation: compare hosts alone.
    @Test func theOriginIsHostPortAndScheme() {
        func same(_ from: String?, _ to: String?) -> Bool {
            CrossHostCredentialStripper.sameOrigin(
                from.flatMap(URL.init(string:)), to.flatMap(URL.init(string:)))
        }
        #expect(same("https://api.github.com/a", "https://api.github.com/b"))
        #expect(same("https://api.github.com/a", "https://API.GITHUB.COM/b"))
        #expect(!same("https://api.github.com/a", "https://api.github.com:8443/b"))
        #expect(!same("https://api.github.com/a", "http://api.github.com/b"))
        #expect(!same("https://api.github.com/a", "https://env.github.com/b"))
        #expect(!same("https://api.github.com/a", nil))
    }
}
