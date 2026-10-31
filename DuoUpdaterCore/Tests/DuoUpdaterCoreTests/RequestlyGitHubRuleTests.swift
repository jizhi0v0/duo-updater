import Foundation
import Testing

@testable import DuoUpdaterCore

/// Requestly's bundle id says `beta` but it ships one stable release train, and
/// its dmg name carries the version, so the tag and the asset must agree.
@Suite struct RequestlyGitHubRuleTests {

    private static let bundleID = "io.requestly.beta"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.bundleID })
    }

    /// `v26.6.29` is the tag shape; the release's `name` is not read, and a
    /// build-number suffix would not be a version.
    @Test func tagsReadAsVersions() throws {
        let pattern = try rule().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: "v26.6.29", pattern: pattern) == "26.6.29")
        #expect(VendorProbeRecipe.extractVersion(from: "26.6.29", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "v26.6.29-beta.1", pattern: pattern) == nil)
    }

    /// A 26.6.26 copy is offered v26.6.29's arm64 dmg, not the arm64 zip or the
    /// x64 dmg beside it.
    /// Mutation: widen `installAssetPattern` to `^Requestly-` → the last
    /// expectation fails (the zip's name still starts with it).
    @Test func theArm64DmgIsTheInstaller() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLatest.self]
        let source = GitHubReleasesSource(
            rules: [try rule()], session: URLSession(configuration: config))

        let remote = try await source.latestVersion(for: Self.installed("26.6.26"))
        #expect(remote?.shortVersion == "26.6.29")
        #expect(remote?.downloadURL?.lastPathComponent == "Requestly-26.6.29-arm64.dmg")
    }

    private static func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "Requestly", bundleID: bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Requestly.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// `/releases/latest` answering v26.6.29 with the real asset set.
    final class StubLatest: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let base = "https://github.com/requestly/http-interceptor-desktop-app/releases/download/v26.6.29/"
            let assets = [
                "Requestly-26.6.29-arm64.dmg", "Requestly-26.6.29-arm64-mac.zip",
                "Requestly-26.6.29-arm64-mac.zip.blockmap", "Requestly-26.6.29.dmg",
                "latest-mac.yml",
            ].map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v26.6.29","name":"v26.6.29","draft":false,"prerelease":false,\
            "published_at":"2026-10-14T09:12:00Z",\
            "html_url":"https://github.com/requestly/http-interceptor-desktop-app/releases/tag/v26.6.29",\
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
