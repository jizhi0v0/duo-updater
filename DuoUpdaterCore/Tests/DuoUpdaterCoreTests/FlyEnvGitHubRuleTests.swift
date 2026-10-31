import Foundation
import Testing

@testable import DuoUpdaterCore

/// FlyEnv's releases carry both electron-updater artifacts (a `-mac.zip` and a
/// dmg) among the linux/windows packages; the rule takes the zip, which is what
/// the app's own updater and the Homebrew cask take.
@Suite struct FlyEnvGitHubRuleTests {

    private static let bundleID = "phpstudy.xpfme.com"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.bundleID })
    }

    /// Tags are `v`-prefixed; the release name carries prose after the version.
    @Test func tagsReadAsVersions() throws {
        let pattern = try rule().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: "v4.20.2", pattern: pattern) == "4.20.2")
        #expect(VendorProbeRecipe.extractVersion(from: "4.20.2", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "v4.20.2: Added Windows support",
                                                 pattern: pattern) == nil)
    }

    /// A 4.20.1 copy is offered v4.20.2's `-arm64-mac.zip`, not the dmg, the
    /// `.blockmap`, or the arm64 `.deb`/`.rpm` beside it.
    /// Mutation: drop `-mac` from `installAssetPattern` → this still passes (no
    /// other asset ends in `-arm64.zip`), so the dmg and blockmap are what the
    /// pattern must keep excluding; widen to `^FlyEnv-` to see it fail.
    @Test func theMacZipIsTheInstaller() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLatest.self]
        let source = GitHubReleasesSource(
            rules: [try rule()], session: URLSession(configuration: config))

        let remote = try await source.latestVersion(for: Self.installed("4.20.1"))
        #expect(remote?.shortVersion == "4.20.2")
        #expect(remote?.downloadURL?.lastPathComponent == "FlyEnv-4.20.2-arm64-mac.zip")
    }

    private static func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "FlyEnv", bundleID: bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-FlyEnv.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// `/releases/latest` answering v4.20.2 with the real asset set.
    final class StubLatest: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let base = "https://github.com/xpf0000/FlyEnv/releases/download/v4.20.2/"
            let assets = [
                "FlyEnv-4.20.2-arm64-mac.zip", "FlyEnv-4.20.2-arm64-mac.zip.blockmap",
                "FlyEnv-4.20.2-arm64.deb", "FlyEnv-4.20.2-arm64.dmg",
                "FlyEnv-4.20.2-arm64.dmg.blockmap", "FlyEnv-4.20.2-arm64.rpm",
                "FlyEnv-4.20.2-x64-mac.zip",
            ].map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v4.20.2","name":"v4.20.2: Added Windows Project Environment Support",\
            "draft":false,"prerelease":false,"published_at":"2026-10-29T06:30:00Z",\
            "html_url":"https://github.com/xpf0000/FlyEnv/releases/tag/v4.20.2",\
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
