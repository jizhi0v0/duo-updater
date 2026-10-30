import Foundation
import Testing

@testable import DuoUpdaterCore

/// Reqable tags with no `v` (its release *names* carry one) and publishes the
/// occasional Windows-only release, which the rule has to walk past.
@Suite struct ReqableGitHubRuleTests {

    private static let bundleID = "com.reqable.macosx"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.bundleID })
    }

    /// Tags are bare numbers; the `v` lives in the release name only.
    @Test func tagsReadAsVersions() throws {
        let pattern = try rule().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: "3.3.9", pattern: pattern) == "3.3.9")
        #expect(VendorProbeRecipe.extractVersion(from: "v3.3.9", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "3.3.9-beta", pattern: pattern) == nil)
    }

    /// A 3.3.7 copy is offered the newest macOS dmg, walking past a Windows-only
    /// release (no macOS asset at all) the way the real 3.3.8 is.
    /// Mutation: drop the walk-back → the version reads "3.3.8" or nothing.
    @Test func aWindowsOnlyReleaseIsWalkedPast() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubReleases.self]
        let source = GitHubReleasesSource(
            rules: [try rule()], session: URLSession(configuration: config))

        let remote = try await source.latestVersion(for: Self.installed("3.3.7"))
        #expect(remote?.shortVersion == "3.3.9")
        #expect(remote?.downloadURL?.lastPathComponent == "reqable-app-macos-arm64.dmg")
    }

    private static func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "Reqable", bundleID: bundleID, shortVersion: version, buildVersion: "229",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Reqable.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// A list whose newest entry is Windows-only, then 3.3.9 with the macOS dmg.
    final class StubReleases: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            func release(_ tag: String, _ assets: [String]) -> String {
                let base = "https://github.com/reqable/reqable-app/releases/download/\(tag)/"
                let list = assets.map {
                    #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
                }
                return """
                {"tag_name":"\(tag)","name":"v\(tag)","draft":false,"prerelease":false,\
                "published_at":"2026-10-20T10:00:00Z",\
                "html_url":"https://github.com/reqable/reqable-app/releases/tag/\(tag)",\
                "body":"notes","assets":[\(list.joined(separator: ","))]}
                """
            }
            let newest = release("3.3.8", [
                "reqable-app-windows-x86_64.exe", "reqable-app-windows-x86_64.zip",
            ])
            let mac = release("3.3.9", [
                "reqable-app-android-arm64.apk", "reqable-app-macos-arm64.dmg",
                "reqable-app-windows-x86_64.exe",
            ])
            let body = request.url?.absoluteString.contains("/releases/latest") == true
                ? mac : "[\(newest),\(mac)]"
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
