import Foundation
import Testing

@testable import DuoUpdaterCore

/// `repo.jellyfin.org/files/server/macos/latest-stable/arm64/`, fetched
/// 2026-10-16, verbatim.
private let jellyfinLatestStableIndex = #"""
<html>
<head><title>Index of /files/server/macos/latest-stable/arm64/</title></head>
<body>
<h1>Index of /files/server/macos/latest-stable/arm64/</h1><hr><pre><a href="../">../</a>
<a href="jellyfin_12.2-arm64.dmg">jellyfin_12.2-arm64.dmg</a>                            05-Oct-2026 23:56           164659012
<a href="jellyfin_12.2-arm64.tar.xz">jellyfin_12.2-arm64.tar.xz</a>                         05-Oct-2026 23:00            85544588
</pre><hr></body>
</html>
"""#

/// Two releases from `api.github.com/repos/jellyfin/jellyfin/releases`
/// (fetched 2026-10-16), bodies cut by whole lines after the first two change
/// lines of v12.2 and after the intro of v12.0-rc7.
private let jellyfinReleasesFixture = #"""
[
 {
  "tag_name": "v12.2",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-10-05T23:07:59Z",
  "body": "# :rocket: Jellyfin Server 12.2\n\nWe are pleased to announce the latest stable release of Jellyfin, version 12.2! This minor release brings several bugfixes to improve your Jellyfin experience. As always, please ensure you take a full backup before upgrading!\n\nDiscuss this release further [on our forums](https://forum.jellyfin.org/t-new-jellyfin-server-web-release-12-2).\n\n## Changelog (51)\n\n### 📈 General Changes\n* Replace custom item display preferences in one transaction [PR #18266], by @martimarkov\n* Use hvc1 for Dolby Vision profile 8 [PR #18300], by @theopeuchlestrade"
 },
 {
  "tag_name": "v12.0-rc7",
  "prerelease": true,
  "draft": false,
  "published_at": "2026-08-31T23:18:53Z",
  "body": "# :rocket: Jellyfin Server 12.0 RC7\r\n\r\nWe are pleased to announce the seventh release candidate preview release of Jellyfin 12.0! \r\n\r\nThis is a **preview** release, intended for those interested in testing 12.0 before its final public release. We welcome testers to help find as many bugs as we can before the final release."
 }
]
"""#

@Suite struct JellyfinRecipeTests {

    private func recipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "Jellyfin.Server" })
    }

    @Test func readsTheStableDmgFromTheIndex() throws {
        let recipe = try recipe()
        #expect(recipe.channel == .stable)
        #expect(VendorProbeRecipe.extractVersion(
            from: jellyfinLatestStableIndex, pattern: recipe.versionPattern) == "12.2")
    }

    /// Every other file the vendor's macOS tree holds: the tar.xz beside the dmg,
    /// the Intel dmg, an rc dmg under `preview/`, and an unstable build (tar.xz
    /// only, numbered by date). None of them is a stable arm64 dmg.
    @Test func ignoresOtherTracksAndFormats() throws {
        let pattern = try recipe().versionPattern
        for name in [
            "jellyfin_12.2-arm64.tar.xz",
            "jellyfin_12.2-amd64.dmg",
            "jellyfin_12.0-rc7-arm64.dmg",
            "jellyfin_2026101212-arm64.tar.xz",
        ] {
            #expect(VendorProbeRecipe.extractVersion(
                from: #"<a href="\#(name)">\#(name)</a>"#, pattern: pattern) == nil, "\(name)")
        }
        // The three-part versions before the scheme dropped its leading `10.`,
        // and the next major, read too.
        #expect(VendorProbeRecipe.extractVersion(
            from: #"<a href="jellyfin_10.11.11-arm64.dmg">"#, pattern: pattern) == "10.11.11")
        #expect(VendorProbeRecipe.extractVersion(
            from: #"<a href="jellyfin_13.0-arm64.dmg">"#, pattern: pattern) == "13.0")
    }

    /// The scheme change (10.11.11 → 12.0) still orders as an upgrade, an rc copy
    /// is offered its final release, and an rc of a later major is not offered an
    /// older stable.
    @Test func versionOrderAcrossTheSchemeChangeAndRcCopies() {
        #expect(VersionComparator.isNewer("12.2", than: "10.11.11"))
        #expect(VersionComparator.isNewer("12.2", than: "12.0-rc7"))
        #expect(!VersionComparator.isNewer("12.2", than: "13.0-rc1"))
    }

    @Test func installsTheComparedVersionFromItsOwnFolder() throws {
        let install = try #require(try recipe().install)
        #expect(install.kind == .dmg)
        guard case .versionTemplate(let template) = install.urlSource else {
            Issue.record("expected .versionTemplate, got \(install.urlSource)")
            return
        }
        #expect(template
            == "https://repo.jellyfin.org/files/server/macos/stable/v{version}/arm64/jellyfin_{version}-arm64.dmg")
    }

    /// The rc published before 12.0 is a prerelease, and the probe reads the
    /// stable track, so it is not on the rail.
    @Test func changelogReadsStableReleasesOnly() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "Jellyfin.Server"))
        let log = try #require(ChangelogService.parse(recipe, body: jellyfinReleasesFixture))
        #expect(log.entries.map(\.version) == ["12.2"])
        #expect(log.entries.first?.items == [
            "Replace custom item display preferences in one transaction [PR #18266], by @martimarkov",
            "Use hvc1 for Dolby Vision profile 8 [PR #18300], by @theopeuchlestrade",
        ])
    }
}
