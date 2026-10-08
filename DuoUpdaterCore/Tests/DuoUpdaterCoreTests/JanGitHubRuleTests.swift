import Foundation
import Testing

@testable import DuoUpdaterCore

/// Jan (`Recipes/jan-ai-app.swift`): from 0.8.5 the bundled local-model engine is
/// arm64-only while the zip's name and the main executable stay universal, so the
/// rule's `architectureRequirement` is the only thing that keeps an Intel Mac on
/// 0.8.4. The host architecture is passed in, never read from the test machine.
@Suite struct JanGitHubRuleTests {

    private static func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == "jan.ai.app" })
    }

    @Test func theRuleKeepsIntelMacsBelowZeroEightFive() throws {
        let requirement = try #require(try Self.rule().architectureRequirement)
        #expect(requirement.fromVersion == "0.8.5")
        #expect(requirement.architectures == [.arm64])
    }

    /// Compared as versions, not text: `0.8.10` is above the threshold although
    /// it sorts below `0.8.5` as a string.
    @Test func admitsBelowTheThresholdEverywhereAndAboveItOnlyOnArm64() {
        let requirement = GitHubArchitectureRequirement(fromVersion: "0.8.5", architectures: [.arm64])
        for version in ["0.8.4", "0.8.0", "0.7.9"] {
            #expect(requirement.admits(version: version, on: .arm64), "\(version) arm64")
            #expect(requirement.admits(version: version, on: .x86_64), "\(version) x86_64")
        }
        for version in ["0.8.5", "0.8.6", "0.8.10", "0.9.0", "1.0.0"] {
            #expect(requirement.admits(version: version, on: .arm64), "\(version) arm64")
            #expect(!requirement.admits(version: version, on: .x86_64), "\(version) x86_64")
        }
    }

    // MARK: - Through the source

    /// Newest first, as `(tag, assetNames)` — the macOS half of the real v0.8.5
    /// and v0.8.4 asset lists.
    private static func assets(_ v: String) -> [String] {
        ["jan-mac-universal-\(v).zip", "Jan_\(v)_universal.dmg", "Jan.app.tar.gz", "latest.json"]
    }

    class StubReleases: URLProtocol, @unchecked Sendable {
        class var releases: [(String, [String])] { [] }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url?.absoluteString ?? ""
            let all = Self.releases
            if url.contains("/releases/latest") {
                respond(Data("{\(Self.fields(all[0]))}".utf8))
                return
            }
            let perPage = URLComponents(string: url)?.queryItems?
                .first { $0.name == "per_page" }?.value.flatMap(Int.init) ?? all.count
            let page = all.prefix(perPage).map { "{\(Self.fields($0))}" }
            respond(Data("[\(page.joined(separator: ","))]".utf8))
        }

        private static func fields(_ release: (String, [String])) -> String {
            let assets = release.1.map {
                """
                {"name":"\($0)","browser_download_url":\
                "https://github.com/janhq/jan/releases/download/\(release.0)/\($0)",\
                "size":1000}
                """
            }
            return """
            "tag_name":"\(release.0)","name":"\(release.0)","draft":false,\
            "prerelease":false,"published_at":"2026-10-08T04:11:16Z",\
            "html_url":"https://github.com/janhq/jan/releases/tag/\(release.0)",\
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

    /// Today's shape: 0.8.5 is `/releases/latest`, 0.8.4 sits below it.
    final class Today: StubReleases, @unchecked Sendable {
        override class var releases: [(String, [String])] {
            [("v0.8.5", JanGitHubRuleTests.assets("0.8.5")),
             ("v0.8.4", JanGitHubRuleTests.assets("0.8.4"))]
        }
    }

    /// Every release on the page is at or above the threshold.
    final class AllAbove: StubReleases, @unchecked Sendable {
        override class var releases: [(String, [String])] {
            [("v0.8.6", JanGitHubRuleTests.assets("0.8.6")),
             ("v0.8.5", JanGitHubRuleTests.assets("0.8.5"))]
        }
    }

    /// The release below the threshold is there but has lost its macOS asset.
    final class BelowWithoutAsset: StubReleases, @unchecked Sendable {
        override class var releases: [(String, [String])] {
            [("v0.8.5", JanGitHubRuleTests.assets("0.8.5")),
             ("v0.8.4", ["Jan_0.8.4_amd64.AppImage", "latest.json"])]
        }
    }

    private static func outcome(
        _ rule: GitHubReleaseRule, _ stub: StubReleases.Type, on arch: HostArch
    ) async -> ProbeOutcome {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [stub]
        let source = GitHubReleasesSource(rules: [rule], session: URLSession(configuration: config))
        return await source.resolveDiagnostic(
            rule, preferring: arch, allowingIntelTranslation: false)
    }

    @Test func appleSiliconIsOfferedZeroEightFive() async throws {
        let outcome = await Self.outcome(try Self.rule(), Today.self, on: .arm64)
        #expect(outcome.failure == nil)
        #expect(outcome.remote?.shortVersion == "0.8.5")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == "jan-mac-universal-0.8.5.zip")
        #expect(outcome.remote?.requiresManualInstaller == false)
    }

    /// `/releases/latest` names only 0.8.5, so the Intel answer needs the list.
    @Test func anIntelMacIsOfferedZeroEightFourWithItsOwnZip() async throws {
        let outcome = await Self.outcome(try Self.rule(), Today.self, on: .x86_64)
        #expect(outcome.failure == nil)
        #expect(outcome.remote?.shortVersion == "0.8.4")
        #expect(outcome.remote?.downloadURL?.lastPathComponent == "jan-mac-universal-0.8.4.zip")
        #expect(outcome.remote?.requiresManualInstaller == false)
    }

    /// The control: without the requirement the same Intel host is offered
    /// 0.8.5, so the answer above comes from the requirement and nothing else.
    @Test func withoutTheRequirementAnIntelMacWouldBeOfferedZeroEightFive() async throws {
        let jan = try Self.rule()
        let bare = GitHubReleaseRule(
            bundleID: jan.bundleID, owner: jan.owner, repo: jan.repo,
            versionPattern: jan.versionPattern,
            installAssetPattern: jan.installAssetPattern, installerKind: jan.installerKind)
        let outcome = await Self.outcome(bare, Today.self, on: .x86_64)
        #expect(outcome.remote?.shortVersion == "0.8.5")
    }

    /// Nothing below the threshold left on the page: no offer, and reported as a
    /// fact about this host rather than as a broken recipe.
    @Test func noReleaseBelowTheThresholdIsNotARecipeMiss() async throws {
        let outcome = await Self.outcome(try Self.rule(), AllAbove.self, on: .x86_64)
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.classification == .notApplicable)
        let arm = await Self.outcome(try Self.rule(), AllAbove.self, on: .arm64)
        #expect(arm.remote?.shortVersion == "0.8.6")
    }

    /// A host-refused release does not hide a renamed asset below it: the walk
    /// still reports the asset miss, the failure that needs fixing in the rule.
    @Test func aMissingAssetBelowTheThresholdIsStillAnAssetMiss() async throws {
        let outcome = await Self.outcome(try Self.rule(), BelowWithoutAsset.self, on: .x86_64)
        #expect(outcome.remote == nil)
        #expect(outcome.failure?.kind == "assetPatternNoMatch")
    }
}
