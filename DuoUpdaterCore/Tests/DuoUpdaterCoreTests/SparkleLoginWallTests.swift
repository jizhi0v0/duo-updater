import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// A feed redirect declared as a login wall is not followed (#892).
///
/// Muse's appcast on facebook.com usually answers `302 → /login/?next=…`. The
/// session used to follow that redirect and download the ~84 KB login page on
/// every check round, only for `SparkleAppcastSource` to throw `notAFeed`. With
/// the wall declared, the session delegate stops at the 302 and the source throws
/// the same `notAFeed` from the 3xx, so the next source answers exactly as before.
///
/// The server here is loopback. `127.0.0.1` plays the vendor and `localhost` plays
/// a second host, so the cross-host credential stripping can be seen from the
/// server side as well.
@Suite(.serialized)
struct SparkleLoginWallTests {

    // MARK: - Fixture

    /// Loopback HTTP/1.1 server with four routes:
    /// - `/endo/appcast.xml` answers `302 → /login/?next=…` while `walled`, and a
    ///   one-item appcast otherwise;
    /// - `/login/` answers a login page, and counts its hits;
    /// - `/api/feed.xml` answers `302` to `localhost` on the same port, so a
    ///   request that follows it crosses hosts;
    /// - `/landing.xml` answers the appcast and records whether `Authorization`
    ///   arrived.
    private final class Server: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "SparkleLoginWallTests.Server")
        private let lock = NSLock()
        private var _hits: [String: Int] = [:]
        private var _landingAuthorization: [String?] = []
        private var _walled: Bool
        private var _port: UInt16 = 0
        /// Set once in `init`, before any request can know where to go.
        var port: UInt16 { lock.withLock { _port } }

        static let appcast = """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel><title>Subject</title>
                <item>
                  <title>Version 4.1</title>
                  <sparkle:version>1077426479</sparkle:version>
                  <sparkle:shortVersionString>4.1</sparkle:shortVersionString>
                  <enclosure url="https://cdn.example.invalid/Subject-4.1.dmg" length="10" type="application/octet-stream"/>
                </item>
              </channel>
            </rss>
            """

        /// Big enough that downloading it is not an accident a test could miss.
        static let loginPage = "<!DOCTYPE html><html><head><title>Log in</title></head><body>"
            + String(repeating: "<div>sign in</div>", count: 4_000) + "</body></html>"

        func hits(_ path: String) -> Int { lock.withLock { _hits[path] ?? 0 } }
        var landingAuthorization: [String?] { lock.withLock { _landingAuthorization } }
        var walled: Bool {
            get { lock.withLock { _walled } }
            set { lock.withLock { _walled = newValue } }
        }

        init(walled: Bool) throws {
            _walled = walled
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: queue)
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
            let text = String(decoding: data, as: UTF8.self)
            let lines = text.components(separatedBy: "\r\n")
            let target = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let path = String(target.split(separator: "?", maxSplits: 1).first ?? "/")
            let authorization = lines.dropFirst()
                .first { $0.lowercased().hasPrefix("authorization:") }
                .map { String($0.dropFirst("authorization:".count)).trimmingCharacters(in: .whitespaces) }
            lock.withLock {
                _hits[path, default: 0] += 1
                if path == "/landing.xml" { _landingAuthorization.append(authorization) }
            }
            switch path {
            case "/endo/appcast.xml" where walled:
                let next = "http%3A%2F%2F127.0.0.1%3A\(port)%2Fendo%2Fappcast.xml"
                return Self.response(
                    "302 Found", type: "text/html; charset=\"utf-8\"", body: "",
                    extra: "Location: http://127.0.0.1:\(port)/login/?next=\(next)\r\n")
            case "/endo/appcast.xml", "/landing.xml":
                return Self.response("200 OK", type: "text/xml;charset=utf-8", body: Self.appcast)
            case "/login/":
                return Self.response("200 OK", type: "text/html; charset=\"utf-8\"", body: Self.loginPage)
            case "/api/feed.xml":
                return Self.response(
                    "302 Found", type: "text/plain", body: "",
                    extra: "Location: http://localhost:\(port)/landing.xml\r\n")
            default:
                return Self.response("404 Not Found", type: "text/plain", body: "")
            }
        }

        private static func response(_ status: String, type: String, body: String, extra: String = "") -> Data {
            let bytes = Data(body.utf8)
            var header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(bytes.count)\r\n"
            header += "Cache-Control: no-store\r\n" + extra + "Connection: close\r\n\r\n"
            return Data(header.utf8) + bytes
        }
    }

    private static func feedURL(_ server: Server) -> URL {
        URL(string: "http://127.0.0.1:\(server.port)/endo/appcast.xml?channel=production")!
    }

    /// The wall as a recipe would declare it, for this server.
    private static func walls(_ server: Server) -> [SparkleFeedCatalog.LoginWall] {
        [SparkleFeedCatalog.LoginWall(
            feed: URL(string: "http://127.0.0.1:\(server.port)/endo/appcast.xml")!,
            login: URL(string: "http://127.0.0.1:\(server.port)/login/")!)]
    }

    /// A session built like `URLSession.updates`: same delegate class, same
    /// walls as the source.
    private static func source(
        _ server: Server, walls: [SparkleFeedCatalog.LoginWall]
    ) -> SparkleAppcastSource {
        let session = URLSession(
            configuration: .ephemeral,
            delegate: CrossHostCredentialStripper(loginWalls: walls), delegateQueue: nil)
        return SparkleAppcastSource(session: session, loginWalls: walls)
    }

    private static func app(_ server: Server) -> InstalledApp {
        InstalledApp(
            name: "Subject", bundleID: "com.example.subject", shortVersion: "2.2",
            buildVersion: "1074644564",
            path: URL(fileURLWithPath: "/Applications/Subject.app"),
            isMASApp: false, sparkleFeedURL: feedURL(server))
    }

    /// Stands in for Muse's Homebrew-cask VendorProbe.
    private struct Fallback: UpdateSource {
        let name = "Vendor"
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            RemoteVersion(shortVersion: "4.1", version: nil, downloadURL: nil, sourceName: name)
        }
    }

    private static func notAFeedDescription(
        _ source: SparkleAppcastSource, _ app: InstalledApp
    ) async -> String? {
        do {
            let remote = try await source.latestVersion(for: app)
            Issue.record("expected SparkleError.notAFeed, got \(String(describing: remote))")
        } catch let error as SparkleAppcastSource.SparkleError {
            guard case .notAFeed = error else { Issue.record("wrong case: \(error)"); return nil }
            return error.errorDescription
        } catch {
            Issue.record("expected SparkleError.notAFeed, got \(error)")
        }
        return nil
    }

    // MARK: - Tests

    /// The fix. Mutations, each red here:
    /// - drop the wall check in `CrossHostCredentialStripper` → the login page is
    ///   fetched (`/login/` hit once);
    /// - drop the 3xx branch in `SparkleAppcastSource.latestVersion` → the source
    ///   throws `badStatus(302)` instead of `notAFeed`.
    @Test func aDeclaredWallStopsAtTheRedirectAndStillThrowsNotAFeed() async throws {
        let server = try Server(walled: true)
        defer { server.stop() }

        let description = await Self.notAFeedDescription(
            Self.source(server, walls: Self.walls(server)), Self.app(server))

        #expect(server.hits("/endo/appcast.xml") == 1)
        #expect(server.hits("/login/") == 0, "the login page was downloaded")
        #expect(description?.contains("web page") == true)
        #expect(description?.contains("127.0.0.1/login") == true)
    }

    /// The error is the one the downloaded page used to produce, message and all.
    /// The control run (no wall declared) is today's behaviour, and it must still
    /// download the page, or this comparison proves nothing.
    @Test func theErrorMatchesTheOneTheDownloadedPageProduced() async throws {
        let server = try Server(walled: true)
        defer { server.stop() }

        let before = await Self.notAFeedDescription(Self.source(server, walls: []), Self.app(server))
        #expect(server.hits("/login/") == 1, "control run did not follow the redirect")
        let after = await Self.notAFeedDescription(
            Self.source(server, walls: Self.walls(server)), Self.app(server))
        #expect(server.hits("/login/") == 1, "the login page was downloaded again")

        #expect(before != nil)
        #expect(after == before)
    }

    /// Through the checker, the next source answers, the same with and without the
    /// wall. This is the #867 fallback.
    @Test func theNextSourceAnswersAsBefore() async throws {
        let server = try Server(walled: true)
        defer { server.stop() }

        for walls in [[], Self.walls(server)] {
            let checker = UpdateChecker(sources: [Self.source(server, walls: walls), Fallback()])
            let result = await checker.check(Self.app(server))
            #expect(result.remote?.sourceName == "Vendor")
            #expect(result.remote?.shortVersion == "4.1")
            guard case .updateAvailable = result.status else {
                Issue.record("expected .updateAvailable, got \(result.status)")
                continue
            }
        }
        #expect(server.hits("/login/") == 1, "only the run without the wall should fetch the page")
    }

    /// When the feed gets through, Sparkle answers, with the wall declared.
    @Test func aFeedThatGetsThroughIsStillRead() async throws {
        let server = try Server(walled: false)
        defer { server.stop() }

        let remote = try await Self.source(server, walls: Self.walls(server))
            .latestVersion(for: Self.app(server))
        #expect(remote?.shortVersion == "4.1")
        #expect(remote?.version == "1077426479")

        let checker = UpdateChecker(sources: [Self.source(server, walls: Self.walls(server)), Fallback()])
        let result = await checker.check(Self.app(server))
        #expect(result.remote?.sourceName == "Sparkle")
        #expect(server.hits("/login/") == 0)
    }

    /// The same delegate still strips credentials on a cross-host redirect that
    /// is not a wall, and still follows it.
    @Test func otherRedirectsAreFollowedWithCredentialsStripped() async throws {
        let server = try Server(walled: true)
        defer { server.stop() }

        let session = URLSession(
            configuration: .ephemeral,
            delegate: CrossHostCredentialStripper(loginWalls: Self.walls(server)), delegateQueue: nil)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/api/feed.xml")!)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("Bearer not-a-real-token", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(response.url?.host == "localhost")
        #expect(server.landingAuthorization == [nil])
    }

    /// The match itself: the feed by scheme, host and path (query ignored); the
    /// login page by path prefix, trailing slash included.
    @Test func theWallMatchesOnlyItsOwnRedirect() throws {
        let wall = SparkleFeedCatalog.LoginWall(
            feed: URL(string: "https://www.example.invalid/endo/release/appcast.xml")!,
            login: URL(string: "https://www.example.invalid/login/")!)
        let feed = URL(string: "https://WWW.example.invalid/endo/release/appcast.xml?channel=production")
        let login = URL(string: "https://www.example.invalid/login/?next=https%3A%2F%2Fwww.example.invalid%2F")

        #expect(wall.matches(redirectFrom: feed, to: login))
        // Another feed on the same host.
        #expect(!wall.matches(
            redirectFrom: URL(string: "https://www.example.invalid/other/appcast.xml"), to: login))
        // A path that only starts with the same letters.
        #expect(!wall.matches(
            redirectFrom: feed, to: URL(string: "https://www.example.invalid/loginfoo/x")))
        // Another host, or plain http.
        #expect(!wall.matches(
            redirectFrom: feed, to: URL(string: "https://cdn.example.invalid/login/")))
        #expect(!wall.matches(
            redirectFrom: feed, to: URL(string: "http://www.example.invalid/login/")))
        #expect(!wall.matches(redirectFrom: nil, to: login))
    }

    /// Muse's declaration matches the redirect measured on 2026-09-27.
    @Test func museDeclaresItsMeasuredWall() throws {
        let feed = URL(string: "https://www.facebook.com/endo/release/appcast.xml?channel=production")
        let login = URL(string: "https://www.facebook.com/login/?next=https%3A%2F%2Fwww.facebook.com%2Fendo%2Frelease%2Fappcast.xml%3Fchannel%3Dproduction")
        #expect(SparkleFeedCatalog.loginWall(redirectFrom: feed, to: login) != nil)
    }
}
