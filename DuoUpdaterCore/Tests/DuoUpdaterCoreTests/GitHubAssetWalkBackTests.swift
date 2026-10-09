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
        // PrintCraft's v0.4.0: the repo and its dmg were renamed to pdfcraft.
        "zz-owner/printcraft-shape": [
            ("v0.4.0", "pdfcraft-0.4.0-macos-universal.dmg"),
            ("v0.2.1", "App-0.2.1-arm64.dmg"),
        ],
        // LocalSend's v1.18.1: a release with no macOS build at all.
        "zz-owner/android-only": [
            ("v1.18.1", "App-1.18.1-android.apk"),
            ("v1.18.0", "App-1.18.0-arm64.dmg"),
        ],
        "zz-owner/windows-zip-only": [
            ("v3.0.1", "App-3.0.1-windows-x64-portable.zip"),
            ("v3.0.0", "App-3.0.0-arm64.dmg"),
        ],
        // A backport cut after the newer release sits above it in the list.
        "zz-owner/backport-above": [
            ("v1.9.5", "App-1.9.5-mac-arm64.dmg"),
            ("v2.0.0", "App-2.0.0-arm64.dmg"),
        ],
        "zz-owner/mac-zip": [
            ("v3.0.1", "App-3.0.1-macos.zip"),
            ("v3.0.0", "App-3.0.0-arm64.dmg"),
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
        // The host is pinned: every fixture asset is arm64-only, so on an Intel
        // Mac `HostArch.current` would turn each answer into an arch-incompatible
        // `notApplicable` and the boundary cases would measure nothing.
        return await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false)
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
        // …but no longer silently: the releases it walked past carry a dmg, so
        // the answer says the artifact was most likely renamed, naming the newest.
        #expect(outcome.warnings == [.installAssetRenamed(
            release: "v2.0.14", assets: ["App-2.0.14-mac-arm64.dmg"], offered: "2.0.9")])
    }

    /// PrintCraft (#1087): one renamed release above the last old-name one. The
    /// walk offers v0.2.1 and, before `installAssetRenamed`, every check called
    /// that healthy.
    @Test func aRenamedInstallerAboveTheAnswerIsAWarning() async {
        let outcome = await diagnostic("zz-owner/printcraft-shape")
        #expect(outcome.remote?.shortVersion == "0.2.1")
        #expect(outcome.warnings == [.installAssetRenamed(
            release: "v0.4.0", assets: ["pdfcraft-0.4.0-macos-universal.dmg"], offered: "0.2.1")])
    }

    /// A release with no macOS build is what the walk exists for, and it still
    /// answers the older version — but says so, as a separate kind: it cannot be
    /// told apart from a rename the name check does not recognise for certain.
    @Test func aReleaseWithNoMacOSBuildIsStillReported() async {
        let android = await diagnostic("zz-owner/android-only")
        #expect(android.remote?.shortVersion == "1.18.0")
        #expect(android.warnings == [.installAssetMissing(release: "v1.18.1", offered: "1.18.0")])
        let windows = await diagnostic("zz-owner/windows-zip-only")
        #expect(windows.remote?.shortVersion == "3.0.0")
        #expect(windows.warnings == [.installAssetMissing(release: "v3.0.1", offered: "3.0.0")])
    }

    /// A release with a macOS-looking installer is named over a newer one with
    /// none: it is the likelier rename.
    @Test func aRenameIsNamedOverANewerMissingBuild() {
        let skipped: [GitHubReleasesSource.SkippedRelease] = [
            .init(tag: "v3.0.2", version: "3.0.2", candidates: []),
            .init(tag: "v3.0.1", version: "3.0.1", candidates: ["App-3.0.1.dmg"]),
        ]
        #expect(GitHubReleasesSource.skippedReleaseWarning(skipped, offered: "3.0.0")
            == .installAssetRenamed(release: "v3.0.1", assets: ["App-3.0.1.dmg"], offered: "3.0.0"))
        #expect(GitHubReleasesSource.skippedReleaseWarning(Array(skipped.prefix(1)), offered: "3.0.0")
            == .installAssetMissing(release: "v3.0.2", offered: "3.0.0"))
        #expect(GitHubReleasesSource.skippedReleaseWarning([], offered: "3.0.0") == nil)
    }

    /// The list is ordered by creation, not version: an older line's backport
    /// above the answer is not a newer release the user is missing.
    @Test func aBackportListedAboveTheAnswerIsNotARename() async {
        let outcome = await diagnostic("zz-owner/backport-above")
        #expect(outcome.remote?.shortVersion == "2.0.0")
        #expect(outcome.warnings.isEmpty)
    }

    /// A zip counts when its name says mac.
    @Test func aMacZipIsARename() async {
        let outcome = await diagnostic("zz-owner/mac-zip")
        #expect(outcome.warnings.first?.kind == "installAssetRenamed")
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
        #expect(outcome.warnings.isEmpty)
    }

    /// What counts as a macOS installer by its name alone.
    @Test func whichAssetsLookLikeAMacOSInstaller() {
        let url = URL(string: "https://example.com/x")!
        let names = [
            "App.dmg", "App.pkg", "App-macos.zip", "App_osx.tar.gz", "App-darwin-arm64.tgz",
            "App-apple-silicon.zip", "App-windows-x64-portable.zip", "App.AppImage",
            "App.apk", "App-linux.tar.gz", "Macro-1.0-windows.zip", "SHA256SUMS.txt",
        ]
        #expect(GitHubReleaseRule.renamedInstallerCandidates(
            in: names.map { ($0, url, nil) }) == [
            "App.dmg", "App.pkg", "App-macos.zip", "App_osx.tar.gz", "App-darwin-arm64.tgz",
            "App-apple-silicon.zip",
        ])
    }
}
