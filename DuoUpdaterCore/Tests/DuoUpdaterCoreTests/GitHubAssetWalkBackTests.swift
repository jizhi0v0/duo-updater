import Foundation
import Testing

@testable import DuoUpdaterCore

/// The walk back past releases whose assets do not match `installAssetPattern`.
///
/// Two contracts meet here, and they pull in opposite directions:
///
/// * Espanso's rule relies on the tolerated side — its pattern is a literal
///   (`Espanso-Mac-Universal.dmg`) and older releases shipped the same name as a
///   `.zip`, so "walk back to the newest release that still carries the dmg" is the
///   behaviour it was written for (`Recipes/com-federicoterzi-espanso.swift:12-15`).
/// * The walk itself says the opposite for a *run* of them: "a run of them means
///   the pattern stopped matching, which is a recipe failure and has to surface as
///   one" (`GitHubReleasesSource` at `skippedForMissingAsset`).
///
/// Cherry Studio sat on the seam: the vendor renamed its macOS artifact at v2.0.10,
/// the five releases above 2.0.9 carried no *matching* asset, and the walk answered
/// **2.0.9** as the latest while recording the recipe healthy.
///
/// These tests do not move that boundary — which side of it is right is a decision
/// for whoever owns the two contracts above — they pin where it currently is, so
/// changing it is a visible edit rather than a silent one. What they DO pin as a
/// bug is the reporting: a walk that ends with no answer at all must say the ASSET
/// pattern stopped matching, not that the version pattern did.
@Suite struct GitHubAssetWalkBackTests {

    private static let bundleID = "zz.walkback.app"

    /// A rule whose tag pattern matches every release and whose asset pattern
    /// matches only the pre-rename spelling. One slug per scenario, because
    /// swift-testing runs these in parallel and the stub below is keyed by it —
    /// a single shared slug made the cases read each other's fixtures.
    private static func rule(_ slug: String) -> GitHubReleaseRule {
        let parts = slug.split(separator: "/")
        return GitHubReleaseRule(
            bundleID: bundleID,
            owner: String(parts[0]), repo: String(parts[1]),
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^App-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg)
    }

    /// Every scenario's releases, newest first, as `(tag, assetName)` — immutable,
    /// so parallel tests cannot interfere.
    private static let payloads: [String: [(String, String)]] = [
        "zz-owner/renamed": [
            ("v2.0.14", "App-2.0.14-mac-arm64.dmg"),
            ("v2.0.13", "App-2.0.13-mac-arm64.dmg"),
            ("v2.0.12", "App-2.0.12-mac-arm64.dmg"),
            ("v2.0.11", "App-2.0.11-mac-arm64.dmg"),
            ("v2.0.10", "App-2.0.10-mac-arm64.dmg"),
            ("v2.0.9", "App-2.0.9-mac-arm64.dmg"),
            ("v2.0.8", "App-2.0.8-mac-arm64.dmg"),
        ],
        "zz-owner/renamed-then-old": [
            ("v2.0.14", "App-2.0.14-mac-arm64.dmg"),
            ("v2.0.13", "App-2.0.13-mac-arm64.dmg"),
            ("v2.0.12", "App-2.0.12-mac-arm64.dmg"),
            ("v2.0.11", "App-2.0.11-mac-arm64.dmg"),
            ("v2.0.10", "App-2.0.10-mac-arm64.dmg"),
            ("v2.0.9", "App-2.0.9-arm64.dmg"),
        ],
        "zz-owner/platform-partial": [
            ("v2.0.14", "App-2.0.14-mac-arm64.dmg"),
            ("v2.0.13", "App-2.0.13-mac-arm64.dmg"),
            ("v2.0.12", "App-2.0.12-mac-arm64.dmg"),
            ("v2.0.11", "App-2.0.11-mac-arm64.dmg"),
            ("v2.0.10", "App-2.0.10-arm64.dmg"),
        ],
        "zz-owner/tag-changed": [
            ("release-2.0.14", "App-2.0.14-arm64.dmg"),
            ("release-2.0.13", "App-2.0.13-arm64.dmg"),
        ],
        "zz-owner/healthy": [
            ("v2.0.14", "App-2.0.14-arm64.dmg"),
            ("v2.0.13", "App-2.0.13-mac-arm64.dmg"),
        ],
    ]

