import Foundation
import Testing
@testable import DuoUpdaterCore

/// Characterization of the existing Retry-After policy, kept separate from
/// invariants. These tests do not approve the policies named currentBehavior.
/// Vendor install loops have no injected sleeper: assert their observable
/// request order and configured schedule, with no wall-clock upper bound.
struct HTTPRetryAfterSimulationTests {
    private static func response(_ value: String?) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://retry-after.invalid/fixture")!, statusCode: 429,
            httpVersion: "HTTP/1.1", headerFields: value.map { ["retry-after": $0] })!
    }

    @Test(arguments: ["0", "1", "2", "3000", "0002", " 2 ", "\t2\t"])
    func safetyInvariantVendorParserAcceptsASCIIIntegerSeconds(value: String) {
        #expect(VendorProbeSource.retryAfterDelaySeconds(Self.response(value)) == Double(value.trimmingCharacters(in: .whitespaces)))
    }

    @Test(arguments: ["", " ", "-1", "+1", "1.5", "1e3", "NaN", "Infinity", "2, 3", "٢", "２"])
    func safetyInvariantVendorParserRejectsNonDelaySeconds(value: String) {
        #expect(VendorProbeSource.retryAfterDelaySeconds(Self.response(value)) == nil)
    }

    @Test func currentBehaviorHTTPDateIsIgnoredByTheVendorParser() {
        // Pure parser entry point only: this does not simulate a service clock
        // or claim to have tested the date form through a complete HTTP loop.
        let date = "Wed, 21 Oct 2099 07:28:00 GMT"
        #expect(VendorProbeSource.retryAfterDelaySeconds(Self.response(date)) == nil)
        #expect(VendorProbeSource.retryAfterDelaySeconds(Self.response(nil)) == nil)
    }

    private static func recipe(_ fixture: RetryAfterHTTPFixture) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.example.retryafter.\(fixture.id)", url: fixture.url("/feed"),
            mode: .responseBody, versionPattern: #""version":"([0-9.]+)""#,
            install: VendorInstallSpec(urlSource: .redirect(fixture.url("/install")), kind: .zip))
    }

    @Test func safetyInvariantLong429StopsRedirectResolutionAtTheFirstHEAD() async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", 429, headers: ["retry-after": "3000"])
        ])
        defer { fixture.close() }
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.remote?.vendorInstallerKind == nil)
        #expect(outcome.warnings.map(\.display) == ["installURLTransient: HTTP 429"])
        #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func currentBehaviorTwoSecond429StillAdmitsTheNextScheduledAttempt() async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", 429, headers: ["Retry-After": "2"]),
            .init("HEAD", "/install", 200, responsePath: "/Example-2.3.4.zip")
        ])
        defer { fixture.close() }
        let asked = VendorProbeSource.retryAfterDelaySeconds(Self.response("2"))
        #expect(asked == 2)
        #expect(VendorProbeSource.redirectRetryBackoff == [0, 0.7, 1.4])
        // This characterizes admission against the *total remaining* 2.1s,
        // although the next scheduled pause is only 0.7s. The test deliberately
        // does not make a flaky claim about elapsed runtime under scheduler load.
        #expect((asked ?? 0) > VendorProbeSource.redirectRetryBackoff[1])
        #expect((asked ?? .infinity) < VendorProbeSource.redirectRetryBackoff.dropFirst().reduce(0, +))
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == "Example-2.3.4.zip")
        #expect(outcome.remote?.vendorInstallerKind == .zip)
        #expect(outcome.warnings.isEmpty)
        #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install", "HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func currentBehaviorLong503RetryAfterDoesNotStopRedirectResolution() async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", 503, headers: ["Retry-After": "3000"]),
            .init("HEAD", "/install", 503, headers: ["Retry-After": "3000"]),
            .init("HEAD", "/install", 503, headers: ["Retry-After": "3000"])
        ])
        defer { fixture.close() }
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.remote?.vendorInstallerKind == nil)
        #expect(outcome.warnings.map(\.display) == ["installURLTransient: HTTP 503"])
        #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install", "HEAD /install", "HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: ["absent", "invalid"])
    func currentBehaviorMissingOrInvalid429DelayKeepsRedirectAttempts(value: String) async {
        let headers = value == "absent" ? [:] : ["Retry-After": "not-a-delay"]
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", 429, headers: headers),
            .init("HEAD", "/install", 429, headers: headers),
            .init("HEAD", "/install", 429, headers: headers)
        ])
        defer { fixture.close() }
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.warnings.map(\.display) == ["installURLTransient: HTTP 429"])
        #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install", "HEAD /install", "HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func currentBehaviorGatewayFeedHelperIgnores503RetryAfter() async throws {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 503, headers: ["Retry-After": "3000"], body: "first-503"),
            .init("GET", "/feed", 200, body: "second-response-marker")
        ])
        defer { fixture.close() }
        let (data, response) = try await fixture.session.versionFeedData(
            for: URLRequest(url: fixture.url("/feed")), label: "Retry-After simulation", retryDelay: .zero)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "second-response-marker")
        #expect(fixture.requests.map(\.line) == ["GET /feed", "GET /feed"])
        #expect(URLSession.gatewayRetryDelay == .milliseconds(800))
        #expect(fixture.unexpected.isEmpty)
    }

    /// A service's 429 closes the actual countedData gate. A fixed injected
    /// clock proves the deadline without sleeping, and the script proves that
    /// the refused request never reached URLSession. The token budget remains
    /// independent of the anonymous budget that was refused.
    @Test func safetyInvariantGitHub429PausesOnlyItsCredentialBeforeAnotherRequestIsSent() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let probe = #"{"resources":{"core":{"remaining":100,"reset":1800000600}}}"#
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/rate_limit", 200, body: probe),
            .init("GET", "/repos/simulation/app/releases/latest", 429,
                  headers: ["Retry-After": "120"], body: #"{"message":"secondary rate limit"}"#),
            .init("GET", "/rate_limit", 200, body: probe),
            .init("GET", "/repos/simulation/app/releases/latest", 200, body: "independent-token-body")
        ])
        defer { fixture.close() }
        let gate = GitHubRateLimitGate.Store(now: { now })
        let store = EventStore(fileURL: DuoStateDirectory.testProcessScratchRoot
            .appendingPathComponent(fixture.id).appendingPathComponent("events.sqlite"))
        let credentials = GitHubCredentials()
        let anonymous = URLRequest(url: URL(string: "https://api.github.com/repos/simulation/app/releases/latest")!)
        let first = try await GitHubCredentials.$current.withValue(credentials) {
            try await fixture.session.countedData(for: anonymous, purpose: .versionCheck, store: store, gate: gate)
        }
        #expect((first.1 as? HTTPURLResponse)?.statusCode == 429)
        #expect(String(decoding: first.0, as: UTF8.self).contains("secondary rate limit"))
        #expect(await gate.closure(.anonymous) == .init(
            until: now.addingTimeInterval(120), reason: .secondary(strike: 1)))
        do {
            _ = try await GitHubCredentials.$current.withValue(credentials) {
                try await fixture.session.countedData(for: anonymous, purpose: .versionCheck, store: store, gate: gate)
            }
            Issue.record("The anonymous request must be refused by the active 429 closure")
        } catch let refused as GitHubRateLimitGate.Refused {
            #expect(refused.credential == .anonymous)
            #expect(refused.closure.until == now.addingTimeInterval(120))
        }
        #expect(fixture.requests.map(\.line) == ["GET /rate_limit", "GET /repos/simulation/app/releases/latest"])
        var token = anonymous
        token.setValue("Bearer simulation-placeholder", forHTTPHeaderField: "Authorization")
        let independent = try await GitHubCredentials.$current.withValue(credentials) {
            try await fixture.session.countedData(for: token, purpose: .versionCheck, store: store, gate: gate)
        }
        #expect((independent.1 as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: independent.0, as: UTF8.self) == "independent-token-body")
        #expect(await gate.closure(.token) == nil)
        #expect(await gate.closure(.anonymous)?.until == now.addingTimeInterval(120))
        #expect(!credentials.isRejected)
        #expect(fixture.requests.map(\.authorization) == [nil, nil, "Bearer simulation-placeholder", "Bearer simulation-placeholder"])
        #expect(fixture.unexpected.isEmpty)
        await store.flush()
    }

    @Test func currentBehaviorReachabilityDoesNotApplyRedirectsLong429Guard() async {
        let fixture = RetryAfterHTTPFixture([
            .init("HEAD", "/install", 429, headers: ["Retry-After": "3000"]),
            .init("HEAD", "/install", 429, headers: ["Retry-After": "3000"]),
            .init("HEAD", "/install", 429, headers: ["Retry-After": "3000"])
        ])
        defer { fixture.close() }
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(
            fixture.url("/install"), spec: VendorInstallSpec(urlSource: .fixed(fixture.url("/install")), kind: .zip))
        #expect(result == .transient(status: 429))
        #expect(fixture.requests.map(\.line) == ["HEAD /install", "HEAD /install", "HEAD /install"])
        #expect(fixture.requests.allSatisfy { $0.range == nil })
        #expect(fixture.unexpected.isEmpty)
    }

    /// A terminal HEAD method refusal gets a range-read check, whereas a
    /// transient status keeps the HEAD loop. The second response is inspected;
    /// treating the HEAD's 405 as a deletion would fail this assertion.
    @Test func safetyInvariantReachabilityHEADRefusalUsesRangeGETAndInstallerHeaders() async {
        let fixture = RetryAfterHTTPFixture([
            .init("HEAD", "/install", 405),
            .init("GET", "/install", 206, body: "x")
        ])
        defer { fixture.close() }
        let url = fixture.url("/install")
        let spec = VendorInstallSpec(
            urlSource: .fixed(url), kind: .zip, requestHeaders: ["Referer": "https://vendor.invalid/downloads"])
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(url, spec: spec)
        #expect(result == .ok)
        #expect(fixture.requests.map(\.line) == ["HEAD /install", "GET /install"])
        #expect(fixture.requests.map(\.range) == [nil, "bytes=0-0"])
        #expect(fixture.requests.allSatisfy {
            $0.acceptEncoding == "identity" && $0.userAgent == Downloader.userAgent
                && $0.referer == "https://vendor.invalid/downloads"
                && $0.cachePolicy == URLRequest.versionFeedCachePolicy
        })
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantReachabilityBoth404MeansGoneWithoutMoreAttempts() async {
        let fixture = RetryAfterHTTPFixture([
            .init("HEAD", "/install", 404), .init("GET", "/install", 404)
        ])
        defer { fixture.close() }
        let url = fixture.url("/install")
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(
            url, spec: VendorInstallSpec(urlSource: .fixed(url), kind: .zip))
        #expect(result == .gone(status: 404))
        #expect(fixture.requests.map(\.line) == ["HEAD /install", "GET /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [416, 501])
    func safetyInvariantRangeRefusalIsTransientRatherThanAnArtifactDeletion(status: Int) async {
        let fixture = RetryAfterHTTPFixture((0..<3).flatMap { _ in [
            RetryAfterHTTPFixture.Answer("HEAD", "/install", 405),
            RetryAfterHTTPFixture.Answer("GET", "/install", status)
        ] })
        defer { fixture.close() }
        let url = fixture.url("/install")
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(
            url, spec: VendorInstallSpec(urlSource: .fixed(url), kind: .zip))
        #expect(result == .transient(status: status))
        #expect(fixture.requests.map(\.line) == Array(repeating: ["HEAD /install", "GET /install"], count: 3).flatMap { $0 })
        #expect(fixture.requests.filter { $0.method == "GET" }.allSatisfy { $0.range == "bytes=0-0" })
        #expect(fixture.unexpected.isEmpty)
    }
}

