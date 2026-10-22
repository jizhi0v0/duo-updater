import Foundation
import Testing

@testable import DuoUpdaterCore

/// PicGo's beta copies share the stable bundle id, and their version
/// (`2.4.0-beta.10` on the real dmg) makes `ReleaseChannel.detect` call them
/// beta. The detection-only beta rule gives them the newest stable release, as
/// the app's own `checkBetaUpdate` does; the stable copy keeps the stable rule
/// and its one-click. See `docs/app-audits/com-molunerfinn-picgo.md`.
///
/// Mutation: delete the beta rule from `com-molunerfinn-picgo.swift` and
/// `aBetaCopyIsOfferedTheLatestStableWithoutOneClick` fails (no rule, nil).
@Suite struct PicGoBetaRuleTests {

    private static let bundleID = "com.molunerfinn.picgo"

    private static var rules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
    }

    private func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "PicGo", bundleID: Self.bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-PicGo.app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: ReleaseChannel.detect(
                name: "PicGo", bundleID: Self.bundleID, keystoneChannel: nil, version: version))
    }

    private func source() -> GitHubReleasesSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLatest.self]
        return GitHubReleasesSource(rules: Self.rules, session: URLSession(configuration: config))
    }

    @Test func theBetaRuleIsDetectionOnly() throws {
        let beta = try #require(Self.rules.first { $0.channel == .beta })
        #expect(beta.installAssetPattern == nil)
        #expect(beta.installerKind == nil)
        #expect(beta.installedTagPrefix == nil)
        #expect(beta.usePrereleases == false)
    }

    @Test func aBetaCopyIsOfferedTheLatestStableWithoutOneClick() async throws {
        let app = installed("2.4.0-beta.10")
        #expect(app.releaseChannel == .beta)
        let remote = try #require(try await source().latestVersion(for: app))
        #expect(remote.shortVersion == "3.0.3")
        // No asset: the row links the releases page, and nothing installs.
        #expect(remote.downloadURL?.absoluteString == "https://github.com/Molunerfinn/PicGo/releases")
        #expect(remote.vendorInstallerKind == nil)
    }

    @Test func theStableCopyKeepsTheStableRuleAndItsDmg() async throws {
        let app = installed("3.0.2")
        #expect(app.releaseChannel == .stable)
        let remote = try #require(try await source().latestVersion(for: app))
        #expect(remote.shortVersion == "3.0.3")
        #expect(remote.downloadURL?.lastPathComponent == "PicGo-3.0.3-arm64.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
    }

    /// `/releases/latest` answering v3.0.3 with its two mac dmgs.
    final class StubLatest: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let base = "https://github.com/Molunerfinn/PicGo/releases/download/v3.0.3/"
            let assets = ["PicGo-3.0.3-arm64.dmg", "PicGo-3.0.3-x64.dmg"].map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v3.0.3","name":"3.0.3","draft":false,"prerelease":false,\
            "published_at":"2026-10-01T00:00:00Z",\
            "html_url":"https://github.com/Molunerfinn/PicGo/releases/tag/v3.0.3",\
            "body":"notes","assets":[\(assets.joined(separator: ","))]}
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
}
