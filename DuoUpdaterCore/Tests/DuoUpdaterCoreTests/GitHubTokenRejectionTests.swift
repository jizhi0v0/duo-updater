import Foundation
import Testing
@testable import DuoUpdaterCore

/// A token GitHub rejects (`401`) is dropped for the rest of the round, and the
/// request it failed is asked again without it — see `GitHubCredentials` and
/// `countedData`.
///
/// Driven through `countedData` against a `URLProtocol` stub, so nothing leaves
/// the process: the stub answers every request itself, `api.github.com` URL or
/// not. Each test gives its requests their own `GitHubCredentials`, so the
/// app's shared one, and other suites running alongside, never see these
/// rejections. The token is a placeholder that no server ever receives.
@Suite(.serialized)
struct GitHubTokenRejectionTests {
    /// Answers `statusWithToken` to a request carrying `Authorization` and
    /// `statusWithout` to one without, and remembers which each was.
    private final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var statusWithToken = 401
        nonisolated(unsafe) static var statusWithout = 200
        nonisolated(unsafe) private static var carried: [Bool] = []
        private static let lock = NSLock()

        static func reset(withToken: Int = 401, without: Int = 200) {
            lock.withLock {
                carried = []
                statusWithToken = withToken
                statusWithout = without
            }
        }

