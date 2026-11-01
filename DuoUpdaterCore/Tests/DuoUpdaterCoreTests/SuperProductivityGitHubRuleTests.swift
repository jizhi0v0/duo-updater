import Foundation
import Testing

@testable import DuoUpdaterCore

/// Super Productivity's prereleases are tagged with a suffix
/// (`v18.0.0-rc.0`, `v17.0.0-RC.13`, `v15.1.3-rc.0`) and the bundle keeps that
/// suffix in both version keys, so the anchored stable patterns never see one.
/// The trap is the unanchored default pattern: it would read `18.0.0` out of
/// `v18.0.0-rc.0` and offer a two-year-old release.
@Suite struct SuperProductivityGitHubRuleTests {
    private static let id = "com.super-productivity.app"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.id })
    }

    private static func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "Super Productivity", bundleID: id, shortVersion: version,
            buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Super Productivity.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// Mutation: drop the `$` anchor from the rule's pattern → the first two
    /// expectations read versions and fail.
    @Test func releaseCandidateTagsAreNotVersions() throws {
        let pattern = try rule().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: "v18.0.0-rc.0", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "v17.0.0-RC.13", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "v15.1.3-rc.0", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "v19.3.1", pattern: pattern) == "19.3.1")
    }

    /// A 19.3.0 copy is offered 19.3.1's arm64 dmg, never the x64 one beside it.
    @Test func aStableCopyIsOfferedTheArm64Dmg() async throws {
        let source = GitHubReleasesSource(
            rules: [try rule()], session: Self.stubbedSession())
        let remote = try #require(try await source.latestVersion(for: Self.installed("19.3.0")))
        #expect(remote.shortVersion == "19.3.1")
        #expect(remote.downloadURL?.lastPathComponent == "superProductivity-arm64.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
    }

    private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    final class Stub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let base = "https://example.invalid/super-productivity/releases/download/v19.3.1/"
            let assets = ["superProductivity-arm64.dmg", "superProductivity-x64.dmg"].map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v19.3.1","name":"v19.3.1","draft":false,"prerelease":false,\
            "published_at":"2026-10-25T14:42:30Z",\
            "html_url":"https://example.invalid/super-productivity/releases/tag/v19.3.1",\
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
