import Foundation
import Testing

@testable import DuoUpdaterCore

/// Cindy's two editions (`Recipes/com-xd-cindy.swift`, `Recipes/com-xd-cindycn.swift`).
///
/// One repo, two apps: each rule must take its own edition's dmg and never the
/// other's, keep the `-beta` tags out, and walk past `v1.0.0` — a source
/// snapshot with no assets whose tag would otherwise read as a newer 1.0.0.
@Suite struct CindyGitHubRuleTests {

    static let editions = [("com.xd.cindy", "global", "cn"), ("com.xd.cindycn", "cn", "global")]

    private static func rule(_ bundleID: String) -> GitHubReleaseRule? {
        GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID }
    }

    @Test(arguments: editions)
    func ruleReadsTheBareTagAndItsOwnEditionOnly(
        _ edition: (bundleID: String, own: String, other: String)
    ) throws {
        let rule = try #require(Self.rule(edition.bundleID), "no GitHubReleaseRule for \(edition.bundleID)")
        #expect(rule.owner == "makecindy" && rule.repo == "cindy")
        #expect(rule.channel == .stable && !rule.usePrereleases)
        #expect(rule.installerKind == .dmg)
        let pattern = try #require(rule.installAssetPattern)
        func extract(_ tag: String) -> String? {
            VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern)
        }
        func matches(_ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }

        #expect(extract("v0.1.97") == "0.1.97")
        #expect(extract("v0.1.96-beta") == nil)

        #expect(matches("cindy-0.1.97-darwin-arm64-\(edition.own).dmg"))
        #expect(matches("cindy-0.1.97-darwin-x64-\(edition.own).dmg"))
        // The rest of a real release listing.
        #expect(!matches("cindy-0.1.97-darwin-arm64-\(edition.other).dmg"))
        #expect(!matches("cindy-0.1.97-darwin-x64-\(edition.other).dmg"))
        #expect(!matches("cindy-0.1.97-linux-x64-\(edition.own).deb"))
        #expect(!matches("cindy-0.1.97-win32-x64-\(edition.own).exe"))
    }

    // MARK: - The assetless v1.0.0 as `/releases/latest`

    /// Newest first, as `(tag, prerelease, assetNames)`. `v1.0.0` is real and
    /// really has no assets; it is put first here, where `/releases/latest`
    /// would answer it, to replay the worst case.
    private static let releases: [(String, Bool, [String])] = [
        ("v1.0.0", false, []),
        ("v0.1.97", false, [
            "cindy-0.1.97-darwin-arm64-cn.dmg", "cindy-0.1.97-darwin-arm64-global.dmg",
            "cindy-0.1.97-darwin-x64-cn.dmg", "cindy-0.1.97-darwin-x64-global.dmg",
            "cindy-0.1.97-linux-x64-global.deb", "cindy-0.1.97-win32-x64-global.exe"]),
        ("v0.1.96-beta", true, [
            "cindy-0.1.96-darwin-arm64-cn.dmg", "cindy-0.1.96-darwin-arm64-global.dmg",
            "cindy-0.1.96-darwin-x64-cn.dmg", "cindy-0.1.96-darwin-x64-global.dmg"]),
        ("v0.1.95", false, [
            "cindy-0.1.95-darwin-arm64-cn.dmg", "cindy-0.1.95-darwin-arm64-global.dmg",
            "cindy-0.1.95-darwin-x64-cn.dmg", "cindy-0.1.95-darwin-x64-global.dmg"]),
    ]

    final class StubReleases: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url?.absoluteString ?? ""
            let all = CindyGitHubRuleTests.releases
            if url.contains("/releases/latest") {
                respond(Data("{\(Self.fields(all[0]))}".utf8))
                return
            }
            let perPage = URLComponents(string: url)?.queryItems?
                .first { $0.name == "per_page" }?.value.flatMap(Int.init) ?? all.count
            let page = all.prefix(perPage).map { "{\(Self.fields($0))}" }
            respond(Data("[\(page.joined(separator: ","))]".utf8))
        }

        private static func fields(_ release: (String, Bool, [String])) -> String {
            let assets = release.2.map {
                """
                {"name":"\($0)","browser_download_url":\
                "https://github.com/makecindy/cindy/releases/download/\(release.0)/\($0)",\
                "size":1000}
                """
            }
            return """
            "tag_name":"\(release.0)","name":"Cindy \(release.0)","draft":false,\
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

    /// Each edition, on each arch, lands on 0.1.97 and its own dmg: the
    /// assetless 1.0.0 is walked past and the beta is never offered.
    /// Mutation (run): with `installAssetPattern` dropped, the source answers
    /// "1.0.0" — the dmg pattern is what refuses the snapshot.
    @Test(arguments: [
        ("com.xd.cindy", HostArch.arm64, "cindy-0.1.97-darwin-arm64-global.dmg"),
        ("com.xd.cindy", HostArch.x86_64, "cindy-0.1.97-darwin-x64-global.dmg"),
        ("com.xd.cindycn", HostArch.arm64, "cindy-0.1.97-darwin-arm64-cn.dmg"),
        ("com.xd.cindycn", HostArch.x86_64, "cindy-0.1.97-darwin-x64-cn.dmg"),
    ])
    func theAssetlessSnapshotIsWalkedPast(_ bundleID: String, _ arch: HostArch, _ dmg: String) async throws {
        let rule = try #require(Self.rule(bundleID))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubReleases.self]
        let source = GitHubReleasesSource(
            rules: [rule], session: URLSession(configuration: config))
        let outcome = await source.resolveDiagnostic(
            rule, preferring: arch, allowingIntelTranslation: false)
        #expect(outcome.failure == nil)
        #expect(outcome.remote?.shortVersion == "0.1.97")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == dmg)
    }
}

extension CindyGitHubRuleTests {
    /// Two rules on one repo and channel keep separate `recipeID`s through
    /// `variant`; a rule without one keeps the id it always had.
    @Test func theTwoEditionsKeepTheirOwnRecipeIDs() throws {
        let global = try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == "com.xd.cindy" })
        let cn = try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == "com.xd.cindycn" })
        #expect(global.recipeID == "github:makecindy/cindy:stable:global")
        #expect(cn.recipeID == "github:makecindy/cindy:stable:cn")
        let plain = GitHubReleaseRule(bundleID: "com.example.app", owner: "o", repo: "r")
        #expect(plain.recipeID == "github:o/r:stable")
    }
}
