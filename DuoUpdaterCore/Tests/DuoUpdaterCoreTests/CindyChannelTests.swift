import Foundation
import Testing

@testable import DuoUpdaterCore

/// `CindyChannel`: the app's own `update-channel-settings.json` decides beta, the
/// two editions keep it in different directories, and the beta rule offers
/// whichever of a `-beta` prerelease or a stable release is newer.
@Suite struct CindyChannelTests {

    private func resolve(_ json: String?) -> ReleaseChannel {
        CindyChannel.resolve(settings: json.map { Data($0.utf8) }).channel
    }

    /// The two files the real app wrote when its toggle was flipped on and off
    /// (global edition 0.1.97, 2026-10-07), byte for byte.
    @Test func theTogglesRealFilesResolve() {
        #expect(resolve("{\n  \"enableBeta\": true\n}") == .beta)
        #expect(resolve("{\n  \"enableBeta\": false\n}") == .stable)
    }

    /// The app's rule: a present `enableBeta` decides; without it the
    /// organisation default does; with neither, stable.
    @Test func anExplicitChoiceOutranksTheOrganisationDefault() {
        #expect(resolve(nil) == .stable)
        #expect(resolve("{}") == .stable)
        #expect(resolve(#"{"orgDefaultEnableBeta":true}"#) == .beta)
        #expect(resolve(#"{"enableBeta":false,"orgDefaultEnableBeta":true}"#) == .stable)
        #expect(resolve(#"{"enableBeta":true,"orgDefaultEnableBeta":false}"#) == .beta)
    }

    /// Anything that is not JSON `true` is not an opt-in — the app's `normalize`
    /// takes booleans only — and a file that is not an object is no choice at all.
    @Test func onlyJSONTrueOptsIn() {
        #expect(resolve(#"{"enableBeta":1}"#) == .stable)
        #expect(resolve(#"{"enableBeta":"true"}"#) == .stable)
        #expect(resolve(#"{"orgDefaultEnableBeta":1}"#) == .stable)
        #expect(resolve("[true]") == .stable)
        #expect(resolve("not json") == .stable)
    }

    /// The editions' `userData` directories differ; reading one for both would
    /// leave the other on stable forever.
    @Test func eachEditionReadsItsOwnDirectory() throws {
        let global = try #require(CindyChannel.settingsFileURL(forBundleID: "com.xd.cindy"))
        let china = try #require(CindyChannel.settingsFileURL(forBundleID: "com.xd.cindycn"))
        #expect(global.path.hasSuffix("/Library/Application Support/CindyGlobal/update-channel-settings.json"))
        #expect(china.path.hasSuffix("/Library/Application Support/Cindy/update-channel-settings.json"))
        #expect(CindyChannel.settingsFileURL(forBundleID: "com.xd.other") == nil)
        #expect(ChannelBinding.boundBundleIDs.isSuperset(of: ["com.xd.cindy", "com.xd.cindycn"]))
    }

    /// The proof anchors the request, on both halves (same shape as WhatCable's):
    /// it passes on each edition's beta rule as written and fails when either
    /// the list read or the `-beta` tag acceptance is dropped.
    @Test(arguments: ["com.xd.cindy", "com.xd.cindycn"])
    func theBetaProofAnchorsBothHalvesOfTheRequest(_ bundleID: String) throws {
        let proof = try #require(ChannelProofRegistry.githubProofs[ChannelProofKey(bundleID, .beta)])
        guard case .recipeAnchor(let pattern, let fields) = proof else {
            Issue.record("expected a recipe anchor"); return
        }
        let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
        let beta = try #require(rules.first { $0.channel == .beta })
        let stable = try #require(rules.first { $0.channel == .stable })
        func failure(_ rule: GitHubReleaseRule) -> String? {
            RecipeSanity.recipeAnchorFailure(pattern: pattern, fields: fields, channel: .beta, subject: rule)
        }
        func variant(usePrereleases: Bool, versionPattern: String) -> GitHubReleaseRule {
            GitHubReleaseRule(
                bundleID: beta.bundleID, owner: beta.owner, repo: beta.repo,
                usePrereleases: usePrereleases, versionPattern: versionPattern,
                installAssetPattern: beta.installAssetPattern, installerKind: beta.installerKind,
                channel: .beta, variant: beta.variant)
        }
        #expect(failure(beta) == nil)
        #expect(failure(variant(usePrereleases: false, versionPattern: beta.versionPattern)) != nil)
        #expect(failure(variant(usePrereleases: true, versionPattern: stable.versionPattern)) != nil)
    }

