import Foundation
import Testing

@testable import DuoUpdaterCore

/// massCode's beta copies (`2.0.0-beta.6`, `4.0.0-beta.2`) share the stable
/// bundle id, and their version makes `ReleaseChannel.detect` call them beta.
/// There has been no beta since 2025-07, so the detection-only beta rule gives
/// them the newest stable release; the stable copy keeps the stable rule and
/// its one-click.
///
/// Mutation: delete the beta rule from `io-masscode-app.swift` and
/// `aBetaCopyIsOfferedTheLatestStableWithoutOneClick` fails (no rule, nil).
/// See `docs/app-audits/io-masscode-app.md`.
@Suite struct MassCodeBetaRuleTests {

    private static let bundleID = "io.masscode.app"

    private static var rules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
    }

    private func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "massCode", bundleID: Self.bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-massCode.app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: ReleaseChannel.detect(
                name: "massCode", bundleID: Self.bundleID, keystoneChannel: nil, version: version))
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
        let app = installed("4.0.0-beta.2")
        #expect(app.releaseChannel == .beta)
        let remote = try #require(try await source().latestVersion(for: app))
        #expect(remote.shortVersion == "6.3.1")
        // No asset: the row links the releases page, and nothing installs.
        #expect(remote.downloadURL?.absoluteString == "https://github.com/massCodeIO/massCode/releases")
        #expect(remote.vendorInstallerKind == nil)
    }

    @Test func theStableCopyKeepsTheStableRuleAndItsDmg() async throws {
        let app = installed("6.2.1")
        #expect(app.releaseChannel == .stable)
        let remote = try #require(try await source().latestVersion(for: app))
        #expect(remote.shortVersion == "6.3.1")
        #expect(remote.downloadURL?.lastPathComponent == "massCode-6.3.1-arm64.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
    }

    /// `/releases/latest` answering v6.3.1 with its mac dmgs.
    final class StubLatest: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let base = "https://github.com/massCodeIO/massCode/releases/download/v6.3.1/"
            let assets = ["massCode-6.3.1-arm64.dmg", "massCode-6.3.1.dmg"].map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v6.3.1","name":"6.3.1","draft":false,"prerelease":false,\
            "published_at":"2026-10-01T00:00:00Z",\
            "html_url":"https://github.com/massCodeIO/massCode/releases/tag/v6.3.1",\
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
