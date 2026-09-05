import Testing
import Foundation
@testable import DuoUpdaterCore

/// A `usePrereleases` rule with `.newest` scope opens with a page of ONE
/// release and only pays for its full `listPageSize` page when that one row
/// cannot answer (#358). The list endpoint cannot be revalidated cheaply — no
/// `Last-Modified`, an `ETag` that churns with download counters — so the page
/// size is the only lever, and the newest row is the whole page almost every
/// round. These pin which URL goes out first, when the full page is paid for,
/// when it is deliberately NOT paid for, and which rules never probe at all.
@Suite(.serialized)
struct GitHubListProbeTests {

    /// Answers by URL string (query included), so a test states what each page
    /// size returns and then reads back the exact sequence of URLs requested.
    private final class ByURLProtocol: URLProtocol, @unchecked Sendable {
        struct Answer { let body: String; let etag: String? }
        final class Script: @unchecked Sendable {
            private let lock = NSLock()
            private var answers: [String: Answer] = [:]
            private var requested: [String] = []
            func load(_ table: [String: Answer]) { lock.lock(); answers = table; requested = []; lock.unlock() }
            func answer(for url: String) -> Answer? {
                lock.lock(); defer { lock.unlock() }
                requested.append(url)
                return answers[url]
            }
            var urls: [String] { lock.lock(); defer { lock.unlock() }; return requested }
        }
        static let script = Script()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!.absoluteString
            let answer = Self.script.answer(for: url)
            var headers: [String: String] = [:]
            if let etag = answer?.etag { headers["ETag"] = etag }
            // A request that presents the answer's own ETag gets the real thing:
            // a 304 with an empty body, exactly what GitHub sends.
            let notModified = answer?.etag != nil
                && request.value(forHTTPHeaderField: "If-None-Match") == answer?.etag
            let response = HTTPURLResponse(
                url: request.url!, statusCode: answer == nil ? 404 : (notModified ? 304 : 200),
                httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data((notModified ? "" : (answer?.body ?? "{}")).utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ByURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private static func release(_ tag: String, assets: [String] = ["App-arm64.zip"]) -> String {
        let assetJSON = assets.map {
            #"{"name": "\#($0)", "browser_download_url": "https://example.com/\#($0)", "size": 10}"#
        }.joined(separator: ",")
        return """
        {"tag_name": "\(tag)", "assets": [\(assetJSON)], "prerelease": true, "draft": false,
         "published_at": "2026-09-05T00:00:00Z", "html_url": "https://github.com/example/app/releases/tag/\(tag)"}
        """
    }
    private static func page(_ releases: [String]) -> String { "[" + releases.joined(separator: ",") + "]" }

    private static let slug = "example/app"
    private static let probeURL = "https://api.github.com/repos/\(slug)/releases?per_page=1"
    private static let fullURL = "https://api.github.com/repos/\(slug)/releases?per_page=5"
    private static let latestURL = "https://api.github.com/repos/\(slug)/releases/latest"

    /// A prerelease rule whose full page is five rows.
    private static func rule(
        probes: Bool = true, scope: GitHubCandidateScope = .newest, assetPattern: String? = #"\.zip$"#
    ) -> GitHubReleaseRule {
        GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app",
            usePrereleases: true, listPageSize: 5,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-beta\.[0-9]+)?)$"#,
            candidateScope: scope,
            installAssetPattern: assetPattern, installerKind: assetPattern == nil ? nil : .zip,
            channel: .beta, probesNewestFirst: probes)
    }

    private static func tempCache() -> GitHubConditionalCache {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-list-probe-tests-\(UUID().uuidString)")
        return GitHubConditionalCache(fileURL: dir.appendingPathComponent("cache.json"))
    }

    // MARK: - The probe answers, and nothing else is fetched

