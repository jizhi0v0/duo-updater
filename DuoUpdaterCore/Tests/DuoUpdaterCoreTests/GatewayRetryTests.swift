import Testing
import Foundation
@testable import DuoUpdaterCore

/// A gateway 5xx (502/503/504) says an intermediary could not reach the origin —
/// it carries no verdict on the request, so the same bytes a moment later usually
/// work. These pin the *shape* of that one retry: which statuses earn it, that it
/// happens exactly once, and that nothing else changed.
@Suite(.serialized)
struct GatewayRetryTests {

    /// Serves a scripted list of statuses in order, recording every request it saw.
    /// The body is GitHub-release shaped and *versioned by attempt number*, so a
    /// test can prove which response the caller ended up with rather than merely
    /// that some 200 arrived.
    private final class ScriptedProtocol: URLProtocol, @unchecked Sendable {
        final class Script: @unchecked Sendable {
            private let lock = NSLock()
            private var queue: [Int] = []
            private var seen: [String] = []

            func load(_ statuses: [Int]) {
                lock.lock(); queue = statuses; seen = []; lock.unlock()
            }

            func next(method: String) -> (status: Int, attempt: Int) {
                lock.lock(); defer { lock.unlock() }
                seen.append(method)
                let status = queue.isEmpty ? 200 : queue.removeFirst()
                return (status, seen.count)
            }

            var requests: [String] { lock.lock(); defer { lock.unlock() }; return seen }
        }

