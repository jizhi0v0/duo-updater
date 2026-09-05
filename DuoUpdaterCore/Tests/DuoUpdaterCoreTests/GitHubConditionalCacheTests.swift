import Testing
import Foundation
@testable import DuoUpdaterCore

/// `GitHubReleasesSource.fetchReleases` was measured (see `GitHubConditionalCache`'s
/// doc comment) to almost never get a `URLCache` revalidation for
/// `/releases/latest` and `/releases?per_page=N`: GitHub's `ETag` churns with
/// `assets[].download_count`, and a stale `If-None-Match` on the wire makes the
/// server ignore the `If-Modified-Since` next to it. These pin the self-maintained
/// validator store that replaces reliance on `URLCache` for those two endpoints:
/// which single validator header goes out, what it does with a 304, and what it
/// refuses to do when the 304 can't be trusted.
@Suite(.serialized)
struct GitHubConditionalCacheTests {

    /// Serves scripted (status, etag, lastModified, body) answers in order and
    /// records every request's two conditional headers and its cache policy, so
    /// a test can assert "how many times did the network actually get hit",
    /// "which validator did we send" and "did we keep `URLCache` out of it".
    private final class ScriptedProtocol: URLProtocol, @unchecked Sendable {
        struct Answer {
            let status: Int; let etag: String?; let lastModified: String?; let body: String
            init(status: Int, etag: String?, lastModified: String? = nil, body: String) {
                self.status = status; self.etag = etag; self.lastModified = lastModified; self.body = body
            }
        }
        struct Seen { let ifNoneMatch: String?; let ifModifiedSince: String?; let cachePolicy: URLRequest.CachePolicy }

        final class Script: @unchecked Sendable {
            private let lock = NSLock()
            private var queue: [Answer] = []
            private var seen: [Seen] = []

            func load(_ answers: [Answer]) {
                lock.lock(); queue = answers; seen = []; lock.unlock()
            }

            func next(_ request: URLRequest) -> Answer {
                lock.lock(); defer { lock.unlock() }
                seen.append(Seen(
                    ifNoneMatch: request.value(forHTTPHeaderField: "If-None-Match"),
                    ifModifiedSince: request.value(forHTTPHeaderField: "If-Modified-Since"),
                    cachePolicy: request.cachePolicy))
                return queue.isEmpty
                    ? Answer(status: 200, etag: nil, body: "{}") : queue.removeFirst()
            }

            var requestCount: Int { lock.lock(); defer { lock.unlock() }; return seen.count }
            var ifNoneMatchSent: [String?] { lock.lock(); defer { lock.unlock() }; return seen.map(\.ifNoneMatch) }
            var ifModifiedSinceSent: [String?] { lock.lock(); defer { lock.unlock() }; return seen.map(\.ifModifiedSince) }
            var cachePolicies: [URLRequest.CachePolicy] { lock.lock(); defer { lock.unlock() }; return seen.map(\.cachePolicy) }
        }

        static let script = Script()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let answer = Self.script.next(request)
            var headers: [String: String] = [:]
            if let etag = answer.etag { headers["ETag"] = etag }
            if let lastModified = answer.lastModified { headers["Last-Modified"] = lastModified }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: answer.status,
                httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedProtocol.self]
        // No URLCache at all — every test proves the SOURCE's own conditional
        // layer, not a lucky assist from the protocol cache.
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// A `/releases/latest` payload with one tag. `tag` is deliberately shaped so
    /// two different `versionPattern`s can extract two DIFFERENT version strings
    /// from the exact same bytes — see
    /// `aRulePatternChangeTakesEffectThroughA304NotACachedConclusion`.
    private static func body(tag: String) -> String {
        """
        {
          "tag_name": "\(tag)",
          "assets": [],
          "prerelease": false,
          "draft": false
        }
        """
    }

    private static func tempCache() -> GitHubConditionalCache {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-conditional-cache-tests-\(UUID().uuidString)")
        return GitHubConditionalCache(fileURL: dir.appendingPathComponent("cache.json"))
    }

    // MARK: - 1. Store raw body, re-parse on every 304 (never a cached conclusion)