    // MARK: - The beta rule against a release list

    /// Newest first, as `(tag, prerelease)`; every release carries all four
    /// macOS dmgs, named as the real ones are (no channel token).
    nonisolated(unsafe) static var releases: [(String, Bool)] = []

    final class StubReleases: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url?.absoluteString ?? ""
            let all = CindyChannelTests.releases
            if url.contains("/releases/latest") {
                let latest = all.first { !$0.1 }!
                respond(Data("{\(Self.fields(latest))}".utf8))
                return
            }
            let perPage = URLComponents(string: url)?.queryItems?
                .first { $0.name == "per_page" }?.value.flatMap(Int.init) ?? all.count
            let page = all.prefix(perPage).map { "{\(Self.fields($0))}" }
            respond(Data("[\(page.joined(separator: ","))]".utf8))
        }

        private static func fields(_ release: (String, Bool)) -> String {
            let version = release.0.dropFirst().replacingOccurrences(of: "-beta", with: "")
            let assets = ["arm64-cn", "arm64-global", "x64-cn", "x64-global"].map {
                """
                {"name":"cindy-\(version)-darwin-\($0).dmg","browser_download_url":\
                "https://github.com/makecindy/cindy/releases/download/\(release.0)/cindy-\(version)-darwin-\($0).dmg",\
                "size":1000}
                """
            }
            return """
            "tag_name":"\(release.0)","name":"\(release.0)","draft":false,\
            "prerelease":\(release.1),"published_at":"2026-10-03T00:00:00Z",\
            "html_url":"https://github.com/makecindy/cindy/releases/tag/\(release.0)",\
            "body":"notes","assets":[\(assets.joined(separator: ","))]
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

    private func answer(_ bundleID: String, _ channel: ReleaseChannel) async throws -> String? {
        let rule = try #require(GitHubReleaseRegistry.rules.first {
            $0.bundleID == bundleID && $0.channel == channel
        })
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubReleases.self]
        let source = GitHubReleasesSource(rules: [rule], session: URLSession(configuration: config))
        let outcome = await source.resolveDiagnostic(rule, preferring: .arm64, allowingIntelTranslation: false)
        return outcome.remote.map {
            "\($0.shortVersion ?? "-") \($0.downloadURL?.lastPathComponent ?? "-")"
        }
    }

    /// Both cases in one test: the stub is a static and the two lists must not
    /// race each other.
    @Test func betaTakesTheNewerOfBetaAndStableAndStableNeverTakesBeta() async throws {
        // Today's shape: the newest release is stable, a beta sits below it.
        Self.releases = [("v0.1.97", false), ("v0.1.96-beta", true), ("v0.1.95", false)]
        #expect(try await answer("com.xd.cindy", .beta) == "0.1.97 cindy-0.1.97-darwin-arm64-global.dmg")
        #expect(try await answer("com.xd.cindycn", .beta) == "0.1.97 cindy-0.1.97-darwin-arm64-cn.dmg")

        // A beta ahead of stable: only the beta rule offers it.
        Self.releases = [("v0.1.98-beta", true), ("v0.1.97", false)]
        #expect(try await answer("com.xd.cindy", .beta) == "0.1.98 cindy-0.1.98-darwin-arm64-global.dmg")
        #expect(try await answer("com.xd.cindycn", .beta) == "0.1.98 cindy-0.1.98-darwin-arm64-cn.dmg")
        #expect(try await answer("com.xd.cindy", .stable) == "0.1.97 cindy-0.1.97-darwin-arm64-global.dmg")
        #expect(try await answer("com.xd.cindycn", .stable) == "0.1.97 cindy-0.1.97-darwin-arm64-cn.dmg")
    }
}