    /// Serves `/releases/latest` as one release and `/releases?per_page=N` as a
    /// list, from a canned set, so the walk is driven without the network.
    final class StubReleases: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url?.absoluteString ?? ""
            let all = GitHubAssetWalkBackTests.payloads
                .first { url.contains("/repos/\($0.key)/") }?.value ?? []
            // `/releases/latest` answers with a bare object, not an array — and a
            // one-row probe arrives as `?per_page=1`, which the list branch below
            // slices like any other page.
            if url.contains("/releases/latest") {
                respond(Data("{\(Self.fields(all[0]))}".utf8))
                return
            }
            let perPage = URLComponents(string: url)?.queryItems?
                .first { $0.name == "per_page" }?.value.flatMap(Int.init) ?? all.count
            let page = all.prefix(perPage).map { "{\(Self.fields($0))}" }
            respond(Data("[\(page.joined(separator: ","))]".utf8))
        }

        private static func fields(_ release: (String, String)) -> String {
            """
            "tag_name":"\(release.0)","name":"\(release.0)","draft":false,"prerelease":false,\
            "published_at":"2026-09-01T00:00:00Z",\
            "html_url":"https://github.com/zz-owner/zz-repo/releases/tag/\(release.0)",\
            "body":"notes","assets":[\
            {"name":"\(release.1)","browser_download_url":\
            "https://github.com/zz-owner/zz-repo/releases/download/\(release.0)/\(release.1)",\
            "size":1000}]
            """
        }

        private func respond(_ data: Data) {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func diagnostic(_ slug: String) async -> ProbeOutcome {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubReleases.self]
        let rule = Self.rule(slug)
        let source = GitHubReleasesSource(
            rules: [rule], session: URLSession(configuration: config))
        return await source.resolveDiagnostic(rule)
    }

    /// Six asset-less releases: past the tolerance, no answer, and the report must
    /// name the ASSET pattern. Before this, the same walk produced
    /// `versionPatternNoMatch` — and `duo verify` handed the issue the *tag* regex,
    /// which was matching every one of those releases perfectly.
    @Test func aRenamedArtifactIsReportedAsAnAssetMissNotAVersionMiss() async {
        let outcome = await diagnostic("zz-owner/renamed")
        #expect(outcome.remote == nil)
        guard case .assetPatternNoMatch(let walked) = outcome.failure else {
            Issue.record("expected an asset-pattern miss, got \(String(describing: outcome.failure))")
            return
        }
        #expect(walked == 6, "the walk stops on the sixth asset-less release")
    }

    /// A version pattern that matches nothing is still the version pattern's
    /// failure — the distinction has to cut both ways, or every tag-format change
    /// would be blamed on the asset pattern instead.
    @Test func aTagThatMatchesNoVersionIsStillAVersionMiss() async {
        let outcome = await diagnostic("zz-owner/tag-changed")
        #expect(outcome.remote == nil)
        guard case .versionPatternNoMatch = outcome.failure else {
            Issue.record("expected a version-pattern miss, got \(String(describing: outcome.failure))")
            return
        }
    }

    /// **The boundary, pinned.** Five asset-less releases and then one that still
    /// carries the old name: the walk accepts it and offers it as the latest. That
    /// is the tolerated side espanso's rule documents, and it is also exactly the
    /// shape Cherry Studio produced — so this test is the place to look before
    /// changing either.
    @Test func fiveAssetLessReleasesStillWalkBackToAnOlderMatch() async {
        let outcome = await diagnostic("zz-owner/renamed-then-old")
        #expect(outcome.remote?.shortVersion == "2.0.9")
        #expect(outcome.failure == nil)
    }

    /// Four asset-less releases and a match: the ordinary platform-partial case the
    /// walk exists for.
    @Test func aHandfulOfAssetLessReleasesStillWalkBack() async {
        let outcome = await diagnostic("zz-owner/platform-partial")
        #expect(outcome.remote?.shortVersion == "2.0.10")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == "App-2.0.10-arm64.dmg")
    }

    /// The asset pattern still matches: nothing about the walk-back may change the
    /// healthy path.
    @Test func anAssetThatMatchesIsAnsweredWithoutWalking() async {
        let outcome = await diagnostic("zz-owner/healthy")
        #expect(outcome.remote?.shortVersion == "2.0.14")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == "App-2.0.14-arm64.dmg")
        #expect(outcome.failure == nil)
    }
}
