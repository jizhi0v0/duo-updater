import Foundation
import Testing

@testable import DuoUpdaterCore

/// Tropy's beta builds up to v1.11.0-beta.3 shipped under the stable bundle id
/// `org.tropy.tropy` (real v1.10.0-beta.2 and v1.11.0-beta.3 zips:
/// `Tropy Beta.app`, CFBundleName "Tropy Beta", both version keys
/// `x.y.z-beta.N`). These tests pin that such a copy gets the detection-only
/// beta rule, and that a stable copy still gets the stable rule. See
/// `docs/app-audits/org-tropy-tropy.md`.
@Suite(.serialized) struct TropyGitHubRuleTests {

    private static let stableID = "org.tropy.tropy"

    private static var rules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == stableID }
    }

    private func rule(_ channel: ReleaseChannel) throws -> GitHubReleaseRule {
        try #require(Self.rules.first { $0.channel == channel })
    }

    private func detect(name: String, version: String) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: name, bundleID: Self.stableID, keystoneChannel: nil,
            version: version, bundleFileName: name)
    }

    private func app(name: String, version: String) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: Self.stableID,
            shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/\(name).app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil,
            releaseChannel: detect(name: name, version: version))
    }

    private func source() -> GitHubReleasesSource {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TropyGitHubFixture.self]
        return GitHubReleasesSource(
            rules: Self.rules, session: URLSession(configuration: configuration))
    }

    @Test func theStableIdCarriesAStableAndAnOldBetaRule() {
        #expect(Self.rules.map(\.channel) == [.stable, .beta])
    }

    /// The old beta rule has nothing it could install: the current beta tags
    /// ship `org.tropy.tropy-beta`, a different app.
    @Test func theOldBetaRuleIsDetectionOnly() throws {
        let beta = try rule(.beta)
        #expect(beta.installAssetPattern == nil)
        #expect(beta.installerKind == nil)
        #expect(beta.installedTagPrefix == nil)
        #expect(beta.usePrereleases)
        #expect(VendorProbeRecipe.extractVersion(
            from: "v1.18.0-beta.6", pattern: beta.versionPattern) == "1.18.0-beta.6")
        #expect(VendorProbeRecipe.extractVersion(
            from: "1.10.0-beta.2", pattern: beta.versionPattern) == "1.10.0-beta.2")
        for tag in ["v1.17.3", "1.9.0", "daedalus", "1.0.0-rc.1"] {
            #expect(VendorProbeRecipe.extractVersion(
                from: tag, pattern: beta.versionPattern) == nil, "\(tag)")
        }
    }

    /// The identities read off the real packages.
    @Test func realIdentitiesDetectToTheirRulesChannel() {
        #expect(detect(name: "Tropy Beta", version: "1.11.0-beta.3") == .beta)
        #expect(detect(name: "Tropy Beta", version: "1.10.0-beta.2") == .beta)
        #expect(detect(name: "Tropy", version: "1.17.2") == .stable)
    }

    @Test func aStableCopySelectsTheStableRule() async throws {
        TropyGitHubFixture.reset()
        let remote = try #require(
            try await source().latestVersion(for: app(name: "Tropy", version: "1.17.2")))
        #expect(remote.releaseChannel == .stable)
        #expect(remote.displayVersion == "1.17.3")
        #expect(remote.vendorInstallerKind == .zip)
        let url = try #require(remote.downloadURL?.absoluteString)
        #expect(url.hasSuffix("/v1.17.3/tropy-1.17.3-darwin-arm64.zip"), "\(url)")
        #expect(TropyGitHubFixture.paths() == ["/repos/tropy/tropy/releases/latest"])
    }

    @Test func anOldBetaCopySelectsTheOldBetaRule() async throws {
        TropyGitHubFixture.reset()
        let remote = try #require(try await source().latestVersion(
            for: app(name: "Tropy Beta", version: "1.11.0-beta.3")))
        #expect(remote.releaseChannel == .beta)
        #expect(remote.displayVersion == "1.18.0-beta.6")
        #expect(remote.vendorInstallerKind == nil)
        #expect(remote.requiresManualInstaller)
        #expect(!TropyGitHubFixture.paths().contains("/repos/tropy/tropy/releases/latest"))
    }
}

/// The shape of the real repository: `/releases/latest` is v1.17.3; the list
/// holds the beta prereleases above it.
private final class TropyGitHubFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requested: [String] = []

    static func reset() { lock.withLock { requested = [] } }
    static func paths() -> [String] { lock.withLock { requested } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.withLock { Self.requested.append(path) }
        let latest = Self.release(tag: "v1.17.3", version: "1.17.3", prerelease: false)
        let status: Int
        let body: String
        switch path {
        case "/repos/tropy/tropy/releases/latest":
            status = 200
            body = latest
        case "/repos/tropy/tropy/releases":
            status = 200
            body = "[" + [
                Self.release(tag: "v1.18.0-beta.6", version: "1.18.0-beta.6", prerelease: true),
                Self.release(tag: "v1.18.0-beta.5", version: "1.18.0-beta.5", prerelease: true),
                latest,
            ].joined(separator: ",") + "]"
        default:
            status = 404
            body = #"{"message":"Not Found"}"#
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func release(tag: String, version: String, prerelease: Bool) -> String {
        let base = "https://github.com/tropy/tropy/releases/download/\(tag)/"
        let assets = [
            "tropy-\(version)-darwin-arm64.zip", "tropy-\(version)-darwin.zip",
            "tropy-\(version).dmg",
        ].map { name in
            "{\"name\":\"\(name)\",\"browser_download_url\":\"\(base)\(name)\",\"size\":143605139}"
        }.joined(separator: ",")
        return """
        {
          "tag_name":"\(tag)",
          "prerelease":\(prerelease),
          "draft":false,
          "published_at":"2026-09-16T00:00:00Z",
          "html_url":"https://github.com/tropy/tropy/releases/tag/\(tag)",
          "body":"",
          "assets":[\(assets)]
        }
        """
    }
}
