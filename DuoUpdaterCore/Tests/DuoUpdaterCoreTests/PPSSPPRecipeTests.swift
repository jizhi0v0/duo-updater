import Foundation
import Testing

@testable import DuoUpdaterCore

struct PPSSPPRecipeTests {
    // The vendor download page offers Gold before the free button. The
    // previous-releases table also repeats the free DMG without button classes.
    private let downloadPage = #"""
        <a class="download-button button-block button-gold"  href="https://www.ppsspp.org/api/goldfiles/1_20_4/PPSSPPGold_macOS.dmg">
        <a class="download-button button-block "  href="https://www.ppsspp.org/files/1_20_4/PPSSPP_macOS.dmg">
        <a href="https://www.ppsspp.org/files/1_20_3/PPSSPP_macOS.dmg">
        """#

    @Test func currentFreeMacButtonSuppliesBothVersionAndInstaller() throws {
        let recipe = try #require(org_ppsspp_ppsspp.set.probes.first)
        let install = try #require(recipe.install)
        #expect(recipe.bundleID == "org.ppsspp.ppsspp")
        #expect(recipe.channel == .stable)
        #expect(install.kind == .dmg)
        guard case .bodyPattern(let assetPattern) = install.urlSource else {
            Issue.record("expected the URL to come from the downloads page")
            return
        }
        #expect(VendorProbeRecipe.extractVersion(
            from: downloadPage, pattern: recipe.versionPattern) == "1.20.4")
        #expect(VendorProbeRecipe.extractVersion(
            from: downloadPage, pattern: assetPattern)
            == "https://www.ppsspp.org/files/1_20_4/PPSSPP_macOS.dmg")

        let noCurrentFreeButton = downloadPage.replacingOccurrences(
            of: #"class="download-button button-block "  href="https://www.ppsspp.org/files/"#,
            with: #"href="https://www.ppsspp.org/files/"#)
        #expect(VendorProbeRecipe.extractVersion(
            from: noCurrentFreeButton, pattern: recipe.versionPattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: noCurrentFreeButton, pattern: assetPattern) == nil)

        let twoComponents = downloadPage.replacingOccurrences(of: "/1_20_4/PPSSPP_macOS", with: "/1_20/PPSSPP_macOS")
        #expect(VendorProbeRecipe.extractVersion(
            from: twoComponents, pattern: recipe.versionPattern) == "1.20")
    }

    @Test func stableRecipeRequiresANormalReleaseVersion() throws {
        let recipe = try #require(org_ppsspp_ppsspp.set.probes.first)
        #expect(recipe.matchesInstalled(version: "1.20.3"))
        #expect(recipe.matchesInstalled(version: "1.20.4"))
        #expect(!recipe.matchesInstalled(version: "1.20.4-4696-g79e845c4d0fc"))
        #expect(!recipe.matchesInstalled(version: nil))
    }

    @Test func releaseIndexFollowsTheTitleLinkForSharedPatchArticles() throws {
        let recipe = try #require(org_ppsspp_ppsspp.set.changelogs.first)
        let pattern = try #require(recipe.indexLinkPattern)
        let index = #"""
            <li><a href="/news/release-1.19/" class="nav-tree-item ">PPSSPP 1.19</a></li>
            <h2 id="release-1.20" class="h1-style">
                <a href="/news/release-1.20/">PPSSPP 1.20.3</a>
            </h2>
            """#
        #expect(ChangelogService.firstLink(in: index, pattern: pattern, base: recipe.source)?
            .absoluteString == "https://www.ppsspp.org/news/release-1.20/")
    }

    @Test func detailedNotesPreserveCategoriesAndPatchVersions() throws {
        let recipe = try #require(org_ppsspp_ppsspp.set.changelogs.first)
        let detail = #"""
            <article class="article" aria-labelledby="release-1.20">
            <h2 id="detailed-changelog" class="center-vertical">Detailed changelog</h2>
            <h3 id="what-s-new-in-1-20-3" class="center-vertical">What's new in 1.20.3</h3>
            <ul><li>A patch fix without a category.</li></ul>
            <h3 id="what-s-new-in-1-20-1" class="center-vertical">What's new in 1.20.1</h3>
            <ul><li><p>User interface</p>
            <ul><li>New feature: Portrait Mode.</li></ul>
            </li><li><p>Regression fixes</p>
            <ul><li>Soundtrack is working again in Tony Hawk's Project 8.</li></ul>
            </li></ul>
            </article>
            <footer><ul><li>Community</li></ul></footer>
            """#
        let changelog = try #require(ChangelogExtractor.extract(from: detail, using: recipe))
        #expect(changelog.entries.map(\.version) == ["1.20.3", "1.20.1"])
        #expect(changelog.entries.first?.items == ["A patch fix without a category."])
        #expect(changelog.entries.last?.content == [
            .heading("User interface"),
            .note("New feature: Portrait Mode."),
            .heading("Regression fixes"),
            .note("Soundtrack is working again in Tony Hawk's Project 8."),
        ])
    }
}
