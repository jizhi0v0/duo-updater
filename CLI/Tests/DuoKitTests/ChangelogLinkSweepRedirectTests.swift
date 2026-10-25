import Foundation
import Network
import Testing
import DuoUpdaterCore

@testable import DuoKit

/// The link sweep's session used to follow any redirect anywhere. The app's own
/// changelog fetch does not: it stops at a target the changelog pane would refuse
/// (`ChangelogURLPolicy`), and a check that is meant to measure what the button
/// opens has to stop there too — and say so rather than report the far side.
@Suite(.serialized)
struct ChangelogLinkSweepRedirectTests {

    /// `/moved` redirects to plain http on `localhost` (refused by the policy: not
    /// https, and a local name); `/ok` answers 200. `/landing` records that it was
    /// reached, which it must not be.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "ChangelogLinkSweepRedirectTests.Server")
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
            case "/moved":
                return Self.response("302 Found", extra: "Location: http://localhost:\(port)/landing\r\n")
            case "/ok":
                return Self.response("200 OK")
            case "/landing":
                lock.withLock { _landings += 1 }
                return Self.response("200 OK")
            default:
                return Self.response("404 Not Found")
            }
        }

        private static func response(_ status: String, extra: String = "") -> Data {
            Data(("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nCache-Control: no-store\r\n"
                + extra + "Connection: close\r\n\r\n").utf8)
        }
    }

    /// Mutation: give `linkSession` no delegate again — the redirect is followed to
    /// `/landing`, the verdict reads `.alive`, and both assertions go red.
    @Test func aRedirectTheChangelogPaneWouldRefuseIsNotFollowed() async throws {
        let server = try Server()
        defer { server.stop() }

        let verdict = await ChangelogLinkSweep.verdict(
            for: URL(string: "http://127.0.0.1:\(server.port)/moved")!)

        #expect(verdict == .redirectRefused("http://localhost:\(server.port)/landing"))
        #expect(server.landings == 0, "the redirect target was requested")
    }

    /// The same session still answers an ordinary page.
    @Test func aPageThatAnswersIsStillAlive() async throws {
        let server = try Server()
        defer { server.stop() }
        let verdict = await ChangelogLinkSweep.verdict(
            for: URL(string: "http://127.0.0.1:\(server.port)/ok")!)
        #expect(verdict == .alive)
    }

    /// Reported as a machine note naming both ends, never as a warning that could
    /// open an issue against the recipe.
    @Test func aRefusedRedirectIsANoteNamingBothEnds() throws {
        let page = URL(string: "https://vendor.invalid/changelog")!
        let text = try #require(ChangelogLinkSweep.complaint(
            for: .redirectRefused("http://vendor.invalid/changelog"), url: page))
        #expect(text.hasPrefix(Finding.machineNotePrefix))
        #expect(text.contains(page.absoluteString))
        #expect(text.contains("http://vendor.invalid/changelog"))
    }

    /// The delegate applies `ChangelogURLPolicy.isDisplayable` to the target: an
    /// https hop to a named host is followed (vendors move notes between their own
    /// domains), the rest is not.
    ///
    /// Mutation: have the delegate return the request unconditionally.
    @Test(arguments: [
        ("https://docs.vendor.example/notes", true),
        ("http://docs.vendor.example/notes", false),
        ("https://127.0.0.1/notes", false),
        ("https://localhost/notes", false),
        ("https://printer.local/notes", false),
        ("https://user:pass@vendor.example/notes", false),
        ("https://vendor.example:8443/notes", false),
        ("file:///etc/hosts", false),
    ])
    func theDelegateFollowsOnlyWhatThePolicyAllows(target: String, followed: Bool) async throws {
        let url = URL(string: target)!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://vendor.example/changelog")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://vendor.example/changelog")!, statusCode: 302,
            httpVersion: "HTTP/1.1", headerFields: ["Location": target])!

        let followedRequest: URLRequest? = await withCheckedContinuation { continuation in
            ChangelogLinkSweep.ConfinedRedirects().urlSession(
                session, task: task, willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: url), completionHandler: { continuation.resume(returning: $0) })
        }
        #expect((followedRequest != nil) == followed, "\(target)")
    }
}
