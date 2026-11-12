import Foundation
import Testing
@testable import DuoUpdaterCore

/// In-process HTTP simulations through the production helper and sources.
/// Each case owns its session, script and credentials. No script defaults to 200.
/// Source APIs do not expose an EventStore argument: their counted requests still
/// use EventStore.shared, which the test host relocates to process scratch state.
struct HTTPVersionSourceSimulationTests {
    private static func release(_ version: String) -> String {
        #"{"tag_name":"v\#(version)","draft":false,"prerelease":false,"assets":[]}"#
    }

    private static func rule(_ fixture: VersionHTTPFixture) -> GitHubReleaseRule {
        GitHubReleaseRule(
            bundleID: "com.example.http.\(fixture.id)", owner: fixture.id, repo: "app",
            versionPattern: #"^v([0-9.]+)$"#)
    }

    private static func app(_ rule: GitHubReleaseRule) -> InstalledApp {
        InstalledApp(
            name: "HTTP Simulation", bundleID: rule.bundleID,
            shortVersion: "1.0.0", buildVersion: nil,
            path: DuoStateDirectory.testProcessScratchRoot
                .appendingPathComponent("\(rule.bundleID).app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    private static func vendorRecipe(
        _ fixture: VersionHTTPFixture,
        transient: Bool = false,
        post: Bool = false
    ) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.example.http.\(fixture.id)", url: fixture.url("/feed"),
            mode: .responseBody, versionPattern: #""version":"([0-9.]+)""#,
            transientBodyPattern: transient ? #""error":"temporary""# : nil,
            requestBody: post ? .init(json: #"{"client":"simulation"}"#) : nil,
            requestHeaders: ["X-Simulation-Request": fixture.id])
    }

    /// The fallback policy for statuses outside the three gateway codes is the
    /// original response. The extra scripted answer proves no hidden retry used it.
    /// Registry snapshot: IANA HTTP Status Codes, updated 2025-09-15
    /// (https://www.iana.org/assignments/http-status-codes). Includes every
    /// registered terminal 2xx–5xx code, the unused 306/418 and obsolete 510,
    /// plus 499/599/701 as unknown-code representatives. Informational 1xx
    /// responses are not terminal responses; this fixture makes no claim about
    /// their protocol handling.
    @Test(arguments: [200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                      300, 301, 302, 303, 304, 305, 306, 307, 308,
                      400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410,
                      411, 412, 413, 414, 415, 416, 417, 418, 421, 422, 423,
                      424, 425, 426, 428, 429, 431, 451, 499,
                      500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511,
                      599, 701])
    func safetyInvariantHelperHasABoundedStatusPolicy(status: Int) async throws {
        let first = status == 204 ? "" : "first-\(status)"
        let fixture = VersionHTTPFixture([
            .init(status, body: first), .init(206, body: "second-206")
        ])
        defer { fixture.close() }
        var request = URLRequest(url: fixture.url("/feed"))
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue(fixture.id, forHTTPHeaderField: "X-Simulation-Request")
        let tally = GatewayRetry.Tally()
        let (data, response) = try await GitHubCredentials.$current.withValue(fixture.credentials) {
            try await GatewayRetry.$tally.withValue(tally) {
                try await fixture.session.versionFeedData(
                    for: request, label: "HTTP simulation", retryDelay: .zero)
            }
        }
        let retries = [502, 503, 504].contains(status)
        #expect((response as? HTTPURLResponse)?.statusCode == (retries ? 206 : status))
        #expect(String(decoding: data, as: UTF8.self) == (retries ? "second-206" : first))
        #expect(fixture.requests.count == (retries ? 2 : 1))
        #expect(tally.count == (retries ? 1 : 0))
        #expect(fixture.requests.allSatisfy {
            $0.method == "GET" && $0.marker == fixture.id
                && $0.cachePolicy == URLRequest.versionFeedCachePolicy
        })
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"])
    func safetyInvariantGatewayAndBodyEnvelopeShareOneMethodGuard(method: String) async throws {
        let fixture = VersionHTTPFixture([
            .init(503, body: "first-gateway"),
            .init(200, body: #"{"error":"temporary"}"#),
            .init(200, body: #"{"version":"99.0.0"}"#)
        ])
        defer { fixture.close() }
        var request = URLRequest(url: fixture.url("/feed"))
        request.httpMethod = method
        if method != "GET" && method != "HEAD" { request.httpBody = Data("fixed-request".utf8) }
        let (data, response) = try await fixture.session.versionFeedData(
            for: request, label: "HTTP method simulation", retryDelay: .zero,
            retryableBody: { String(decoding: $0, as: UTF8.self).contains("temporary") })
        let retries = method == "GET" || method == "HEAD"
        #expect((response as? HTTPURLResponse)?.statusCode == (retries ? 200 : 503))
        #expect(fixture.requests.map(\.method) == Array(repeating: method, count: retries ? 2 : 1))
        // A gateway retry's second body cannot earn a third attempt.
        if retries && method == "GET" {
            #expect(String(decoding: data, as: UTF8.self) == #"{"error":"temporary"}"#)
        }
        if !retries { #expect(fixture.requests.first?.body == Data("fixed-request".utf8)) }
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [200, 201, 206])
    func safetyInvariantGitHubParsesAValidSuccessPayload(status: Int) async throws {
        let fixture = VersionHTTPFixture([.init(status, body: Self.release("2.3.4"))])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let source = GitHubReleasesSource(rules: [rule], session: fixture.session)
        let remote = try await GitHubCredentials.$current.withValue(fixture.credentials) {
            try await source.latestVersion(for: Self.app(rule))
        }
        #expect(remote?.shortVersion == "2.3.4")
        #expect(fixture.requests.map(\.path) == ["/repos/\(fixture.id)/app/releases/latest"])
        #expect(fixture.requests.first?.accept == "application/vnd.github+json")
        #expect(fixture.requests.first?.cachePolicy == URLRequest.versionFeedCachePolicy)
        #expect(fixture.unexpected.isEmpty)
        await RecipeHealth.shared.forget(id: rule.recipeID, source: source.name)
    }

    @Test func currentBehaviorGitHub200ErrorBodyIsAParseMissWithoutAnotherRequest() async {
        let fixture = VersionHTTPFixture([
            .init(200, body: #"{"message":"upstream temporarily unavailable"}"#),
            .init(200, body: Self.release("9.9.9"))
        ])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let source = GitHubReleasesSource(rules: [rule], session: fixture.session)
        let outcome = await GitHubCredentials.$current.withValue(fixture.credentials) {
            await source.resolveDiagnostic(rule)
        }
        #expect(outcome.remote == nil)
        guard case .versionPatternNoMatch = outcome.failure else {
            Issue.record("Expected a parse miss for the synthetic 200 error body, got \(String(describing: outcome.failure))")
            return
        }
        #expect(fixture.requests.count == 1)
        #expect(fixture.unexpected.isEmpty)
        await RecipeHealth.shared.forget(id: rule.recipeID, source: source.name)
    }

    /// URLProtocol delivers a terminal 3xx here; this tests source semantics
    /// after URLSession, not URLSession's redirect-hop implementation.
    @Test(arguments: [301, 302, 303, 307, 308, 500, 501, 511, 599, 701])
    func safetyInvariantGitHubDoesNotParseTerminalFailureBodiesAsReleases(status: Int) async {
        let fixture = VersionHTTPFixture([.init(status, body: Self.release("99.0.0"))])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let source = GitHubReleasesSource(rules: [rule], session: fixture.session)
        let outcome = await GitHubCredentials.$current.withValue(fixture.credentials) {
            await source.resolveDiagnostic(rule)
        }
        #expect(outcome.remote == nil)
        #expect(outcome.failure == .httpStatus(status))
        #expect(fixture.requests.count == 1)
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [502, 503, 504])
    func safetyInvariantGitHubUsesTheRetriedReleaseBody(status: Int) async throws {
        let fixture = VersionHTTPFixture([
            .init(status, body: Self.release("88.0.0")),
            .init(200, body: Self.release("2.3.4"))
        ])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let source = GitHubReleasesSource(rules: [rule], session: fixture.session)
        let remote = try await GitHubCredentials.$current.withValue(fixture.credentials) {
            try await source.latestVersion(for: Self.app(rule))
        }
        #expect(remote?.shortVersion == "2.3.4")
        #expect(fixture.requests.map(\.method) == ["GET", "GET"])
        #expect(Set(fixture.requests.map(\.path)).count == 1)
        #expect(fixture.unexpected.isEmpty)
        await RecipeHealth.shared.forget(id: rule.recipeID, source: source.name)
    }

    /// countedData owns the token fallback, versionFeedData owns the gateway
    /// retry. Composition must keep the rejected token off attempt three.
    @Test func safetyInvariantTokenRejectionThenGatewayUsesAnonymousRecoveryBody() async throws {
        let fixture = VersionHTTPFixture([
            .init(401, body: #"{"message":"Bad credentials"}"#),
            .init(503, body: Self.release("88.0.0")),
            .init(200, body: Self.release("2.3.4"))
        ])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let source = GitHubReleasesSource(
            rules: [rule], token: "simulation-placeholder", session: fixture.session)
        let remote = try await GitHubCredentials.$current.withValue(fixture.credentials) {
            try await source.latestVersion(for: Self.app(rule))
        }
        #expect(remote?.shortVersion == "2.3.4")
        #expect(fixture.requests.map(\.authorization) == ["Bearer simulation-placeholder", nil, nil])
        #expect(fixture.credentials.isRejected)
        #expect(fixture.requests.count == 3)
        #expect(fixture.unexpected.isEmpty)
        await RecipeHealth.shared.forget(id: rule.recipeID, source: source.name)
    }

    @Test(arguments: ["17", "0", "absent"])
    func currentBehaviorGitHub403SeparatesPermissionAndRateLimit(remaining: String) async throws {
        let headers = remaining == "absent" ? [:] : ["X-RateLimit-Remaining": remaining]
        let fixture = VersionHTTPFixture([.init(403, headers: headers, body: "forbidden")])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let source = GitHubReleasesSource(
            rules: [rule], token: "simulation-placeholder", session: fixture.session)
        do {
            _ = try await GitHubCredentials.$current.withValue(fixture.credentials) {
                try await source.latestVersion(for: Self.app(rule))
            }
            Issue.record("403 must remain an error")
        } catch let error as GitHubReleasesSource.GitHubError {
            #expect(error.statusCode == 403)
            switch error {
            case .badStatus: #expect(remaining == "17")
            case .rateLimited: #expect(remaining != "17")
            }
        }
        #expect(fixture.requests.count == 1)
        #expect(!fixture.credentials.isRejected)
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantGitHub429DoesNotUseGatewayRetryOrDiscardToken() async throws {
        let fixture = VersionHTTPFixture([
            .init(429, headers: ["Retry-After": "2", "X-RateLimit-Remaining": "17"], body: "limited")
        ])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let source = GitHubReleasesSource(
            rules: [rule], token: "simulation-placeholder", session: fixture.session)
        do {
            _ = try await GitHubCredentials.$current.withValue(fixture.credentials) {
                try await source.latestVersion(for: Self.app(rule))
            }
            Issue.record("429 must remain a rate-limit error")
        } catch let error as GitHubReleasesSource.GitHubError {
            guard case .rateLimited(429) = error else {
                Issue.record("Wrong 429 classification: \(error)")
                return
            }
        }
        #expect(fixture.requests.count == 1)
        #expect(!fixture.credentials.isRejected)
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantTag404FallsBackButLatest404Fails() async throws {
        let fixture = VersionHTTPFixture([
            .init(404, body: #"{"message":"tag not published"}"#),
            .init(200, body: Self.release("2.3.4")),
            .init(404, body: #"{"message":"repository not found"}"#)
        ])
        defer { fixture.close() }
        let stable = Self.rule(fixture)
        let beta = GitHubReleaseRule(
            bundleID: stable.bundleID, owner: fixture.id, repo: "app", usePrereleases: true,
            versionPattern: #"^v([0-9.]+)$"#, installedTagPrefix: "v", channel: .beta)
        let discovering = GitHubReleasesSource(rules: [stable, beta], session: fixture.session)
        let source = GitHubReleasesSource(rules: [stable], session: fixture.session)
        let remote = try await GitHubCredentials.$current.withValue(fixture.credentials) {
            try await discovering.latestVersion(for: Self.app(stable))
        }
        #expect(remote?.shortVersion == "2.3.4")
        #expect(remote?.releaseChannel == .stable)
        let failed = await GitHubCredentials.$current.withValue(fixture.credentials) {
            await source.resolveDiagnostic(stable)
        }
        #expect(failed.failure == .httpStatus(404))
        #expect(fixture.requests.map(\.path) == [
            "/repos/\(fixture.id)/app/releases/tags/v1.0.0",
            "/repos/\(fixture.id)/app/releases/latest",
            "/repos/\(fixture.id)/app/releases/latest"
        ])
        #expect(fixture.unexpected.isEmpty)
        await RecipeHealth.shared.forget(id: stable.recipeID, source: source.name)
    }

    @Test func safetyInvariantCached304ReparsesBodyAfterAGatewayRetry() async throws {
        let fixture = VersionHTTPFixture([
            .init(200, headers: ["ETag": "simulation-v1"], body: Self.release("2.3.4")),
            .init(503, body: Self.release("88.0.0")),
            .init(304, body: "")
        ])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let cache = GitHubConditionalCache(fileURL: fixture.scratch.appendingPathComponent("validators.json"))
        let source = GitHubReleasesSource(rules: [rule], session: fixture.session, validatorCache: cache)
        let first = await GitHubCredentials.$current.withValue(fixture.credentials) {
            await source.resolveDiagnostic(rule)
        }
        // Same HTTP bytes, a new interpretation. The 304 cannot be treated as a
        // cached RemoteVersion; the production parser must execute again.
        let reinterpreted = GitHubReleaseRule(
            bundleID: rule.bundleID, owner: fixture.id, repo: "app", versionPattern: #"^v2\.([0-9.]+)$"#)
        let next = GitHubReleasesSource(
            rules: [reinterpreted], session: fixture.session, validatorCache: cache)
        let second = await GitHubCredentials.$current.withValue(fixture.credentials) {
            await next.resolveDiagnostic(reinterpreted)
        }
        #expect(first.remote?.shortVersion == "2.3.4")
        #expect(second.remote?.shortVersion == "3.4")
        #expect(fixture.requests.map(\.ifNoneMatch) == [nil, "simulation-v1", "simulation-v1"])
        #expect(fixture.requests.map(\.cachePolicy) == [
            URLRequest.versionFeedCachePolicy, .reloadIgnoringLocalCacheData, .reloadIgnoringLocalCacheData
        ])
        #expect(fixture.unexpected.isEmpty)
        await RecipeHealth.shared.forget(id: rule.recipeID, source: source.name)
    }

    @Test func safetyInvariantUncached304FetchesFreshBodyAndKeepsGatewayRetryBounded() async {
        let fixture = VersionHTTPFixture([
            .init(304, body: ""),
            .init(502, body: Self.release("88.0.0")),
            .init(200, body: Self.release("2.3.4"))
        ])
        defer { fixture.close() }
        let rule = Self.rule(fixture)
        let cache = GitHubConditionalCache(fileURL: fixture.scratch.appendingPathComponent("validators.json"))
        let source = GitHubReleasesSource(rules: [rule], session: fixture.session, validatorCache: cache)
        let outcome = await GitHubCredentials.$current.withValue(fixture.credentials) {
            await source.resolveDiagnostic(rule)
        }
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(fixture.requests.count == 3)
        #expect(fixture.requests.allSatisfy { $0.ifNoneMatch == nil && $0.ifModifiedSince == nil })
        #expect(fixture.unexpected.isEmpty)
        await RecipeHealth.shared.forget(id: rule.recipeID, source: source.name)
    }

    @Test func safetyInvariantDeclaredVendorEnvelopeUsesTheSecondBody() async {
        let fixture = VersionHTTPFixture([
            .init(200, body: #"{"error":"temporary"}"#),
            .init(200, body: #"{"version":"2.3.4"}"#)
        ])
        defer { fixture.close() }
        let recipe = Self.vendorRecipe(fixture, transient: true)
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(recipe)
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(fixture.requests.map(\.marker) == [fixture.id, fixture.id])
        #expect(fixture.requests.map(\.method) == ["GET", "GET"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [200, 503])
    func safetyInvariantVendorPOSTKeepsItsBodyAndIsNeverRepeated(status: Int) async {
        let fixture = VersionHTTPFixture([
            .init(status, body: #"{"error":"temporary"}"#),
            .init(200, body: #"{"version":"99.0.0"}"#)
        ])
        defer { fixture.close() }
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(
            Self.vendorRecipe(fixture, transient: true, post: true))
        #expect(outcome.remote == nil)
        if status == 503 { #expect(outcome.failure == .httpStatus(503)) }
        else {
            guard case .vendorErrorEnvelope = outcome.failure else {
                Issue.record("A 200 envelope must remain a vendor-envelope failure after the POST guard")
                return
            }
        }
        #expect(fixture.requests.map(\.method) == ["POST"])
        #expect(fixture.requests.first?.body == Data(#"{"client":"simulation"}"#.utf8))
        #expect(fixture.requests.first?.contentType == "application/json")
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantOrdinaryVendor200ParseFailureDoesNotBecomeAnOutageRetry() async {
        let fixture = VersionHTTPFixture([
            .init(200, body: #"{"message":"no version field"}"#),
            .init(200, body: #"{"version":"99.0.0"}"#)
        ])
        defer { fixture.close() }
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.vendorRecipe(fixture))
        #expect(outcome.remote == nil)
        guard case .versionPatternNoMatch = outcome.failure else {
            Issue.record("Undeclared error bodies must remain parse failures")
            return
        }
        #expect(fixture.requests.count == 1)
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantVendorHEADParsesTheRetriedResponseURL() async {
        let fixture = VersionHTTPFixture([
            .init(504, body: ""),
            .init(200, body: "", responsePath: "/Example-2.3.4.dmg")
        ])
        defer { fixture.close() }
        let recipe = VendorProbeRecipe(
            bundleID: "com.example.http.\(fixture.id)", url: fixture.url("/latest"),
            mode: .redirectFilename, versionPattern: #"Example-([0-9.]+)\.dmg"#)
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(recipe)
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == "Example-2.3.4.dmg")
        #expect(fixture.requests.map(\.method) == ["HEAD", "HEAD"])
        #expect(fixture.unexpected.isEmpty)
    }
}

/// UUID-keyed scripts allow the suite's cases to run concurrently without a
/// singleton response queue. A session intercepts every URL, including mistakes;
/// an unknown fixture or an exhausted script fails instead of reaching a server.
private final class VersionHTTPFixture: @unchecked Sendable {
    struct Answer: Sendable {
        let status: Int
        let headers: [String: String]
        let body: String
        let responsePath: String?
        init(_ status: Int, headers: [String: String] = [:], body: String, responsePath: String? = nil) {
            self.status = status; self.headers = headers; self.body = body; self.responsePath = responsePath
        }
    }
    struct Seen: Sendable {
        let method: String
        let path: String
        let marker: String?
        let authorization: String?
        let accept: String?
        let contentType: String?
        let ifNoneMatch: String?
        let ifModifiedSince: String?
        let cachePolicy: URLRequest.CachePolicy
        let body: Data?
    }
    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [Answer]
        private var seen: [Seen] = []
        private var failures: [String] = []
        init(_ answers: [Answer]) { self.answers = answers }
        func next(_ request: URLRequest) -> Answer? {
            let body = Self.body(of: request)
            return lock.withLock { () -> Answer? in
                seen.append(Seen(
                    method: request.httpMethod ?? "GET", path: request.url?.path ?? "<no URL>",
                    marker: request.value(forHTTPHeaderField: "X-Simulation-Request"),
                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                    accept: request.value(forHTTPHeaderField: "Accept"),
                    contentType: request.value(forHTTPHeaderField: "Content-Type"),
                    ifNoneMatch: request.value(forHTTPHeaderField: "If-None-Match"),
                    ifModifiedSince: request.value(forHTTPHeaderField: "If-Modified-Since"),
                    cachePolicy: request.cachePolicy, body: body))
                guard !answers.isEmpty else {
                    failures.append("Unplanned \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<no URL>")")
                    return nil
                }
                return answers.removeFirst()
            }
        }
        private static func body(of request: URLRequest) -> Data? {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return nil }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
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
                let url = request.url?.absoluteString ?? ""
                return scripts.first { url.contains($0.key) }?.value
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

    let id = "httpsimulation" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let credentials = GitHubCredentials()
    let scratch: URL
    let session: URLSession
    private let script: Script
    init(_ answers: [Answer]) {
        script = Script(answers)
        scratch = DuoStateDirectory.testProcessScratchRoot.appendingPathComponent(id, isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
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