        static let script = Script()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let (status, attempt) = Self.script.next(method: request.httpMethod ?? "GET")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(Self.body(attempt: attempt).utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        /// A minimal but real `/releases/latest` payload — `GitHubReleasesSource`
        /// parses this one for the end-to-end test, and the plain helper tests read
        /// the tag out of it as an attempt marker.
        static func body(attempt: Int) -> String {
            """
            {
              "tag_name": "v0.0.\(attempt)",
              "assets": [
                {
                  "name": "Example-0.0.\(attempt)-arm64.dmg",
                  "browser_download_url": "https://example.com/Example-0.0.\(attempt)-arm64.dmg",
                  "size": 42
                }
              ],
              "prerelease": false,
              "draft": false
            }
            """
        }
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static let url = URL(string: "https://example.com/feed.json")!

    /// Tests never wait the production 800 ms; the delay is a parameter for exactly
    /// this reason.
    private static let fastDelay: Duration = .milliseconds(1)

    private static func fetch(
        scripting statuses: [Int], method: String? = nil
    ) async throws -> (status: Int?, body: String, requests: [String]) {
        ScriptedProtocol.script.load(statuses)
        var request = URLRequest(url: url)
        if let method { request.httpMethod = method }
        let (data, response) = try await session().versionFeedData(
            for: request, label: "test", retryDelay: fastDelay)
        return (
            (response as? HTTPURLResponse)?.statusCode,
            String(decoding: data, as: UTF8.self),
            ScriptedProtocol.script.requests)
    }

    @Test(arguments: [502, 503, 504])
    func gatewayStatusIsRetriedOnceAndTheSecondAnswerWins(status: Int) async throws {
        let result = try await Self.fetch(scripting: [status, 200])
        #expect(result.status == 200)
        // Not just "a 200": the tag proves the caller got attempt 2, not a
        // cached or replayed first response.
        #expect(result.body.contains("\"tag_name\": \"v0.0.2\""))
        #expect(result.requests.count == 2)
    }

    /// "Once" is the whole contract. A wedged gateway must not turn one check into
    /// an open-ended retry loop across a 130-app fan-out.
    @Test func aPersistentGatewayFailureIsRetriedExactlyOnce() async throws {
        let result = try await Self.fetch(scripting: [504, 504, 200])
        #expect(result.status == 504)
        #expect(result.requests.count == 2)  // the scripted 200 is never reached
    }

    /// 500 is the origin answering and throwing — repeating it reproduces it, and a
    /// recipe whose feed 500s consistently should be *reported*, not smoothed over.
    @Test func plainServerErrorIsNotRetried() async throws {
        let result = try await Self.fetch(scripting: [500, 200])
        #expect(result.status == 500)
        #expect(result.requests.count == 1)
    }

    /// Retrying a rate limit spends the budget it is complaining about.
    @Test(arguments: [403, 429])
    func rateLimitIsNotRetried(status: Int) async throws {
        let result = try await Self.fetch(scripting: [status, 200])
        #expect(result.status == status)
        #expect(result.requests.count == 1)
    }

    @Test(arguments: [200, 304, 404])
    func settledStatusesCostExactlyOneRequest(status: Int) async throws {
        let result = try await Self.fetch(scripting: [status])
        #expect(result.status == status)
        #expect(result.requests.count == 1)
    }

    /// `VendorProbeSource` builds GET and POST probes through one code path, so the
    /// method guard lives in the helper rather than in each caller's head.
    @Test func aBodyCarryingMethodIsNeverRetried() async throws {
        let result = try await Self.fetch(scripting: [503, 200], method: "POST")
        #expect(result.status == 503)
        #expect(result.requests == ["POST"])
    }

    @Test func onlyGatewayStatusesAreEligible() {
        #expect(URLSession.retryableGatewayStatuses == [502, 503, 504])
    }

    /// Every other test injects a 1 ms delay, so without this the production
    /// constant is pinned by nothing: raising it to 30 s would keep the whole
    /// suite green while melting a 130-app fan-out.
    @Test func theProductionDelayIsPinned() {
        #expect(URLSession.gatewayRetryDelay == .milliseconds(800))
    }

    /// `.redirectFilename` recipes read the version from a HEAD's resolved URL, so
    /// HEAD is a real version-read path here, not just a permitted method.
    @Test func headIsRetriedLikeAnyOtherIdempotentRead() async throws {
        let result = try await Self.fetch(scripting: [503, 200], method: "HEAD")
        #expect(result.status == 200)
        #expect(result.requests == ["HEAD", "HEAD"])
    }

    /// Cancelling during the wait must not invent a failure shape no caller knows.
    /// `VendorProbeSource.transportFailure` renders a non-`URLError` through
    /// `NSError.code`, which would print a nonexistent "URLError 1"; cancelling a
    /// plain `data(for:)` has always yielded `URLError(.cancelled)`.
    @Test func cancellationDuringTheWaitSurfacesAsACancelledURLError() async throws {
        ScriptedProtocol.script.load([504, 200])
        let session = Self.session()
        let task = Task {
            try await session.versionFeedData(
                for: URLRequest(url: Self.url), label: "test", retryDelay: .seconds(30))
        }
        // Let the first attempt land and the sleep begin.
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()

        await #expect(throws: URLError.self) { try await task.value }
        do { _ = try await task.value }
        catch let error as URLError { #expect(error.code == .cancelled) }
        // The retry never went out.
        #expect(ScriptedProtocol.script.requests == ["GET"])
    }

    /// The reported case, end to end: Headlamp's check died because one
    /// `api.github.com` 504 was a terminal answer. Through the real source, the
    /// same 504 now resolves to a version.
    @Test func aGitHubGatewayFailureNoLongerStrandsTheCheck() async throws {
        ScriptedProtocol.script.load([504])   // then the stub's 200 for attempt 2
        let source = GitHubReleasesSource(rules: [], session: Self.session())
        let rule = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            versionPattern: #"^v([0-9.]+)$"#,
            installAssetPattern: #"^Example-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg)

        let outcome = await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false)

        // Before this change the 504 was terminal: one request, a thrown
        // `badStatus(504)`, and the row read "GitHub returned HTTP 504". Resolving
        // to `0.0.2` — the *second* attempt's tag — is the proof the retry happens
        // inside the source, not only in the helper's own unit tests.
        #expect(outcome.remote?.shortVersion == "0.0.2")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == "Example-0.0.2-arm64.dmg")
        #expect(outcome.failure == nil)
        #expect(ScriptedProtocol.script.requests == ["GET", "GET"])
    }
}
