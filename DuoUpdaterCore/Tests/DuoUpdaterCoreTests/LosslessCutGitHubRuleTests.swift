import Foundation
import Testing

@testable import DuoUpdaterCore

/// LosslessCut publishes prereleases on the SAME tag shape and asset names as
/// its stable releases (`v3.70.0` is `prerelease: true`; stable of that line is
/// `v3.70.1`/`v3.70.2`), so a copy installed from one is read as stable. The
/// stable rule is safe because the line graduates upward: this replays the
/// graduation and the asset choice, and pins that the x64 dmg / universal pkg
/// are never the answer.
@Suite struct LosslessCutGitHubRuleTests {
    private static let id = "no.mifi.losslesscut-mac"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.id })
    }

    private static func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "LosslessCut", bundleID: id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-LosslessCut.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// 3.70.0 is the prerelease of the 3.70 line, 3.70.2 its stable graduation;
    /// a copy installed from the prerelease is offered the graduation, and the
    /// arm64 dmg is what installs it.
    @Test func aPrereleaseCopyIsOfferedItsStableGraduation() async throws {
        let source = GitHubReleasesSource(
            rules: [try rule()], session: Self.stubbedSession())
        let remote = try #require(try await source.latestVersion(for: Self.installed("3.70.0")))
        #expect(remote.shortVersion == "3.70.2")
        #expect(remote.downloadURL?.lastPathComponent == "LosslessCut-mac-arm64.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
    }

    /// The release beside the arm64 dmg carries the Intel dmg and a universal
    /// pkg named "DONT-USE-THIS-FILE"; neither is ever the chosen asset. Mutation:
    /// loosen the pattern to `\.dmg$` → the x64 dmg is chosen here.
    @Test func theArm64DmgIsTheOnlyAssetChosen() async throws {
        let rule = try rule()
        #expect(GitHubReleaseRule.installableAsset(
            from: Self.assets, matching: try #require(rule.installAssetPattern),
            preferring: .arm64, allowingIntelTranslation: false)?.url.lastPathComponent
            == "LosslessCut-mac-arm64.dmg")
        #expect(GitHubReleaseRule.installableAsset(
            from: Self.assets, matching: try #require(rule.installAssetPattern),
            preferring: .x86_64, allowingIntelTranslation: false) == nil)
    }

    /// A newest row that ships no arm64 dmg is not answered from a stale row:
    /// the walk-back is bounded, and the answer is nil rather than an older
    /// version presented as "latest".
    @Test func aRowWithoutTheArm64DmgIsNotAnsweredFromAnOlderRow() async throws {
        let source = GitHubReleasesSource(
            rules: [try rule()], session: Self.intelOnlySession())
        #expect(try await source.latestVersion(for: Self.installed("3.70.0")) == nil)
    }

    private static let assets: [(name: String, url: URL, size: Int64?)] = [
        ("LosslessCut-mac-arm64.dmg", URL(string: "https://example.invalid/a/LosslessCut-mac-arm64.dmg")!, 1000),
        ("LosslessCut-mac-x64.dmg", URL(string: "https://example.invalid/a/LosslessCut-mac-x64.dmg")!, 1000),
        ("LosslessCut-mac-universal-DONT-USE-THIS-FILE.pkg", URL(string: "https://example.invalid/a/u.pkg")!, 1000),
    ]

    private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    private static func intelOnlySession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IntelOnlyStub.self]
        return URLSession(configuration: config)
    }

    /// `/releases/latest` answers v3.70.2; the list endpoint answers the same one
    /// row, so the fallback cannot find an arm64 dmg either.
    class Stub: URLProtocol, @unchecked Sendable {
        class var names: [String] {
            ["LosslessCut-mac-arm64.dmg", "LosslessCut-mac-x64.dmg",
             "LosslessCut-mac-universal-DONT-USE-THIS-FILE.pkg"]
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let assets = Self.names
            let base = "https://example.invalid/lossless-cut/releases/download/v3.70.2/"
            let encoded = assets.map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v3.70.2","name":"v3.70.2","draft":false,"prerelease":false,\
            "published_at":"2026-10-28T06:48:01Z",\
            "html_url":"https://example.invalid/lossless-cut/releases/tag/v3.70.2",\
            "body":"notes","assets":[\(encoded.joined(separator: ","))]}
            """
            let body = request.url?.absoluteString.contains("/releases/latest") == true
                ? release : "[\(release)]"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// The same release with the arm64 dmg missing, so the list fallback cannot
    /// find one either.
    final class IntelOnlyStub: Stub {
        override class var names: [String] {
            ["LosslessCut-mac-x64.dmg", "LosslessCut-mac-universal-DONT-USE-THIS-FILE.pkg"]
        }
    }
}