    /// Mutation this pins: dropping the probe (always fetching the full page).
    /// With no validator store wired in there is nothing to seed, so the very
    /// first request is the one-row page — and when that row matches the rule
    /// and carries the asset, it is the only request.
    @Test func aProbingRuleOpensWithOneRowAndStopsThere() async throws {
        ByURLProtocol.script.load([
            Self.probeURL: .init(body: Self.page([Self.release("v2.0.0-beta.3")]), etag: nil),
            Self.fullURL: .init(body: Self.page([Self.release("v2.0.0-beta.3"), Self.release("v2.0.0-beta.2")]), etag: nil),
        ])
        let source = GitHubReleasesSource(rules: [Self.rule()], session: Self.session())

        let outcome = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote?.shortVersion == "2.0.0-beta.3")
        #expect(ByURLProtocol.script.urls == [Self.probeURL])
    }

    // MARK: - The probe cannot answer, so the full page is paid for

    /// Mutation this pins: treating a probe miss as the rule's answer (Bitwarden's
    /// shape — the newest row is a `web-v…` tag the pattern rejects). The full
    /// page must be fetched, and the answer must come from it. Also pins that
    /// the two pages are requested in that order and nothing else is.
    @Test func aProbeThatCannotAnswerPaysForTheFullPage() async throws {
        ByURLProtocol.script.load([
            Self.probeURL: .init(body: Self.page([Self.release("web-v9.9.9")]), etag: nil),
            Self.fullURL: .init(body: Self.page([
                Self.release("web-v9.9.9"), Self.release("v1.5.0-beta.1"), Self.release("v1.4.0"),
            ]), etag: nil),
        ])
        let source = GitHubReleasesSource(rules: [Self.rule()], session: Self.session())

        let outcome = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote?.shortVersion == "1.5.0-beta.1")
        #expect(outcome.failure == nil)
        #expect(ByURLProtocol.script.urls == [Self.probeURL, Self.fullURL])
    }

    /// The same, for the other way a newest row fails to answer: it matches the
    /// version pattern but ships no asset the install pattern accepts (a
    /// platform-partial release). The full page has the real one below it.
    @Test func aProbeWithoutTheMacOSAssetPaysForTheFullPage() async throws {
        ByURLProtocol.script.load([
            Self.probeURL: .init(body: Self.page([Self.release("v3.0.0", assets: ["App.apk"])]), etag: nil),
            Self.fullURL: .init(body: Self.page([
                Self.release("v3.0.0", assets: ["App.apk"]), Self.release("v2.9.0"),
            ]), etag: nil),
        ])
        let source = GitHubReleasesSource(rules: [Self.rule()], session: Self.session())

        let outcome = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote?.shortVersion == "2.9.0")
        #expect(ByURLProtocol.script.urls == [Self.probeURL, Self.fullURL])
    }

    // MARK: - A probe that IS the answer, even though it offers nothing

    /// Mutation this pins: falling back whenever the probe yields no remote. A
    /// newest row that only ships the other architecture is the rule's answer
    /// — the walk stops on that row on the full page too — so paying for the
    /// full page would buy the same nothing at ten times the bytes.
    @Test func aProbeWhoseNewestRowIsArchIncompatibleDoesNotFallBack() async throws {
        ByURLProtocol.script.load([
            Self.probeURL: .init(body: Self.page([Self.release("v4.0.0", assets: ["App-x86_64.zip"])]), etag: nil),
            Self.fullURL: .init(body: Self.page([
                Self.release("v4.0.0", assets: ["App-x86_64.zip"]), Self.release("v3.9.0"),
            ]), etag: nil),
        ])
        let source = GitHubReleasesSource(rules: [Self.rule()], session: Self.session())

        let outcome = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote == nil)
        #expect(ByURLProtocol.script.urls == [Self.probeURL])
    }

    // MARK: - With a validator store, the full page is fetched once to seed history

    /// Mutation this pins: probing from the first round even when a store is
    /// wired in (the release history would then be seeded from one row), or
    /// never probing once one is (the saving would only exist in tests). The
    /// first resolve must fetch the full page; the second, with that page's
    /// memo now in the store, must open with the probe and stop there.
    @Test func aWiredStoreSeedsTheFullPageOnceThenProbes() async throws {
        ByURLProtocol.script.load([
            Self.probeURL: .init(body: Self.page([Self.release("v2.0.0-beta.3")]), etag: "p"),
            Self.fullURL: .init(body: Self.page([Self.release("v2.0.0-beta.3"), Self.release("v2.0.0-beta.2")]), etag: "f"),
        ])
        let source = GitHubReleasesSource(
            rules: [Self.rule()], session: Self.session(), validatorCache: Self.tempCache())

        let first = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)
        let second = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)

        #expect(first.remote?.shortVersion == "2.0.0-beta.3")
        #expect(second.remote?.shortVersion == "2.0.0-beta.3")
        #expect(ByURLProtocol.script.urls == [Self.fullURL, Self.probeURL])
        // The seeding round carried the whole page's history; the probe round
        // carries one row — the timeline keeps what the first round recorded.
        #expect(first.remote?.releaseHistory.count == 2)
        #expect(second.remote?.releaseHistory.count == 1)
    }

    /// The probe page has its own validator, and its 304 must be re-parsed as a
    /// LIST of one — a probe decoded as a single object would yield zero rows,
    /// fall back to the full page, and quietly undo the saving on exactly the
    /// rounds it exists for. Round three presents the probe's ETag and gets a
    /// 304; the answer must still be the stored row, with no full-page fetch.
    @Test func aProbe304IsServedFromTheStoredRow() async throws {
        ByURLProtocol.script.load([
            Self.probeURL: .init(body: Self.page([Self.release("v2.0.0-beta.3")]), etag: "p"),
            Self.fullURL: .init(body: Self.page([Self.release("v2.0.0-beta.3"), Self.release("v2.0.0-beta.2")]), etag: "f"),
        ])
        let source = GitHubReleasesSource(
            rules: [Self.rule()], session: Self.session(), validatorCache: Self.tempCache())

        _ = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)
        _ = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)
        let third = await source.resolveDiagnostic(Self.rule(), preferring: .arm64, allowingIntelTranslation: false)

        #expect(third.remote?.shortVersion == "2.0.0-beta.3")
        #expect(third.failure == nil)
        #expect(ByURLProtocol.script.urls == [Self.fullURL, Self.probeURL, Self.probeURL])
    }

    /// Mutation this pins: `recordingMisses: true` on the probe. A probe that
    /// cannot answer is not evidence about the recipe — the release it wants may
    /// sit below the newest row — so after a probe miss that the full page then
    /// answers, the recipe's health must show no miss at all, not a miss that a
    /// later success happens to outrank.
    @Test func aProbeMissLeavesNoMarkOnRecipeHealth() async throws {
        let rule = GitHubReleaseRule(
            bundleID: "com.example.health", owner: "probe-health", repo: "repo",
            usePrereleases: true, listPageSize: 5,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-beta\.[0-9]+)?)$"#,
            installAssetPattern: #"\.zip$"#, installerKind: .zip, channel: .beta)
        let probe = "https://api.github.com/repos/probe-health/repo/releases?per_page=1"
        let full = "https://api.github.com/repos/probe-health/repo/releases?per_page=5"
        ByURLProtocol.script.load([
            probe: .init(body: Self.page([Self.release("web-v9.9.9")]), etag: nil),
            full: .init(body: Self.page([Self.release("web-v9.9.9"), Self.release("v1.5.0-beta.1")]), etag: nil),
        ])
        let source = GitHubReleasesSource(rules: [rule], session: Self.session())

        let outcome = await source.resolveDiagnostic(rule, preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote?.shortVersion == "1.5.0-beta.1")
        let entry = await RecipeHealth.shared.snapshot().first { $0.id == rule.slug && $0.source == source.name }
        #expect(entry != nil)
        #expect(entry?.lastMiss == nil)
        #expect(entry?.lastSuccess != nil)
    }

    // MARK: - Rules that never probe

    /// A stable rule reads `/releases/latest` (already one release); a
    /// line-anchored rule needs the window `lineAnchoredCeiling` walks; an
    /// opted-out rule has said its newest row is usually the wrong one. None of
    /// the three may ever request the one-row page.
    @Test func stableLineAnchoredAndOptedOutRulesNeverProbe() async throws {
        let stable = GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app", listPageSize: 5)
        let anchored = Self.rule(scope: .installedMajorLineOrNewestStable)
        let optedOut = Self.rule(probes: false)
        let table: [String: ByURLProtocol.Answer] = [
            Self.latestURL: .init(body: Self.release("v1.0.0"), etag: nil),
            Self.fullURL: .init(body: Self.page([Self.release("v1.0.0")]), etag: nil),
            Self.probeURL: .init(body: Self.page([Self.release("v1.0.0")]), etag: nil),
        ]

        for (rule, expected) in [(stable, Self.latestURL), (anchored, Self.fullURL), (optedOut, Self.fullURL)] {
            ByURLProtocol.script.load(table)
            let source = GitHubReleasesSource(rules: [rule], session: Self.session())
            _ = await source.resolveDiagnostic(rule, preferring: .arm64, allowingIntelTranslation: false)
            #expect(ByURLProtocol.script.urls.first == expected, "\(rule.candidateScope) probes=\(rule.probesNewestFirst)")
            #expect(!ByURLProtocol.script.urls.contains(Self.probeURL), "\(rule.candidateScope) probes=\(rule.probesNewestFirst)")
        }
    }

    /// The probe page is a third endpoint in the validator store, so the
    /// pruned set must keep it for a probing rule — and ONLY for one: a rule
    /// that never probes never fetches it, and a stale one-row body would
    /// otherwise sit on disk forever. Mutation this pins: keeping it for every
    /// rule, or for none.
    @Test func validNonTagEndpointsKeepTheProbePageOnlyForProbingRules() {
        let probing = GitHubReleasesSource(rules: [Self.rule()])
        let optedOut = GitHubReleasesSource(rules: [Self.rule(probes: false)])
        let stable = GitHubReleasesSource(rules: [GitHubReleaseRule(
            bundleID: "com.example.app", owner: "example", repo: "app", listPageSize: 5)])

        #expect(probing.validNonTagEndpoints == [Self.latestURL, Self.fullURL, Self.probeURL])
        #expect(optedOut.validNonTagEndpoints == [Self.latestURL, Self.fullURL])
        #expect(stable.validNonTagEndpoints == [Self.latestURL, Self.fullURL])
    }

    // MARK: - Registry

    /// Bitwarden is the one rule measured to fall back most rounds (its newest
    /// release is a web/CLI/browser tag far more often than the desktop one),
    /// so it is opted out; every other prerelease `.newest` rule probes. A new
    /// opt-out is a measurement to be written down in the rule's comment, and
    /// this list is where it is registered.
    @Test func onlyTheMeasuredRulesAreOptedOutOfProbing() {
        let optedOut = GitHubReleaseRegistry.rules
            .filter { $0.usePrereleases && $0.candidateScope == .newest && !$0.probesNewestFirst }
            .map { "\($0.bundleID)/\($0.channel.rawValue)" }
        #expect(Set(optedOut) == ["com.bitwarden.desktop/stable"])
    }
}