    /// Mutation this pins: caching the RESOLVED version (or anything downstream
    /// of `versionPattern`) instead of the raw HTTP body. Two `GitHubReleasesSource`
    /// instances share one `GitHubConditionalCache` and the same slug, so the
    /// second request is answered 304 from the very same script — but the two
    /// instances use DIFFERENT `versionPattern`s against the identical tag
    /// `"v1.2.3"`. A correct implementation re-parses the stored bytes under
    /// whichever pattern is asking right now, so the two calls must disagree.
    /// An implementation that instead cached (or reused) a parsed conclusion tied
    /// to the first rule would answer "1.2.3" both times — this test goes red on
    /// that mutation (verified below).
    @Test func aRulePatternChangeTakesEffectThroughA304NotACachedConclusion() async throws {
        ScriptedProtocol.script.load([
            .init(status: 200, etag: "etag-1", body: Self.body(tag: "v1.2.3")),
            .init(status: 304, etag: nil, body: ""),
        ])
        let cache = Self.tempCache()
        let session = Self.session()

        let ruleOld = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            versionPattern: #"^v([0-9.]+)$"#)   // "v1.2.3" -> "1.2.3"
        let sourceOld = GitHubReleasesSource(
            rules: [ruleOld], token: "tok", session: session, validatorCache: cache)
        let first = await sourceOld.resolveDiagnostic(ruleOld)
        #expect(first.remote?.shortVersion == "1.2.3")
        #expect(ScriptedProtocol.script.requestCount == 1)

        // Same slug, same endpoint, same cached bytes — but a rule edit: only the
        // suffix after "v1." is the version now.
        let ruleNew = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            versionPattern: #"^v1\.([0-9.]+)$"#)   // "v1.2.3" -> "2.3"
        let sourceNew = GitHubReleasesSource(
            rules: [ruleNew], token: "tok", session: session, validatorCache: cache)
        let second = await sourceNew.resolveDiagnostic(ruleNew)

        // The request that went out was a 304 (belt and braces: proves this
        // exercised the conditional path, not a coincidental fresh 200).
        #expect(ScriptedProtocol.script.requestCount == 2)
        #expect(ScriptedProtocol.script.ifNoneMatchSent.last == "etag-1")
        // The answer reflects the NEW pattern, not the one that was cached under.
        #expect(second.remote?.shortVersion == "2.3")
        #expect(second.remote?.shortVersion != first.remote?.shortVersion)
    }

    /// A response with an `ETag` and no `Last-Modified` — the list endpoint's
    /// shape — is revalidated by `If-None-Match`, and the value sent is exactly
    /// the `ETag` the first 200 carried. Pins the wiring, independent of the
    /// pattern-change scenario above.
    @Test func theSecondRequestSendsTheEtagFromTheFirst200() async throws {
        ScriptedProtocol.script.load([
            .init(status: 200, etag: "\"abc123\"", body: Self.body(tag: "v9.9.9")),
            .init(status: 304, etag: nil, body: ""),
        ])
        let cache = Self.tempCache()
        let session = Self.session()
        let rule = GitHubReleaseRule(bundleID: "com.example.app", owner: "example", repo: "app")
        let source = GitHubReleasesSource(
            rules: [rule], token: "tok", session: session, validatorCache: cache)

        _ = await source.resolveDiagnostic(rule)
        _ = await source.resolveDiagnostic(rule)

        #expect(ScriptedProtocol.script.ifNoneMatchSent == [nil, "\"abc123\""])
        #expect(ScriptedProtocol.script.ifModifiedSinceSent == [nil, nil])
    }

    // MARK: - 1b. `Last-Modified` wins outright, and the `ETag` stays home

    /// Mutation this pins: sending `If-None-Match` alongside (or instead of)
    /// `If-Modified-Since` when the stored response had a `Last-Modified`.
    /// Measured on 2026-09-05 against `VSCodium/vscodium/releases/latest`: the
    /// `ETag` rotates every few minutes with `assets[].download_count`, and a
    /// request carrying the stale `ETag` *and* a valid `If-Modified-Since` gets
    /// a full 200 — GitHub evaluates `If-None-Match` first (RFC 7232 §6) and
    /// ignores the date. Only `If-Modified-Since` alone gets the 304. So the
    /// first 200 here carries BOTH headers, and the second request must carry
    /// exactly one: the date, verbatim.
    @Test func aLastModifiedIsRevalidatedByDateAloneNeverByTheEtagNextToIt() async throws {
        let lastModified = "Sat, 11 Jul 2026 21:54:57 GMT"
        ScriptedProtocol.script.load([
            .init(status: 200, etag: "W/\"churns-with-download-count\"", lastModified: lastModified,
                  body: Self.body(tag: "v1.2.3")),
            .init(status: 304, etag: nil, body: ""),
        ])
        let cache = Self.tempCache()
        let session = Self.session()
        let rule = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            versionPattern: #"^v([0-9.]+)$"#)
        let source = GitHubReleasesSource(
            rules: [rule], token: "tok", session: session, validatorCache: cache)

        let first = await source.resolveDiagnostic(rule)
        let second = await source.resolveDiagnostic(rule)

        #expect(ScriptedProtocol.script.requestCount == 2)
        #expect(ScriptedProtocol.script.ifModifiedSinceSent == [nil, lastModified])
        #expect(ScriptedProtocol.script.ifNoneMatchSent == [nil, nil])
        // And the 304 was served from the stored body, not read as "nothing".
        #expect(first.remote?.shortVersion == "1.2.3")
        #expect(second.remote?.shortVersion == "1.2.3")
    }

