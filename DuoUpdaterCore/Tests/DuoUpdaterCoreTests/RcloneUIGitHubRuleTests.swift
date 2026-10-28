import Foundation
import Testing

@testable import DuoUpdaterCore

/// Rclone UI shares its repository with Rclone Cloud, a CLI released under
/// `cloud-…` tags, and was `com.stray.app` before 2.0.0.
@Suite struct RcloneUIGitHubRuleTests {

    private static let bundleID = "com.rclone.ui"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.bundleID })
    }

    /// The Rclone Cloud tags never read as a Rclone UI version.
    @Test func cloudTagsAreNotRcloneUIReleases() throws {
        let pattern = try rule().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: "v3.7.5", pattern: pattern) == "3.7.5")
        #expect(VendorProbeRecipe.extractVersion(from: "cloud-v0.1.0", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "cloud-latest", pattern: pattern) == nil)
    }

    /// A 1.9.3 copy, still `com.stray.app`, is checked by the rule through
    /// `BundleIDMigration` and offered the Apple-silicon dmg, not the Intel one
    /// beside it. A copy on the old id at or past the bound gets nothing.
    /// Mutation: drop the Rclone UI entry from `BundleIDMigration.all` → the
    /// first expectation fails.
    @Test func aPreRenameCopyIsOfferedTheCurrentRelease() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLatest.self]
        let source = GitHubReleasesSource(
            rules: [try rule()], session: URLSession(configuration: config))

        let old = try await source.latestVersion(for: Self.installed("com.stray.app", "1.9.3"))
        #expect(old?.shortVersion == "3.7.5")
        #expect(old?.downloadURL?.lastPathComponent == "Rclone.UI_aarch64.dmg")
        #expect(try await source.latestVersion(for: Self.installed("com.stray.app", "2.0.0")) == nil)
    }

    /// The swap off a 1.x copy waits for the user's confirmation: the configs,
    /// license key and scheduled tasks 1.x kept under `com.stray.app` are not
    /// read by 2.x. Mutation: drop `isRewrite: true` from the Rclone UI entry
    /// → both expectations fail.
    @Test func aPreRenameCopyIsConfirmedBeforeTheSwap() {
        let result = UpdateResult(
            app: Self.installed("com.stray.app", "1.9.3"),
            remote: RemoteVersion(
                shortVersion: "3.7.5", version: nil, downloadURL: nil, sourceName: "GitHub"),
            status: .updateAvailable(latest: "3.7.5"))
        #expect(result.isVendorRewrite)
        #expect(UpdatePolicy.installConfirmation(for: result) == .vendorRewrite)
    }

    private static func installed(_ id: String, _ version: String) -> InstalledApp {
        InstalledApp(
            name: "Rclone UI", bundleID: id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Rclone UI.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// `/releases/latest` answering v3.7.5 with both macOS dmgs and its updater manifest.
    final class StubLatest: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let base = "https://github.com/rclone/rclone-ui/releases/download/v3.7.5/"
            let assets = ["Rclone.UI_x64.dmg", "Rclone.UI_aarch64.dmg", "latest.json"].map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v3.7.5","name":"v3.7.5","draft":false,"prerelease":false,\
            "published_at":"2026-09-18T22:42:05Z",\
            "html_url":"https://github.com/rclone/rclone-ui/releases/tag/v3.7.5",\
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
