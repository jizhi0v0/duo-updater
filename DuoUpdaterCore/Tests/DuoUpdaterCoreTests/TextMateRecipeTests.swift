import Foundation
import Testing

@testable import DuoUpdaterCore

/// TextMate 2 (`com.macromates.TextMate`): one `TextMate_<version>.tbz` per
/// release on GitHub, prereleases on the same tag shape, and GitHub releases
/// from 2013–2018 tagged `v2.0-alpha.N` / `v2.0-beta.N` / `v2.0-rc.N` that are
/// NOT flagged prerelease. The release notes come from the vendor's own
/// `Changes.md` at the release's tag.
@Suite struct TextMateRecipeTests {
    private static let id = "com.macromates.TextMate"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.id })
    }

    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == Self.id })
    }

    private static func installed(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "TextMate", bundleID: id, shortVersion: version, buildVersion: "9800",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-TextMate.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    // MARK: - Version pattern

    /// Every stable tag the vendor has published reads as its version, two-part
    /// `v2.0` included, and so does a next major. The non-prerelease alpha/beta/rc
    /// tags never read as `2.0`. Mutation: drop the `$` anchor → `v2.0-rc.10`
    /// reads `2.0`.
    @Test func versionPatternReadsReleaseTagsOnly() throws {
        let pattern = try rule().versionPattern
        let read = { VendorProbeRecipe.extractVersion(from: $0, pattern: pattern) }
        #expect(read("v2.0.23") == "2.0.23")
        #expect(read("v2.0.19") == "2.0.19")
        #expect(read("v2.0") == "2.0")
        #expect(read("v3.0.0") == "3.0.0")
        #expect(read("v2.0-rc.10") == nil)
        #expect(read("v2.0-beta.12.4") == nil)
        #expect(read("v2.0-alpha.9561") == nil)
    }

    // MARK: - One-click

    /// The `.tbz` is the release's only asset; it installs as `.tarGz`, which
    /// `ArchiveExtractor` unpacks with `tar -xf` (bzip2 detected by content).
    @Test func theTarballIsTheInstallAsset() async throws {
        let source = GitHubReleasesSource(rules: [try rule()], session: Self.stubbedSession())
        let remote = try #require(try await source.latestVersion(for: Self.installed("2.0.19")))
        #expect(remote.shortVersion == "2.0.23")
        #expect(remote.downloadURL?.lastPathComponent == "TextMate_2.0.23.tbz")
        #expect(remote.vendorInstallerKind == .tarGz)
    }

    /// A copy installed from a prerelease (2.0.22, plain version) or an old
    /// release candidate is offered the stable graduation.
    @Test func prereleaseCopiesAreOfferedTheStableRelease() async throws {
        let source = GitHubReleasesSource(rules: [try rule()], session: Self.stubbedSession())
        for version in ["2.0.22", "2.0-rc.31"] {
            let remote = try #require(try await source.latestVersion(for: Self.installed(version)))
            #expect(remote.shortVersion == "2.0.23")
        }
    }

    // MARK: - Changelog

    /// The vendor's notes are read at the release's tag: `master`'s copy stops a
    /// release early.
    @Test func changelogFollowsTheReleaseTag() throws {
        let recipe = try recipe()
        #expect(recipe.resolvedSource(forVersion: "2.0.23").absoluteString
            == "https://raw.githubusercontent.com/textmate/textmate/v2.0.23/Applications/TextMate/about/Changes.md")
    }

    /// Prerelease entries stay in (they carry the substance of 2.0.23), the
    /// compare links flatten, the `###` group heading inside an entry does not
    /// end it, and the oldest heading shape (a linked version) still parses.
    /// Mutation: end entries on `\n#` → the 2.0 entry loses its last bullet.
    @Test func parsesTheVendorChangesFile() throws {
        let log = try #require(ChangelogExtractor.extract(from: Self.changes, using: try recipe()))
        #expect(log.entries.map(\.version) == ["2.0.23", "2.0.22", "2.0", "2.0-beta.1"])
        #expect(log.entries.map(\.date) == ["2021-10-12", "2021-04-16", "2019-09-15", "2014-10-16"])
        #expect(log.entries[0].items == ["Miscellaneous improvements, see changes since v2.0.22 on GitHub"])
        #expect(log.entries[1].items.count == 2)
        #expect(log.entries[1].items.last == "See all changes since v2.0.21")
        #expect(log.entries[2].items == ["First bullet before the group heading.",
                                         "Bullet after the group heading."])
        #expect(log.entries[3].items == ["Oldest heading shape."])
    }

    /// Trimmed from `Applications/TextMate/about/Changes.md` at `v2.0.23`.
    private static let changes = """
    Title: Release Notes

    # Changes

    ## 2021-10-12 (v2.0.23)

    * Miscellaneous improvements, [see changes since v2.0.22 on GitHub](https://github.com/textmate/textmate/compare/v2.0.22...v2.0.23)

    ## 2021-04-16 (v2.0.22)

    * A few more tweaks to improve things on macOS 11 including dropping use of floating header rows in file browser (SCM Status) and search results, as these appear to cause problems on Big Sur.
    * See [all changes since v2.0.21](https://github.com/textmate/textmate/compare/v2.0.21...v2.0.22)

    ## 2019-09-15 (v2.0)

    * First bullet before the group heading.

    ### Other Changes

    After far too long, there is no longer any qualifier suffix in the version string.

    * Bullet after the group heading.

    ## 2014-10-16 ([v2.0-beta.1](https://github.com/textmate/textmate/compare/v2.0-alpha.9575...v2.0-beta.1))

    * Oldest heading shape.
    """

    // MARK: - Stub

    private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    /// `/releases/latest` answers v2.0.23 (GitHub's latest skips prereleases);
    /// the list answers it newest-first above the v2.0.22 prerelease.
    final class Stub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        private static func release(_ version: String, prerelease: Bool) -> String {
            let name = "TextMate_\(version).tbz"
            let url = "https://example.invalid/textmate/releases/download/v\(version)/\(name)"
            return """
            {"tag_name":"v\(version)","name":"v\(version)","draft":false,"prerelease":\(prerelease),\
            "published_at":"2021-10-12T20:16:36Z",\
            "html_url":"https://example.invalid/textmate/releases/tag/v\(version)",\
            "body":"notes","assets":[{"name":"\(name)","browser_download_url":"\(url)","size":18019467}]}
            """
        }

        override func startLoading() {
            let latest = Self.release("2.0.23", prerelease: false)
            let body = request.url?.absoluteString.contains("/releases/latest") == true
                ? latest : "[\(latest),\(Self.release("2.0.22", prerelease: true))]"
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
