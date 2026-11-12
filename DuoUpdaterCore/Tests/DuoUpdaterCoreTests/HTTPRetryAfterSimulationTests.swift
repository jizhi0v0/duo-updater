import Foundation
import Testing
@testable import DuoUpdaterCore

/// Retry-After invariants through production entry points. Long waits end the
/// current retry round. Clock-sensitive parsing uses an explicit date, and the
/// short-wait test checks a minimum delay without any wall-clock upper bound.
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

    @Test(arguments: ["", " ", "-1", "+1", "1.5", "1e3", "NaN", "Infinity", "2, 3", "٢", "２", "2\n"])
    func safetyInvariantVendorParserRejectsNonDelaySeconds(value: String) {
        #expect(VendorProbeSource.retryAfterDelaySeconds(Self.response(value)) == nil)
    }

    @Test(arguments: ["Sun, 06 Nov 1994 08:49:37 GMT", "Sunday, 06-Nov-94 08:49:37 GMT", "Sun Nov  6 08:49:37 1994"])
    func safetyInvariantAllHTTPDateFormsUseTheInjectedClock(value: String) {
        let before = Date(timeIntervalSince1970: 784_111_775)
        #expect(HTTPRetryAfter.delaySeconds(Self.response(value), now: before) == 2)
        #expect(!HTTPRetryAfter.permitsRetry(Self.response(value), after: .milliseconds(700), now: before))
        #expect(HTTPRetryAfter.permitsRetry(Self.response(value), after: .seconds(2), now: before))
        #expect(HTTPRetryAfter.delaySeconds(Self.response(value), now: before.addingTimeInterval(3)) == 0)
        #expect(VendorProbeSource.retryAfterDelaySeconds(Self.response(nil)) == nil)
    }

    @Test func safetyInvariantRFC850TwoDigitYearsUseTheFiftyYearBoundary() {
        // 2094-11-06 08:49:37 is more than 50 years after the first clock,
        // so "94" means 1994. One second later it is exactly 50 years away,
        // and means 2094. Weekdays are checked against the resolved year.
        let justOutside = Date(timeIntervalSince1970: 2_362_034_976)
        let onBoundary = justOutside.addingTimeInterval(1)
        let past = "Sunday, 06-Nov-94 08:49:37 GMT"
        let future = "Saturday, 06-Nov-94 08:49:37 GMT"
        #expect(HTTPRetryAfter.delaySeconds(Self.response(past), now: justOutside) == 0)
        #expect(HTTPRetryAfter.delaySeconds(Self.response(future), now: onBoundary)
            == 3_939_871_777 - onBoundary.timeIntervalSince1970)
        #expect(HTTPRetryAfter.delaySeconds(Self.response(past), now: onBoundary) == nil)
        // Crossing a century must not turn year 00 into invalid 2100-02-29
        // before the rule has selected the valid past date 2000-02-29.
        #expect(HTTPRetryAfter.delaySeconds(
            Self.response("Tuesday, 29-Feb-00 00:00:00 GMT"), now: Date(timeIntervalSince1970: 1_704_067_200)) == 0)
    }

    @Test(arguments: ["Mon, 06 Nov 1994 08:49:37 GMT", "Sun, 31 Feb 1994 08:49:37 GMT",
                      "Sun, 06 Nov 1994 24:49:37 GMT", "Sun, 06 Nov 1994 08:60:37 GMT",
                      "Sun, 06 Nov 1994 08:49:61 GMT", "Sun, 06 Nov 1994 08:49:37 +0000",
                      "Sun, 06 Nov 1994 08:49:37 UTC", "1994-11-06T08:49:37Z",
                      "Sun, 06 Nov 1994 08:49:37 GMT trailing", "Sun, 06 Nov 1994 08:49:37 GMT\n"])
    func safetyInvariantInvalidHTTPDatesDoNotAcquireRetrySemantics(value: String) {
        #expect(HTTPRetryAfter.delaySeconds(Self.response(value), now: Date(timeIntervalSince1970: 0)) == nil)
    }

    @Test func safetyInvariantDelaySecondsOverflowIsRejected() {
        #expect(HTTPRetryAfter.delaySeconds(Self.response(String(repeating: "9", count: 400))) == nil)
    }

    @Test func safetyInvariantAnHTTPLeapSecondDoesNotMakeTheRetryDeadlineEarlier() {
        #expect(HTTPRetryAfter.delaySeconds(
            Self.response("Sat, 31 Dec 2016 23:59:60 GMT"),
            now: Date(timeIntervalSince1970: 1_483_228_799)) == 1)
    }

    @Test(arguments: [429, 503], ["3000", "Sun, 06 Nov 1994 09:39:35 GMT"])
    func safetyInvariantFreshVendorSourcesHonorAFiftyMinuteWaitAcrossFiveMinuteScans(status: Int, header: String) async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", status, headers: ["Retry-After": header], body: #"{"version":"88.0.0"}"#),
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#)
        ])
        defer { fixture.close() }
        let clock = RetryAfterClock(Date(timeIntervalSince1970: 784_111_775))
        let store = HTTPRetryAfter.CooldownStore(now: { clock.now })
        let recipe = VendorProbeRecipe(
            bundleID: "com.example.cooldown.\(fixture.id)", url: fixture.url("/feed"),
            mode: .responseBody, versionPattern: #""version":"([0-9.]+)""#)
        await HTTPRetryAfter.$cooldowns.withValue(store) {
            let first = await VendorProbeSource(session: fixture.session).probeDiagnostic(recipe)
            #expect(first.failure == .httpStatus(status))
            #expect(first.remote == nil)
            #expect(fixture.requests.map(\.line) == ["GET /feed"])
            #expect(store.entryCount == 1)
            clock.advance(300)
            let second = await VendorProbeSource(session: fixture.session).probeDiagnostic(recipe)
            #expect(second.failure == .httpStatus(status))
            #expect(second.remote == nil)
            #expect(fixture.requests.map(\.line) == ["GET /feed"])
            clock.advance(2700)
            let expired = await VendorProbeSource(session: fixture.session).probeDiagnostic(recipe)
            #expect(expired.remote?.shortVersion == "2.3.4")
            #expect(fixture.requests.map(\.line) == ["GET /feed", "GET /feed"])
            #expect(store.entryCount == 0)
        }
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantRedirectCooldownSurvivesANewSourceAndExpiresWithoutBlockingTheFeed() async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", 429, headers: ["Retry-After": "3000"]),
            .init("GET", "/feed", 200, body: #"{"version":"2.3.5"}"#),
            .init("GET", "/feed", 200, body: #"{"version":"2.3.6"}"#),
            .init("HEAD", "/install", 200, responsePath: "/Example-2.3.6.zip")
        ])
        defer { fixture.close() }
        let clock = RetryAfterClock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = HTTPRetryAfter.CooldownStore(now: { clock.now })
        await HTTPRetryAfter.$cooldowns.withValue(store) {
            let first = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
            #expect(first.warnings == [.installURLTransient(status: 429)])
            clock.advance(300)
            let second = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
            #expect(second.remote?.shortVersion == "2.3.5")
            #expect(second.warnings == [.installURLTransient(status: 429)])
            #expect(fixture.requests.filter { $0.method == "HEAD" }.count == 1)
            clock.advance(2700)
            let expired = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
            #expect(expired.remote?.shortVersion == "2.3.6")
            #expect(expired.remote?.vendorInstallerKind == .zip)
            #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install", "GET /feed", "GET /feed", "HEAD /install"])
        }
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [false, true])
    func safetyInvariantReachabilityCooldownSkipsTheWholeNextProbeAndExpires(ranged: Bool) async {
        let answers: [RetryAfterHTTPFixture.Answer] = ranged ? [
            .init("HEAD", "/install", 405),
            .init("GET", "/install", 503, headers: ["Retry-After": "3000"]),
            .init("HEAD", "/install", 200)
        ] : [
            .init("HEAD", "/install", 503, headers: ["Retry-After": "3000"]),
            .init("HEAD", "/install", 200)
        ]
        let fixture = RetryAfterHTTPFixture(answers)
        defer { fixture.close() }
        let clock = RetryAfterClock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = HTTPRetryAfter.CooldownStore(now: { clock.now })
        let url = fixture.url("/install")
        let spec = VendorInstallSpec(urlSource: .fixed(url), kind: .zip)
        await HTTPRetryAfter.$cooldowns.withValue(store) {
            let first = await VendorProbeSource(session: fixture.session).installURLReachability(url, spec: spec)
            #expect(first == .transient(status: 503))
            let original = fixture.requests.map(\.line)
            #expect(original == (ranged ? ["HEAD /install", "GET /install"] : ["HEAD /install"]))
            clock.advance(300)
            let second = await VendorProbeSource(session: fixture.session).installURLReachability(url, spec: spec)
            #expect(second == .transient(status: 503))
            #expect(fixture.requests.map(\.line) == original)
            clock.advance(2700)
            let expired = await VendorProbeSource(session: fixture.session).installURLReachability(url, spec: spec)
            #expect(expired == .ok)
            #expect(fixture.requests.map(\.line) == original + ["HEAD /install"])
            #expect(store.entryCount == 0)
        }
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantCooldownIdentityExcludesChangingValidatorsTracingAndRange() async throws {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 429, headers: ["Retry-After": "3000"], body: "credential-a-failure"),
            .init("GET", "/feed", 200, body: "credential-b-answer"),
            .init("GET", "/other", 200, body: "other-endpoint-answer"),
            .init("HEAD", "/feed", 200),
            .init("GET", "/feed", 200, body: "other-query-answer"),
            .init("GET", "/feed", 200, body: "other-session-answer")
        ])
        defer { fixture.close() }
        let otherSession = URLSession(configuration: fixture.session.configuration)
        defer { otherSession.invalidateAndCancel() }
        let clock = RetryAfterClock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = HTTPRetryAfter.CooldownStore(now: { clock.now })
        var base = URLRequest(url: fixture.url("/feed"))
        base.setValue("Bearer placeholder-a", forHTTPHeaderField: "Authorization")
        try await HTTPRetryAfter.$cooldowns.withValue(store) {
            let first = try await fixture.session.versionFeedData(for: base, label: "credential A")
            #expect((first.1 as? HTTPURLResponse)?.statusCode == 429)
            #expect(String(decoding: first.0, as: UTF8.self) == "credential-a-failure")
            for field in ["If-None-Match", "If-Modified-Since", "X-Request-ID", "traceparent", "Range"] {
                var changed = base
                changed.setValue("new-\(field)", forHTTPHeaderField: field)
                let held = try await fixture.session.versionFeedData(for: changed, label: "same identity")
                #expect((held.1 as? HTTPURLResponse)?.statusCode == 429)
                #expect(held.0.isEmpty)
            }
            #expect(fixture.requests.count == 1)
            var credentialB = base
            credentialB.setValue("Bearer placeholder-b", forHTTPHeaderField: "Authorization")
            let b = try await fixture.session.versionFeedData(for: credentialB, label: "credential B")
            #expect(String(decoding: b.0, as: UTF8.self) == "credential-b-answer")
            var endpoint = base
            endpoint.url = fixture.url("/other")
            let other = try await fixture.session.versionFeedData(for: endpoint, label: "other endpoint")
            #expect(String(decoding: other.0, as: UTF8.self) == "other-endpoint-answer")
            var head = base
            head.httpMethod = "HEAD"
            let method = try await fixture.session.versionFeedData(for: head, label: "other method")
            #expect((method.1 as? HTTPURLResponse)?.statusCode == 200)
            var query = base
            query.url = fixture.url("/feed?channel=beta")
            let exact = try await fixture.session.versionFeedData(for: query, label: "other exact URL")
            #expect(String(decoding: exact.0, as: UTF8.self) == "other-query-answer")
            let independent = try await otherSession.versionFeedData(for: base, label: "other session")
            #expect(String(decoding: independent.0, as: UTF8.self) == "other-session-answer")
            let stillHeld = try await fixture.session.versionFeedData(for: base, label: "credential A remains held")
            #expect((stillHeld.1 as? HTTPURLResponse)?.statusCode == 429)
            #expect(fixture.requests.count == 6)
            #expect(store.entryCount == 1)
        }
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: ["Authorization", "Cookie", "Proxy-Authorization"])
    func safetyInvariantSessionCredentialsAndExplicitOverridesHaveMatchingCooldownIdentity(field: String) {
        let fixture = RetryAfterHTTPFixture([])
        defer { fixture.close() }
        let configuration = fixture.session.configuration
        var additional = configuration.httpAdditionalHeaders ?? [:]
        additional[field] = "placeholder-a"
        configuration.httpAdditionalHeaders = additional
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = HTTPRetryAfter.CooldownStore(now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let request = URLRequest(url: fixture.url("/feed"))
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil,
                                       headerFields: ["Retry-After": "3000"])!
        store.observe(response, for: request, in: session)
        var same = request
        same.setValue("placeholder-a", forHTTPHeaderField: field)
        var changed = request
        changed.setValue("placeholder-b", forHTTPHeaderField: field)
        #expect(store.failure(for: same, in: session)?.statusCode == 503)
        #expect(store.failure(for: changed, in: session) == nil)
    }

    @Test func safetyInvariantCooldownNeverCachesOrReplaysPOSTResponses() async throws {
        let fixture = RetryAfterHTTPFixture([
            .init("POST", "/feed", 503, headers: ["Retry-After": "3000"], body: "first-post"),
            .init("POST", "/feed", 503, headers: ["Retry-After": "3000"], body: "second-post")
        ])
        defer { fixture.close() }
        let store = HTTPRetryAfter.CooldownStore()
        var request = URLRequest(url: fixture.url("/feed"))
        request.httpMethod = "POST"
        try await HTTPRetryAfter.$cooldowns.withValue(store) {
            let first = try await fixture.session.versionFeedData(for: request, label: "first POST")
            let second = try await fixture.session.versionFeedData(for: request, label: "second explicit POST")
            #expect(String(decoding: first.0, as: UTF8.self) == "first-post")
            #expect(String(decoding: second.0, as: UTF8.self) == "second-post")
            #expect(fixture.requests.map(\.line) == ["POST /feed", "POST /feed"])
            #expect(store.entryCount == 0)
        }
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantGitHubAPIIsExcludedFromTheGenericCooldown() async throws {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/repos/simulation/app/releases/latest", 429, headers: ["Retry-After": "3000"], body: "first-api-answer"),
            .init("GET", "/repos/simulation/app/releases/latest", 200, body: "dedicated-gate-owns-admission")
        ])
        defer { fixture.close() }
        let request = URLRequest(url: URL(string: "https://api.github.com/repos/simulation/app/releases/latest")!)
        let credentials = GitHubCredentials()
        let store = HTTPRetryAfter.CooldownStore()
        try await HTTPRetryAfter.$cooldowns.withValue(store) {
            try await GitHubCredentials.$current.withValue(credentials) {
                let first = try await fixture.session.versionFeedData(for: request, label: "GitHub first")
                #expect((first.1 as? HTTPURLResponse)?.statusCode == 429)
                // No dedicated gate is activated in this isolated test; the
                // generic one must not change its admission/identity semantics.
                let second = try await fixture.session.versionFeedData(for: request, label: "GitHub next")
                #expect(String(decoding: second.0, as: UTF8.self) == "dedicated-gate-owns-admission")
                #expect(fixture.requests.count == 2)
                #expect(store.entryCount == 0)
            }
        }
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantHugeFiniteCooldownDoesNotConvertToAnOverflowingSleep() async throws {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 503, headers: ["Retry-After": "1" + String(repeating: "0", count: 308)], body: "original")
        ])
        defer { fixture.close() }
        let clock = RetryAfterClock(Date(timeIntervalSince1970: TimeInterval.greatestFiniteMagnitude / 2))
        let store = HTTPRetryAfter.CooldownStore(now: { clock.now })
        let request = URLRequest(url: fixture.url("/feed"))
        try await HTTPRetryAfter.$cooldowns.withValue(store) {
            let first = try await fixture.session.versionFeedData(for: request, label: "huge finite wait")
            #expect((first.1 as? HTTPURLResponse)?.statusCode == 503)
            #expect(String(decoding: first.0, as: UTF8.self) == "original")
            let second = try await fixture.session.versionFeedData(for: request, label: "still cooling")
            #expect((second.1 as? HTTPURLResponse)?.statusCode == 503)
            #expect(second.0.isEmpty)
            #expect(fixture.requests.count == 1)
            #expect(store.entryCount == 1)
        }
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantCancellationDuringCooldownSendsNoRequestAndKeepsCancellationShape() async throws {
        let fixture = RetryAfterHTTPFixture([.init("GET", "/feed", 503, headers: ["Retry-After": "3000"])])
        defer { fixture.close() }
        let store = HTTPRetryAfter.CooldownStore()
        let request = URLRequest(url: fixture.url("/feed"))
        try await HTTPRetryAfter.$cooldowns.withValue(store) {
            _ = try await fixture.session.versionFeedData(for: request, label: "establish cooldown")
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await fixture.session.versionFeedData(for: request, label: "cancelled cooldown read")
            }
            do {
                _ = try await task.value
                Issue.record("A standing cancellation must remain cancellation")
            } catch let error as URLError { #expect(error.code == .cancelled) }
            #expect(fixture.requests.count == 1)
        }
        #expect(fixture.unexpected.isEmpty)
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

    @Test func safetyInvariantTwoSecond429CannotUseThePointSevenSecondNextPause() async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", 429, headers: ["Retry-After": "2"])
        ])
        defer { fixture.close() }
        let asked = VendorProbeSource.retryAfterDelaySeconds(Self.response("2"))
        #expect(asked == 2)
        #expect(VendorProbeSource.redirectRetryBackoff == [0, 0.7, 1.4])
        // It fits the total 2.1s budget but exceeds the NEXT pause: no further
        // request is planned. Any early retry fails the fixture as well.
        #expect((asked ?? 0) > VendorProbeSource.redirectRetryBackoff[1])
        #expect((asked ?? .infinity) < VendorProbeSource.redirectRetryBackoff.dropFirst().reduce(0, +))
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.remote?.vendorInstallerKind == nil)
        #expect(outcome.warnings.map(\.display) == ["installURLTransient: HTTP 429"])
        #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [429, 500, 502, 503, 504], ["3000", "Wed, 21 Oct 2099 07:28:00 GMT"])
    func safetyInvariantLongRetryAfterStopsRedirectResolution(status: Int, header: String) async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", status, headers: ["Retry-After": header])
        ])
        defer { fixture.close() }
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.remote?.vendorInstallerKind == nil)
        #expect(outcome.warnings.map(\.display) == ["installURLTransient: HTTP \(status)"])
        #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: ["absent", "invalid"])
    func safetyInvariantMissingOrInvalid429DelayKeepsTheExistingAttemptBudget(value: String) async {
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

    @Test(arguments: [502, 503, 504], ["3000", "Wed, 21 Oct 2099 07:28:00 GMT"])
    func safetyInvariantGatewayFeedKeepsTheOriginalFailureWhenRetryAfterExceedsItsPause(status: Int, header: String) async throws {
        for method in ["GET", "HEAD", "POST"] {
            let body = method == "HEAD" ? "" : "original-failure-marker"
            let fixture = RetryAfterHTTPFixture([
                .init(method, "/feed", status, headers: ["Retry-After": header], body: body)
            ])
            defer { fixture.close() }
            var request = URLRequest(url: fixture.url("/feed"))
            request.httpMethod = method
            let (data, response) = try await fixture.session.versionFeedData(
                for: request, label: "Retry-After simulation")
            #expect((response as? HTTPURLResponse)?.statusCode == status)
            #expect(String(decoding: data, as: UTF8.self) == body)
            #expect(fixture.requests.map(\.line) == ["\(method) /feed"])
            #expect(URLSession.gatewayRetryDelay == .milliseconds(800))
            #expect(fixture.unexpected.isEmpty)
        }
    }

    @Test func safetyInvariantAnAllowedShortWaitDoesNotSendBeforeTheRequestedDelay() async throws {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 503, headers: ["Retry-After": "1"], body: "first"),
            .init("GET", "/feed", 200, body: "second-after-wait")
        ])
        defer { fixture.close() }
        let (data, response) = try await fixture.session.versionFeedData(
            for: URLRequest(url: fixture.url("/feed")), label: "short Retry-After", retryDelay: .seconds(1))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "second-after-wait")
        let requests = fixture.requests
        try #require(requests.count == 2)
        #expect(requests[0].started.duration(to: requests[1].started) >= .seconds(1))
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantRedirectCanHonorOneSecondAtItsLaterOnePointFourSecondPause() async throws {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", 502),
            .init("HEAD", "/install", 429, headers: ["Retry-After": "1"]),
            .init("HEAD", "/install", 200, responsePath: "/Example-2.3.4.zip")
        ])
        defer { fixture.close() }
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == "Example-2.3.4.zip")
        #expect(outcome.remote?.vendorInstallerKind == .zip)
        #expect(outcome.warnings.isEmpty)
        let requests = fixture.requests
        try #require(requests.count == 4)
        #expect(requests.map(\.line) == ["GET /feed", "HEAD /install", "HEAD /install", "HEAD /install"])
        #expect(requests[2].started.duration(to: requests[3].started) >= .seconds(1))
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantRetryAfterDoesNotGive429ANewGatewayRetry() async throws {
        let fixture = RetryAfterHTTPFixture([.init("GET", "/feed", 429, headers: ["Retry-After": "0"], body: "limited")])
        defer { fixture.close() }
        let result = try await fixture.session.versionFeedData(
            for: URLRequest(url: fixture.url("/feed")), label: "429 remains terminal", retryDelay: .zero)
        #expect((result.1 as? HTTPURLResponse)?.statusCode == 429)
        #expect(String(decoding: result.0, as: UTF8.self) == "limited")
        #expect(fixture.requests.map(\.line) == ["GET /feed"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantTheLastGatewayAnswerDoesNotEarnAnotherAttempt() async throws {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 502, body: "first"),
            .init("GET", "/feed", 503, headers: ["Retry-After": "3000"], body: "second-failure")
        ])
        defer { fixture.close() }
        let result = try await fixture.session.versionFeedData(
            for: URLRequest(url: fixture.url("/feed")), label: "last gateway answer", retryDelay: .zero)
        #expect((result.1 as? HTTPURLResponse)?.statusCode == 503)
        #expect(String(decoding: result.0, as: UTF8.self) == "second-failure")
        #expect(fixture.requests.map(\.line) == ["GET /feed", "GET /feed"])
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

    @Test(arguments: [429, 500, 502, 503, 504], ["3000", "Wed, 21 Oct 2099 07:28:00 GMT"])
    func safetyInvariantReachabilityHEADStopsWhenRetryAfterExceedsItsPause(status: Int, header: String) async {
        let fixture = RetryAfterHTTPFixture([
            .init("HEAD", "/install", status, headers: ["Retry-After": header])
        ])
        defer { fixture.close() }
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(
            fixture.url("/install"), spec: VendorInstallSpec(urlSource: .fixed(fixture.url("/install")), kind: .zip))
        #expect(result == .transient(status: status))
        #expect(fixture.requests.map(\.line) == ["HEAD /install"])
        #expect(fixture.requests.allSatisfy { $0.range == nil })
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [429, 500, 502, 503, 504], ["2", "Wed, 21 Oct 2099 07:28:00 GMT"])
    func safetyInvariantRangeGETStopsWhenRetryAfterExceedsTheNextPause(status: Int, header: String) async {
        let fixture = RetryAfterHTTPFixture([
            .init("HEAD", "/install", 405),
            .init("GET", "/install", status, headers: ["Retry-After": header])
        ])
        defer { fixture.close() }
        let url = fixture.url("/install")
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(
            url, spec: VendorInstallSpec(urlSource: .fixed(url), kind: .zip))
        #expect(result == .transient(status: status))
        #expect(fixture.requests.map(\.line) == ["HEAD /install", "GET /install"])
        #expect(fixture.requests.last?.range == "bytes=0-0")
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantAMethodFallbackDoesNotBypassHEADRetryAfter() async {
        let fixture = RetryAfterHTTPFixture([.init("HEAD", "/install", 405, headers: ["Retry-After": "1"])])
        defer { fixture.close() }
        let url = fixture.url("/install")
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(
            url, spec: VendorInstallSpec(urlSource: .fixed(url), kind: .zip))
        #expect(result == .transient(status: 405))
        #expect(fixture.requests.map(\.line) == ["HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [416, 501, 511, 599, 701])
    func safetyInvariantCapabilityAndUnknownServerStatusesDoNotEarnHEADRetries(status: Int) async {
        let fixture = RetryAfterHTTPFixture([.init("HEAD", "/install", status)])
        defer { fixture.close() }
        let url = fixture.url("/install")
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(
            url, spec: VendorInstallSpec(urlSource: .fixed(url), kind: .zip))
        #expect(result == .transient(status: status))
        #expect(fixture.requests.map(\.line) == ["HEAD /install"])
        #expect(!VendorProbeSource.isTransientStatus(status))
        #expect(fixture.unexpected.isEmpty)
    }

    @Test(arguments: [501, 511, 599, 701])
    func safetyInvariantRedirectServerCapabilityFailureRemainsUncertainWithoutRetry(status: Int) async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", status)
        ])
        defer { fixture.close() }
        let outcome = await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture))
        #expect(outcome.remote?.shortVersion == "2.3.4")
        #expect(outcome.remote?.vendorInstallerKind == nil)
        #expect(outcome.warnings.map(\.display) == ["installURLTransient: HTTP \(status)"])
        #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantCancellationStopsRedirectResolutionBeforeAnotherHEAD() async {
        let fixture = RetryAfterHTTPFixture([
            .init("GET", "/feed", 200, body: #"{"version":"2.3.4"}"#),
            .init("HEAD", "/install", 503)
        ])
        defer { fixture.close() }
        let task = Task { await VendorProbeSource(session: fixture.session).probeDiagnostic(Self.recipe(fixture)) }
        await fixture.waitUntilCompleted(2)
        task.cancel()
        _ = await task.value
        #expect(fixture.requests.map(\.line) == ["GET /feed", "HEAD /install"])
        #expect(fixture.unexpected.isEmpty)
    }

    @Test func safetyInvariantCancellationStopsReachabilityBeforeAnotherRequest() async {
        let fixture = RetryAfterHTTPFixture([.init("HEAD", "/install", 503)])
        defer { fixture.close() }
        let url = fixture.url("/install")
        let task = Task {
            await VendorProbeSource(session: fixture.session).installURLReachability(
                url, spec: VendorInstallSpec(urlSource: .fixed(url), kind: .zip))
        }
        await fixture.waitUntilCompleted(1)
        task.cancel()
        let result = await task.value
        guard case .transient = result else { Issue.record("Cancellation must leave reachability uncertain"); return }
        #expect(fixture.requests.map(\.line) == ["HEAD /install"])
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

    @Test(arguments: [416, 501, 511, 599, 701])
    func safetyInvariantRangeRefusalIsTransientRatherThanAnArtifactDeletion(status: Int) async {
        let fixture = RetryAfterHTTPFixture([
            RetryAfterHTTPFixture.Answer("HEAD", "/install", 405),
            RetryAfterHTTPFixture.Answer("GET", "/install", status)
        ])
        defer { fixture.close() }
        let url = fixture.url("/install")
        let result = await VendorProbeSource(session: fixture.session).installURLReachability(
            url, spec: VendorInstallSpec(urlSource: .fixed(url), kind: .zip))
        #expect(result == .transient(status: status))
        #expect(fixture.requests.map(\.line) == ["HEAD /install", "GET /install"])
        #expect(fixture.requests.filter { $0.method == "GET" }.allSatisfy { $0.range == "bytes=0-0" })
        #expect(fixture.unexpected.isEmpty)
    }
}

private final class RetryAfterClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
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
        let started: ContinuousClock.Instant
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
        private var completed = 0
        private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        init(_ queue: [Answer]) { self.queue = queue }
        func next(_ request: URLRequest) -> Answer? {
            lock.withLock { () -> Answer? in
                let method = request.httpMethod ?? "GET"
                let path = request.url?.path ?? "<no URL>"
                seen.append(Seen(
                    started: ContinuousClock.now, method: method, path: path, range: request.value(forHTTPHeaderField: "Range"),
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
        func completedResponse() {
            lock.withLock {
                completed += 1
                let ready = waiters.filter { $0.count <= completed }
                waiters.removeAll { $0.count <= completed }
                for waiter in ready { waiter.continuation.resume() }
            }
        }
        func waitUntilCompleted(_ count: Int) async {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if completed >= count { continuation.resume() }
                    else { waiters.append((count, continuation)) }
                }
            }
        }
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
            script.completedResponse()
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
    func waitUntilCompleted(_ count: Int) async { await script.waitUntilCompleted(count) }
    func close() {
        session.invalidateAndCancel()
        Stub.registry.remove(id)
    }
}
