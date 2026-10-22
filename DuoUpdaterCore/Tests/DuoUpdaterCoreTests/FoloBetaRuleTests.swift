import Foundation
import Testing

@testable import DuoUpdaterCore

/// Folo's Follow-era copies (`0.1.0-beta.0` … `0.3.4-beta.1`) were the
/// mainline (`prerelease: false`), but the bundle keeps the `-beta.N` suffix, so
/// `ReleaseChannel.detect` calls them beta. The detection-only beta rule gives
/// them the newest stable `desktop/vX`; the stable copy keeps the stable rule
/// and its one-click.
///
/// Mutation: delete the beta rule from `is-follow.swift` and
/// `aBetaCopyIsOfferedTheLatestStableWithoutOneClick` fails (no rule, nil).
/// See `docs/app-audits/is-follow.md`.
@Suite struct FoloBetaRuleTests {

    private static let bundleID = "is.follow"

    private static var rules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
    }

    private func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "Folo", bundleID: Self.bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Folo.app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: ReleaseChannel.detect(
                name: "Folo", bundleID: Self.bundleID, keystoneChannel: nil, version: version))
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
        let app = installed("0.3.4-beta.1")
        #expect(app.releaseChannel == .beta)
        let remote = try #require(try await source().latestVersion(for: app))
        #expect(remote.shortVersion == "1.16.0")
        // No asset: the row links the releases page, and nothing installs.
        #expect(remote.downloadURL?.absoluteString == "https://github.com/RSSNext/Folo/releases")
        #expect(remote.vendorInstallerKind == nil)
    }

    @Test func theStableCopyKeepsTheStableRuleAndItsDmg() async throws {
        let app = installed("1.15.0")
        #expect(app.releaseChannel == .stable)
        let remote = try #require(try await source().latestVersion(for: app))
        #expect(remote.shortVersion == "1.16.0")
        #expect(remote.downloadURL?.lastPathComponent == "Folo-1.16.0-macos-arm64.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
    }

    /// `/releases/latest` answering desktop/v1.16.0 with its mac dmgs.
    final class StubLatest: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let base = "https://github.com/RSSNext/Folo/releases/download/desktop/v1.16.0/"
            let assets = ["Folo-1.16.0-macos-arm64.dmg", "Folo-1.16.0-macos-x64.dmg"].map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"desktop/v1.16.0","name":"1.16.0","draft":false,"prerelease":false,\
            "published_at":"2026-10-01T00:00:00Z",\
            "html_url":"https://github.com/RSSNext/Folo/releases/tag/desktop/v1.16.0",\
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
