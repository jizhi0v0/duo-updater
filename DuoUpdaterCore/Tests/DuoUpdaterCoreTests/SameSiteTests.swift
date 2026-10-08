import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// `SameSite`: which hosts count as one site, and that a confined request is not
/// followed off its site by the update session (the formula icon fetch relies on
/// this to keep its requests on the formula's own site).
@Suite(.serialized)
struct SameSiteTests {

    @Test func subdomainsAreOneSite() {
        #expect(SameSite.matches(URL(string: "https://www.gnu.org/x")!, URL(string: "https://ftp.gnu.org/y")!))
        #expect(SameSite.matches(URL(string: "https://example.co.uk/")!, URL(string: "https://cdn.example.co.uk/")!))
        #expect(!SameSite.matches(URL(string: "https://example.org/")!, URL(string: "https://cdn.jsdelivr.net/")!))
        #expect(!SameSite.matches(URL(string: "https://a.co.uk/")!, URL(string: "https://b.co.uk/")!))
        #expect(!SameSite.matches(URL(string: "http://localhost/")!, URL(string: "http://localhost/")!))
    }

    @Test func onlyAConfinedRequestIsHeldToItsSite() {
        let plain = URLRequest(url: URL(string: "https://example.org/")!)
        let confined = SameSite.confine(plain)
        let elsewhere = URL(string: "https://cdn.jsdelivr.net/logo.png")
        #expect(SameSite.allowsRedirect(of: plain, to: elsewhere))
        #expect(!SameSite.allowsRedirect(of: confined, to: elsewhere))
        #expect(SameSite.allowsRedirect(of: confined, to: URL(string: "https://www.example.org/")))
    }

    // MARK: - Through the session

    /// `/hop` answers `302` to `localhost` on the same port, a different site from
    /// `127.0.0.1`; `/landing` counts its hits.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "SameSiteTests.Server")
        private let lock = NSLock()
        private var _landings = 0
        private var _port: UInt16 = 0
        var port: UInt16 { lock.withLock { _port } }
        var landings: Int { lock.withLock { _landings } }

        init() throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: self?.queue ?? .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                    let reply = self?.reply(to: data ?? Data()) ?? Data()
                    conn.send(content: reply, completion: .contentProcessed { _ in conn.cancel() })
                }
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

        private func reply(to data: Data) -> Data {
            let line = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
            let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            switch path {
            case "/hop":
                return Self.response("302 Found", extra: "Location: http://localhost:\(port)/landing\r\n")
            case "/landing":
                lock.withLock { _landings += 1 }
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

    private func scratchStore() -> (EventStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        return (EventStore(fileURL: url, flushEventCount: 1, flushDelay: .milliseconds(10)), url)
    }

    /// Through `countedData`, as the icon fetch calls it: its per-task metrics
    /// delegate must leave the redirect to the session's delegate.
    @Test func confinedRequestStopsAtAnOffSiteRedirect() async throws {
        let server = try Server()
        defer { server.stop() }
        let (store, storeURL) = scratchStore()
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: storeURL.path + s) } }
        let session = URLSession(
            configuration: .ephemeral, delegate: CrossHostCredentialStripper(loginWalls: []), delegateQueue: nil)
        let hop = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/hop")!)

        let (_, confined) = try await session.countedData(
            for: SameSite.confine(hop), purpose: .packageIcon, store: store)
        #expect((confined as? HTTPURLResponse)?.statusCode == 302)
        #expect(server.landings == 0)

        // Control: the same request unconfined follows the redirect.
        let (_, followed) = try await session.countedData(for: hop, purpose: .packageIcon, store: store)
        #expect((followed as? HTTPURLResponse)?.statusCode == 200)
        #expect(server.landings == 1)
    }
}
