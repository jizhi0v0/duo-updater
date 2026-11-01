import Foundation
import Testing

@testable import DuoUpdaterCore

/// GitUp's continuous builds are GitHub prereleases tagged by BUILD NUMBER
/// (`b1059`) whose bundle says the next marketing version (1.6.0). The stable
/// rule must never read a build tag as a release, and a copy installed from one
/// must never be offered an older stable version.
@Suite struct GitUpGitHubRuleTests {
    private static let id = "co.gitup.mac"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.id })
    }

    private static func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "GitUp", bundleID: id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-GitUp.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// Mutation: drop the `v` and the pattern becomes `b1059`-friendly if it is
    /// broadened to `[0-9]`; as written, build tags never read as versions.
    @Test func buildNumberTagsAreNotReleases() throws {
        let pattern = try rule().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: "b1059", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "b1058", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "v1.5.0", pattern: pattern) == "1.5.0")
        #expect(VendorProbeRecipe.extractVersion(from: "v1.3", pattern: pattern) == "1.3")
    }

    /// A 1.4.3 copy is offered 1.5.0's universal zip; the current copy is
    /// up to date.
    @Test func theStableAnswerIsTheUniversalZip() async throws {
        let source = GitHubReleasesSource(
            rules: [try rule()], session: Self.stubbedSession())
        let remote = try #require(try await source.latestVersion(for: Self.installed("1.4.3")))
        #expect(remote.shortVersion == "1.5.0")
        #expect(remote.downloadURL?.lastPathComponent == "GitUp.zip")
        #expect(remote.vendorInstallerKind == .zip)
        let current = try #require(try await source.latestVersion(for: Self.installed("1.5.0")))
        #expect(UpdateChecker.evaluate(installed: Self.installed("1.5.0"), remote: current)
                == .upToDate)
    }

    /// A continuous copy (1.6.0, build 1059) is ahead of the stable line: the
    /// stable answer is 1.5.0, and the policy reads it as up to date rather than
    /// as a downgrade. Mutation: have the rule accept `b…` tags → the resolved
    /// version becomes 1.6.0 and this expectation's premise changes.
    @Test func aContinuousCopyIsNotDowngraded() async throws {
        let source = GitHubReleasesSource(
            rules: [try rule()], session: Self.stubbedSession())
        let remote = try #require(try await source.latestVersion(for: Self.installed("1.6.0")))
        #expect(remote.shortVersion == "1.5.0")
        #expect(!VersionComparator.isNewer(remote.shortVersion ?? "0", than: "1.6.0"))
        #expect(UpdateChecker.evaluate(installed: Self.installed("1.6.0"), remote: remote)
                == .upToDate)
    }

    private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    /// `/releases/latest` answers v1.5.0 with the one universal `GitUp.zip`.
    final class Stub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let release = """
            {"tag_name":"v1.5.0","name":"v1.5.0","draft":false,"prerelease":false,\
            "published_at":"2026-07-15T01:07:50Z",\
            "html_url":"https://example.invalid/GitUp/releases/tag/v1.5.0",\
            "body":"notes","assets":[{"name":"GitUp.zip",\
            "browser_download_url":"https://example.invalid/GitUp/releases/download/v1.5.0/GitUp.zip",\
            "size":4789559}]}
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