    /// Mutation this pins: leaving a validator-bearing request on
    /// `versionFeedCachePolicy` (`.reloadRevalidatingCacheData`). On the real
    /// `URLSession.updates` that lets `URLCache` add its own `If-None-Match`
    /// from the copy it holds of the last 200, and one stale `ETag` on the wire
    /// is enough to void the `If-Modified-Since` (see the previous test). The
    /// first, unconditional request keeps the feed policy — nothing about the
    /// "never answer a version feed from cache freshness" contract changes.
    @Test func aValidatorBearingRequestIgnoresTheLocalURLCache() async throws {
        ScriptedProtocol.script.load([
            .init(status: 200, etag: "e", lastModified: "Sat, 11 Jul 2026 21:54:57 GMT",
                  body: Self.body(tag: "v1.0.0")),
            .init(status: 304, etag: nil, body: ""),
        ])
        let cache = Self.tempCache()
        let session = Self.session()
        let rule = GitHubReleaseRule(bundleID: "com.example.app", owner: "example", repo: "app")
        let source = GitHubReleasesSource(
            rules: [rule], token: "tok", session: session, validatorCache: cache)

        _ = await source.resolveDiagnostic(rule)
        _ = await source.resolveDiagnostic(rule)

        #expect(ScriptedProtocol.script.cachePolicies
                == [URLRequest.versionFeedCachePolicy, .reloadIgnoringLocalCacheData])
    }

    /// A store file written before `lastModified` existed (entries with `etag`
    /// only) must still decode and still revalidate by `ETag` — a format change
    /// that silently emptied the store would cost one full fetch per endpoint
    /// with nothing to notice it by. Mutation this pins: making `Entry.etag` /
    /// `lastModified` non-optional, or renaming a key.
    @Test func aStoreFileFromBeforeLastModifiedStillDecodes() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-conditional-cache-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("cache.json")
        let endpoint = "https://api.github.com/repos/old/repo/releases/latest"
        let legacy = """
        {"\(endpoint)": {"etag": "\\"legacy\\"", "body": "\(Data("{}".utf8).base64EncodedString())",
                          "authFingerprint": "fp", "storedAt": 810280008.0}}
        """
        try Data(legacy.utf8).write(to: file)

        // The clock is pinned a minute after the file's `storedAt`: with the
        // real clock this test would have gone red on its own 24 hours after the
        // fixture was written (`maxAge`), which is not what it measures.
        let cache = GitHubConditionalCache(
            fileURL: file, now: { Date(timeIntervalSinceReferenceDate: 810280008 + 60) })
        let validator = await cache.validator(for: endpoint, authFingerprint: "fp")

        #expect(validator?.etag == "\"legacy\"")
        #expect(validator?.lastModified == nil)
        #expect(validator?.conditionalHeaders == ["If-None-Match": "\"legacy\""])
    }

    /// The LIST endpoint's 304 must be re-parsed as a list. Mutation this pins:
    /// hard-coding `list: false` (or `true`) where the stored body is decoded
    /// on a 304 — every other test scripts the list's second round as a 200,
    /// so that mutation stayed green while in production every list 304 would
    /// have decoded to zero rows and recorded a false miss. A prerelease rule
    /// that does not probe, so the full page is the only list endpoint it
    /// touches.
    @Test func aListEndpoint304IsServedFromTheStoredPage() async throws {
        let page = """
        [{"tag_name": "v2.0.0-beta.2", "assets": [], "prerelease": true, "draft": false, "published_at": "2026-09-02T00:00:00Z"},
         {"tag_name": "v2.0.0-beta.1", "assets": [], "prerelease": true, "draft": false, "published_at": "2026-09-01T00:00:00Z"}]
        """
        ScriptedProtocol.script.load([
            .init(status: 200, etag: "list-etag", body: page),
            .init(status: 304, etag: nil, body: ""),
        ])
        let cache = Self.tempCache()
        let session = Self.session()
        let rule = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            usePrereleases: true, versionPattern: #"^v([0-9.]+-beta\.[0-9]+)$"#,
            channel: .beta, probesNewestFirst: false)
        let source = GitHubReleasesSource(
            rules: [rule], token: "tok", session: session, validatorCache: cache)

        let first = await source.resolveDiagnostic(rule)
        let second = await source.resolveDiagnostic(rule)

        #expect(ScriptedProtocol.script.ifNoneMatchSent == [nil, "list-etag"])
        #expect(first.remote?.shortVersion == "2.0.0-beta.2")
        #expect(second.remote?.shortVersion == "2.0.0-beta.2")
        #expect(second.remote?.releaseHistory.count == 2)
        #expect(second.failure == nil)
    }

    // MARK: - 1c. A stored 200 is not revalidated forever

    /// Mutation this pins: dropping the `maxAge` check in `validator(for:)`.
    /// GitHub answers `If-Modified-Since` the RFC way (a date a day AFTER the
    /// release's `Last-Modified` is still a 304, measured 2026-09-05), so a
    /// `/latest` re-pointed at an OLDER release is "not modified since" too and
    /// would be served from the stored body until something newer appeared. An
    /// entry older than a day yields no validator, the next request goes out
    /// unconditional, and the fresh 200 restamps it.
    @Test func aStoredEntryOlderThanADayYieldsNoValidator() async throws {
        let clock = Clock()
        let cache = GitHubConditionalCache(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-conditional-cache-tests-\(UUID().uuidString)/cache.json"),
            now: { clock.now })
        let endpoint = "https://api.github.com/repos/example/app/releases/latest"
        await cache.store(endpoint: endpoint, authFingerprint: "fp",
                          etag: nil, lastModified: "Sat, 11 Jul 2026 21:54:57 GMT", body: Data("{}".utf8))

        clock.now = clock.now.addingTimeInterval(23 * 60 * 60)
        #expect(await cache.validator(for: endpoint, authFingerprint: "fp") != nil)
        clock.now = clock.now.addingTimeInterval(2 * 60 * 60)
        #expect(await cache.validator(for: endpoint, authFingerprint: "fp") == nil)
        // A fresh 200 restamps it.
        await cache.store(endpoint: endpoint, authFingerprint: "fp",
                          etag: nil, lastModified: "Sun, 06 Sep 2026 00:00:00 GMT", body: Data("{}".utf8))
        #expect(await cache.validator(for: endpoint, authFingerprint: "fp")?.lastModified
                == "Sun, 06 Sep 2026 00:00:00 GMT")
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now = Date()
        var now: Date {
            get { lock.lock(); defer { lock.unlock() }; return _now }
            set { lock.lock(); _now = newValue; lock.unlock() }
        }
    }

    // MARK: - 2. Failure retreats to an unconditional request, never "no update"

    /// Mutation this pins: treating an untrustable 304 (nothing cached to serve
    /// it from) as "no update" or as an error. Nothing was ever stored — the
    /// cache is empty — so the request cannot legitimately carry `If-None-Match`,
    /// yet the script answers 304 on the first call anyway (standing in for a
    /// corrupted/evicted store or a rogue intermediary). The source must not
    /// interpret that as "nothing changed": it must fall back to a *second*,
    /// unconditional request and return whatever that one says.
    @Test func aTrustlessOhThreeOhFourFallsBackToAnUnconditionalRequest() async throws {
        ScriptedProtocol.script.load([
            .init(status: 304, etag: nil, body: ""),
            .init(status: 200, etag: "etag-real", body: Self.body(tag: "v3.1.4")),
        ])
        let cache = Self.tempCache()   // empty — nothing was ever stored
        let session = Self.session()
        let rule = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            versionPattern: #"^v([0-9.]+)$"#)
        let source = GitHubReleasesSource(
            rules: [rule], token: "tok", session: session, validatorCache: cache)

        let outcome = await source.resolveDiagnostic(rule)

        // Not nil, not an error — the retry's real answer.
        #expect(outcome.remote?.shortVersion == "3.1.4")
        #expect(outcome.failure == nil)
        #expect(ScriptedProtocol.script.requestCount == 2)
        // Neither request could have legitimately carried a validator.
        #expect(ScriptedProtocol.script.ifNoneMatchSent == [nil, nil])
    }

    // MARK: - 3. Auth context changes invalidate the old validator

    /// Mutation this pins: keying the cache only by endpoint, so a validator
    /// fetched under one token is reused (as `If-None-Match`) for a DIFFERENT
    /// token. GitHub hands out different ETags to authenticated vs. anonymous
    /// requests for the same resource, so this would risk a spurious 304 that
    /// resurrects a body fetched under someone else's credential.
    @Test func aDifferentTokenNeverReusesTheOldValidator() async throws {
        ScriptedProtocol.script.load([
            .init(status: 200, etag: "etag-for-tokA", body: Self.body(tag: "v1.0.0")),
            .init(status: 200, etag: "etag-for-tokB", body: Self.body(tag: "v2.0.0")),
        ])
        let cache = Self.tempCache()
        let session = Self.session()
        let rule = GitHubReleaseRule(bundleID: "com.example.app", owner: "example", repo: "app")

        let sourceA = GitHubReleasesSource(
            rules: [rule], token: "tokA", session: session, validatorCache: cache)
        let first = await sourceA.resolveDiagnostic(rule)
        #expect(first.remote?.shortVersion == "1.0.0")

        let sourceB = GitHubReleasesSource(
            rules: [rule], token: "tokB", session: session, validatorCache: cache)
        let second = await sourceB.resolveDiagnostic(rule)

        // No validator sent for the different token — a real, unconditional
        // second request, not a 304.
        #expect(ScriptedProtocol.script.ifNoneMatchSent == [nil, nil])
        #expect(second.remote?.shortVersion == "2.0.0")
        #expect(ScriptedProtocol.script.requestCount == 2)
    }

    /// Going from a token to no token (or back) is the same hazard as two
    /// different tokens — `authFingerprint(nil)` must not collide with
    /// `authFingerprint(_:)` for any real token.
    @Test func authFingerprintDistinguishesAnonymousFromAnyToken() {
        let anon = GitHubConditionalCache.authFingerprint(nil)
        let tokA = GitHubConditionalCache.authFingerprint("tokA")
        let tokB = GitHubConditionalCache.authFingerprint("tokB")
        #expect(anon != tokA)
        #expect(tokA != tokB)
        // Deterministic, so re-fetching after a process restart still matches.
        #expect(tokA == GitHubConditionalCache.authFingerprint("tokA"))
        // Never the raw token — a disk-persisted store must not carry it.
        #expect(!anon.contains("tok"))
        #expect(!tokA.contains("tokA"))
    }

    // MARK: - 4. Bounded: pruning drops what the registry no longer asks for

    @Test func pruneDropsEndpointsOutsideTheKeptSet() async {
        let cache = Self.tempCache()
        await cache.store(
            endpoint: "https://api.github.com/repos/kept/repo/releases/latest",
            authFingerprint: "fp", etag: "e1", lastModified: nil, body: Data("{}".utf8))
        await cache.store(
            endpoint: "https://api.github.com/repos/retired/repo/releases/latest",
            authFingerprint: "fp", etag: "e2", lastModified: nil, body: Data("{}".utf8))

        await cache.prune(keeping: ["https://api.github.com/repos/kept/repo/releases/latest"])

        #expect(await cache.validator(
            for: "https://api.github.com/repos/kept/repo/releases/latest",
            authFingerprint: "fp") != nil)
        #expect(await cache.validator(
            for: "https://api.github.com/repos/retired/repo/releases/latest",
            authFingerprint: "fp") == nil)
    }

    // MARK: - 5. The tag lookup never participates

    /// `GitHubReleasesSource.fetchReleases` gates the conditional layer on
    /// `tag == nil` in three places (the lookup, and the two `store` call
    /// sites), and separately `validNonTagEndpoints` — what `prune(keeping:)`
    /// is run against — never contains a tag-shaped URL. Both mechanisms
    /// independently keep a tag entry out of the store, which is deliberate
    /// defense in depth (see that property's doc comment) but means the two
    /// need two different tests: mutating away only the `tag == nil` gates
    /// still gets cleaned up by `prune`, so it does NOT turn this specific
    /// end-to-end test red (verified: request/response shape is unchanged) —
    /// that mutation is instead caught by
    /// `validNonTagEndpointsNeverNamesATagShapedURL` below, which pins the
    /// *other* mechanism directly. This test pins the CURRENT, observable
    /// behaviour: the exact-tag lookup never carries `If-None-Match`, on
    /// either round.
    @Test func theExactTagLookupNeverSendsAValidator() async throws {
        ScriptedProtocol.script.load([
            // channelDiscoveryProbe: list fetch, then the exact-tag fetch.
            .init(status: 200, etag: "list-etag", body: """
            [{"tag_name": "v1.0.0", "assets": [], "prerelease": true, "draft": false}]
            """),
            .init(status: 200, etag: "tag-etag", body: """
            {"tag_name": "v1.0.0", "assets": [], "prerelease": true, "draft": false}
            """),
            // Second round: same two lookups again.
            .init(status: 200, etag: "list-etag", body: """
            [{"tag_name": "v1.0.0", "assets": [], "prerelease": true, "draft": false}]
            """),
            .init(status: 200, etag: "tag-etag", body: """
            {"tag_name": "v1.0.0", "assets": [], "prerelease": true, "draft": false}
            """),
        ])
        let cache = Self.tempCache()
        let session = Self.session()
        let rule = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            versionPattern: #"^v([0-9.]+)$"#,
            installedTagPrefix: "v", channel: .beta)
        let source = GitHubReleasesSource(
            rules: [rule], token: "tok", session: session, validatorCache: cache)

        _ = try await source.channelDiscoveryProbe(rule)
        _ = try await source.channelDiscoveryProbe(rule)

        // Four real requests. The LIST fetch (`releases?per_page=20`) is one of
        // the two registry-driven, non-tag endpoints — it IS eligible for the
        // conditional layer, and correctly carries the validator on its second
        // round (index 2). The exact-TAG fetch (index 1 and 3) is the one this
        // test is actually about: it must never carry `If-None-Match`, on
        // either round — that's the endpoint with no fixed, prunable key space.
        #expect(ScriptedProtocol.script.requestCount == 4)
        #expect(ScriptedProtocol.script.ifNoneMatchSent == [nil, nil, "list-etag", nil])
    }

    /// Direct pin on `validNonTagEndpoints` — the set `prune(keeping:)` is
    /// called with — never containing a `/releases/tags/…` URL for any rule,
    /// regardless of that rule's other settings. This is the mechanism that
    /// keeps a tag entry from surviving even if `fetchReleases`'s own
    /// `tag == nil` gates were ever mistakenly dropped (see the previous
    /// test's doc comment for why that mutation alone doesn't show up
    /// end-to-end). Mutation this pins: adding tag URLs into this set (e.g. "so
    /// pruning doesn't punish a proven install's re-check") — verified red
    /// below.
    @Test func validNonTagEndpointsNeverNamesATagShapedURL() {
        let rule = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            installedTagPrefix: "v", channel: .beta)
        let source = GitHubReleasesSource(rules: [rule])

        let endpoints = source.validNonTagEndpoints
        #expect(endpoints == [
            "https://api.github.com/repos/example/app/releases/latest",
            "https://api.github.com/repos/example/app/releases?per_page=20",
        ])
        #expect(!endpoints.contains { $0.contains("/releases/tags/") })
    }

    /// Mutation this pins: building the list URL in `validNonTagEndpoints` with
    /// a literal `per_page=20` instead of the rule's `listPageSize`. That is
    /// what the first draft did, after `listPageSize` had already made the page
    /// per-rule (#355): for every rule with a smaller page the list entry was
    /// stored and then pruned by the very same fetch, so its cache could never
    /// hit — with no error, no log line and every other test green. The two
    /// URLs must agree byte for byte with what `fetchReleases` requests.
    @Test func validNonTagEndpointsFollowEachRulesListPageSize() {
        let five = GitHubReleaseRule(
            bundleID: "com.example.five", owner: "example", repo: "five",
            usePrereleases: true, listPageSize: 5)
        let twenty = GitHubReleaseRule(
            bundleID: "com.example.twenty", owner: "example", repo: "twenty",
            usePrereleases: true)
        let source = GitHubReleasesSource(rules: [five, twenty])

        // Both rules are prerelease `.newest` rules, so each also keeps its
        // one-row probe page (`GitHubListProbeTests` pins when that third URL
        // is and is not present); the point here is the middle URL of each
        // triple carrying the rule's own page size.
        #expect(source.validNonTagEndpoints == [
            "https://api.github.com/repos/example/five/releases/latest",
            "https://api.github.com/repos/example/five/releases?per_page=5",
            "https://api.github.com/repos/example/five/releases?per_page=1",
            "https://api.github.com/repos/example/twenty/releases/latest",
            "https://api.github.com/repos/example/twenty/releases?per_page=20",
            "https://api.github.com/repos/example/twenty/releases?per_page=1",
        ])
    }
}