private final class RetryAfterHTTPFixture: @unchecked Sendable {
    struct Answer: Sendable {
        let method: String
        let path: String
        let status: Int
        let headers: [String: String]
        let body: String
        let responsePath: String?
        init(
            _ method: String, _ path: String, _ status: Int,
            headers: [String: String] = [:], body: String = "", responsePath: String? = nil
        ) {
            self.method = method; self.path = path; self.status = status
            self.headers = headers; self.body = body; self.responsePath = responsePath
        }
    }
    struct Seen: Sendable {
        let method: String
        let path: String
        let range: String?
        let acceptEncoding: String?
        let userAgent: String?
        let referer: String?
        let authorization: String?
        let cachePolicy: URLRequest.CachePolicy
        var line: String { "\(method) \(path)" }
    }
    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [Answer]
        private var seen: [Seen] = []
        private var failures: [String] = []
        init(_ queue: [Answer]) { self.queue = queue }
        func next(_ request: URLRequest) -> Answer? {
            lock.withLock { () -> Answer? in
                let method = request.httpMethod ?? "GET"
                let path = request.url?.path ?? "<no URL>"
                seen.append(Seen(
                    method: method, path: path, range: request.value(forHTTPHeaderField: "Range"),
                    acceptEncoding: request.value(forHTTPHeaderField: "Accept-Encoding"),
                    userAgent: request.value(forHTTPHeaderField: "User-Agent"),
                    referer: request.value(forHTTPHeaderField: "Referer"),
                    authorization: request.value(forHTTPHeaderField: "Authorization"), cachePolicy: request.cachePolicy))
                guard !queue.isEmpty else {
                    failures.append("Unplanned \(method) \(path)")
                    return nil
                }
                let answer = queue.removeFirst()
                guard answer.method == method, answer.path == path else {
                    failures.append("Expected \(answer.method) \(answer.path), received \(method) \(path)")
                    return nil
                }
                return answer
            }
        }
        var requests: [Seen] { lock.withLock { seen } }
        var unexpected: [String] { lock.withLock { failures } }
    }
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var scripts: [String: Script] = [:]
        func add(_ script: Script, id: String) { lock.withLock { scripts[id] = script } }
        func remove(_ id: String) { lock.withLock { scripts[id] = nil } }
        func script(for request: URLRequest) -> Script? {
            lock.withLock {
                if let id = request.value(forHTTPHeaderField: "X-HTTP-Simulation-ID"), let script = scripts[id] {
                    return script
                }
                let host = request.url?.host ?? ""
                return scripts.first { host == "\($0.key).invalid" }?.value
            }
        }
    }
    final class Stub: URLProtocol, @unchecked Sendable {
        static let registry = Registry()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let script = Self.registry.script(for: request), let answer = script.next(request),
                  let original = request.url,
                  let response = HTTPURLResponse(
                    url: answer.responsePath.map { URL(string: $0, relativeTo: original)!.absoluteURL } ?? original,
                    statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    let id = "retryaftersimulation" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let session: URLSession
    private let script: Script
    init(_ answers: [Answer]) {
        script = Script(answers)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        configuration.httpAdditionalHeaders = ["X-HTTP-Simulation-ID": id]
        session = URLSession(configuration: configuration)
        Stub.registry.add(script, id: id)
    }
    func url(_ path: String) -> URL { URL(string: "https://\(id).invalid\(path)")! }
    var requests: [Seen] { script.requests }
    var unexpected: [String] { script.unexpected }
    func close() {
        session.invalidateAndCancel()
        Stub.registry.remove(id)
    }
}