        /// Whether each request so far carried a token, in order.
        static var seen: [Bool] { lock.withLock { carried } }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            // An API URL that moved to another host — and kept its header, as a
            // session without `CrossHostCredentialStripper` lets it.
            if request.url?.host == "api.github.com", request.url?.path == "/moved",
               let target = URL(string: "https://example.com/moved") {
                var next = request
                next.url = target
                let moved = HTTPURLResponse(
                    url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                    headerFields: ["Location": target.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: moved)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let token = request.value(forHTTPHeaderField: "Authorization") != nil
            let status = Self.lock.withLock {
                Self.carried.append(token)
                return token ? Self.statusWithToken : Self.statusWithout
            }
            let body: String
            if status == 401 {
                body = #"{"message":"Bad credentials"}"#
            } else if request.url?.path.hasSuffix("/releases/latest") == true {
                body = #"{"tag_name":"v2.0.0","draft":false,"prerelease":false,"assets":[]}"#
            } else {
                body = #"[{"tag_name":"v2.0.0","draft":false,"prerelease":false,"assets":[]}]"#
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static let api = URL(string: "https://api.github.com/repos/zzfixture/app/releases/latest")!

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private static func request(_ url: URL = api, token: Bool = true) -> URLRequest {
        var request = URLRequest(url: url)
        if token { request.setValue("Bearer placeholder-not-a-token", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// The status `countedData` hands back, under `credentials`.
    private static func fetch(
        _ request: URLRequest, on session: URLSession, under credentials: GitHubCredentials,
        followsTokenRejection: Bool = true
    ) async throws -> Int {
        let (_, response) = try await GitHubCredentials.$current.withValue(credentials) {
            try await session.countedData(
                for: request, purpose: .versionCheck, followsTokenRejection: followsTokenRejection)
        }
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    /// One retry, without the token, and the caller gets the anonymous answer;
    /// the rest of the round goes without it from the start, until the next
    /// round tries the token again. Mutations: drop the retry; drop the
    /// stripping of later requests; drop `beginRound`'s clearing.
    @Test func aRejectedTokenIsDroppedForTheRestOfTheRound() async throws {
        Stub.reset()
        let session = Self.session()
        let credentials = GitHubCredentials()

        #expect(try await Self.fetch(Self.request(), on: session, under: credentials) == 200)
        #expect(Stub.seen == [true, false], "asked once with the token, then once without")
        #expect(credentials.isRejected)

        Stub.reset()
        #expect(try await Self.fetch(Self.request(), on: session, under: credentials) == 200)
        #expect(Stub.seen == [false], "the rest of the round sends no token")

        credentials.beginRound()
        Stub.reset()
        #expect(!credentials.isRejected)
        #expect(try await Self.fetch(Self.request(), on: session, under: credentials) == 200)
        #expect(Stub.seen == [true, false], "the next round sends the token again")
        #expect(credentials.isRejected)
    }

    /// Only a 401 from `api.github.com` to a request that carried a token. A
    /// 403 keeps the rate-limit rule, and a 401 elsewhere or without a token is
    /// an answer like any other. Mutations: drop the `Authorization` check; drop
    /// the answer's host check; accept 403.
    @Test func onlyATokenTheAPIRejected() async throws {
        let session = Self.session()

        Stub.reset(withToken: 401, without: 401)
        let anonymous = GitHubCredentials()
        #expect(try await Self.fetch(Self.request(token: false), on: session, under: anonymous) == 401)
        #expect(Stub.seen == [false])
        #expect(!anonymous.isRejected)

        Stub.reset(withToken: 401, without: 200)
        let elsewhere = GitHubCredentials()
        let other = URL(string: "https://example.com/repos/zzfixture/app/releases/latest")!
        #expect(try await Self.fetch(Self.request(other), on: session, under: elsewhere) == 401)
        #expect(Stub.seen == [true])
        #expect(!elsewhere.isRejected)

        // Sent to the API, answered by another host.
        Stub.reset(withToken: 401, without: 200)
        let moved = GitHubCredentials()
        let away = URL(string: "https://api.github.com/moved")!
        #expect(try await Self.fetch(Self.request(away), on: session, under: moved) == 401)
        #expect(Stub.seen == [true])
        #expect(!moved.isRejected)

        Stub.reset(withToken: 403, without: 200)
        let forbidden = GitHubCredentials()
        #expect(try await Self.fetch(Self.request(), on: session, under: forbidden) == 403)
        #expect(Stub.seen == [true])
        #expect(!forbidden.isRejected)
    }

    /// Another host's credential (Alcove's Bearer, a vendor feed's) is not
    /// GitHub's to drop, rejected token or not. Mutation: drop the request's
    /// host check.
    @Test func anotherHostsCredentialIsKept() async throws {
        Stub.reset(withToken: 200, without: 200)
        let session = Self.session()
        let credentials = GitHubCredentials()
        credentials.recordRejection(generation: credentials.generation)

        let other = URL(string: "https://example.com/feed")!
        #expect(try await Self.fetch(Self.request(other), on: session, under: credentials) == 200)
        #expect(Stub.seen == [true])
    }

    /// Settings verifying a pasted token: its 401 is the answer, not retried, and
    /// a rejection of the token in use does not strip it. Mutation: ignore
    /// `followsTokenRejection`.
    @Test func verifyingATokenIsLeftAlone() async throws {
        Stub.reset()
        let session = Self.session()
        let credentials = GitHubCredentials()
        credentials.recordRejection(generation: credentials.generation)

        let status = try await Self.fetch(
            Self.request(), on: session, under: credentials, followsTokenRejection: false)
        #expect(status == 401)
        #expect(Stub.seen == [true])
    }

    /// A change in Settings clears the rejection; the old round's requests keep
    /// going without the token it lost, and the new credentials send theirs.
    /// Mutations: `isRejected` true for any generation rejected; report every
    /// 401 rather than the first.
    @Test func aChangeClearsTheRejection() async throws {
        Stub.reset()
        let session = Self.session()
        let credentials = GitHubCredentials()
        let reported = Reports()
        credentials.onRejected { reported.add($0) }

        let old = credentials.generation
        _ = try await Self.fetch(Self.request(), on: session, under: credentials)
        #expect(credentials.isRejected)
        #expect(reported.all == [old])
        // Requests in flight together each get their 401; one report.
        credentials.recordRejection(generation: old)
        #expect(reported.all == [old])

        credentials.changed()
        #expect(!credentials.isRejected)
        Stub.reset()
        _ = try await GitHubCredentials.$pinnedGeneration.withValue(old) {
            try await Self.fetch(Self.request(), on: session, under: credentials)
        }
        // The old round's request went without the token it had already lost…
        #expect(Stub.seen == [false])
        #expect(!credentials.isRejected)

        // …and the new credentials send theirs.
        Stub.reset()
        _ = try await Self.fetch(Self.request(), on: session, under: credentials)
        #expect(Stub.seen == [true, false])
        #expect(credentials.isRejected)
        #expect(reported.all == [old, credentials.generation])
    }

    /// A 401 to the old credentials after a change: retried, but not a rejection
    /// of the new ones. Mutation: record against the current generation instead
    /// of the request's.
    @Test func aLateRejectionOfTheOldCredentialsIsNotTheNewOnes() async throws {
        Stub.reset()
        let session = Self.session()
        let credentials = GitHubCredentials()
        let reported = Reports()
        credentials.onRejected { reported.add($0) }
        let old = credentials.generation
        credentials.changed()

        let status = try await GitHubCredentials.$pinnedGeneration.withValue(old) {
            try await Self.fetch(Self.request(), on: session, under: credentials)
        }
        #expect(status == 200)
        #expect(Stub.seen == [true, false])
        #expect(!credentials.isRejected)
        #expect(reported.all.isEmpty)
    }

    /// An app row: the GitHub source's request was rejected, and the row gets
    /// the anonymous answer instead of "GitHub returned HTTP 401".
    @Test func aGitHubRowShowsTheAnonymousAnswer() async throws {
        Stub.reset()
        let rule = GitHubReleaseRule(
            bundleID: "com.zzfixture.rejected", owner: "zzfixture", repo: "app",
            versionPattern: #"^v([0-9.]+)$"#)
        let source = GitHubReleasesSource(
            rules: [rule], token: "placeholder-not-a-token", session: Self.session())
        let app = InstalledApp(
            name: "ZZFixture", bundleID: rule.bundleID, shortVersion: "1.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Rejected.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
        #expect(!FileManager.default.fileExists(atPath: app.path.path))
        let credentials = GitHubCredentials()

        let remote = try await GitHubCredentials.$current.withValue(credentials) {
            try await source.latestVersion(for: app)
        }
        #expect(remote?.shortVersion == "2.0.0")
        #expect(Stub.seen == [true, false])
        #expect(credentials.isRejected)
    }

    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var generations: [Int] = []
        func add(_ generation: Int) { lock.withLock { generations.append(generation) } }
        var all: [Int] { lock.withLock { generations } }
    }
}
