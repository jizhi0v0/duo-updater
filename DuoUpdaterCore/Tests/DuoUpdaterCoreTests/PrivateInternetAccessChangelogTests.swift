import Foundation
import Testing
@testable import DuoUpdaterCore

struct PrivateInternetAccessChangelogTests {
    private static let bundleID = "com.privateinternetaccess.vpn"

    // Representative HTML using the article and h3 anchors already exercised
    // by the PIA vendor-probe tests. Live validation against the raw vendor
    // page remains required before the recipe is considered production-ready.
    private static let page = #"""
    <article class="changelog-release">
      <ul class="downloads"><li><a href="https://installers.privateinternetaccess.com/download/pia-macos-3.8-08539.zip">Mac ZIP download</a></li></ul>
      <h3 class="text-primary" style="margin-bottom:0px">v3.8.0</h3>
      <h4 class="text-muted">Release Date: October 15, 2026</h4>
      <ul>
        <li>Windows: WireGuard now uses WireGuard-NT</li>
        <li>All: WireGuard is now the default protocol</li>
        <li>Linux/macOS: New WireGuard Amnezia driver</li>
        <li>macOS: Fixed split tunnel &amp; DNS interaction</li>
      </ul>
      <h3>SHA-256 Checksums:</h3>
      <p class="sha256">pia-macos-3.8-08539.zip:<span class="code">824b5a469a7e42a634e98f140e6d31d567d564c8edaa78ebb6b05f0de311008e</span></p>
    </article>
    <article class="changelog-release">
      <h3 class="text-primary" style="margin-bottom:0px">v3.7.2</h3>
      <h4>Release Date: March 19, 2026</h4>
      <ul><li>Connectivity improvements</li></ul>
      <p class="sha256">pia-macos-3.7.2-08420.zip:5677fa</p>
    </article>
    """#

    private static func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID, channel: .stable))
    }

    @Test func readsVersionsDatesAndOnlyReleaseNotes() throws {
        let changelog = try #require(ChangelogExtractor.extract(from: Self.page, using: Self.recipe()))
        #expect(changelog.entries.map(\.version) == ["3.8.0", "3.7.2"])
        #expect(changelog.entries.map(\.date) == ["October 15, 2026", "March 19, 2026"])
        #expect(changelog.entries.map(\.items.count) == [4, 1])
        #expect(changelog.entries[0].items[3] == "macOS: Fixed split tunnel & DNS interaction")
        let text = changelog.entries.flatMap(\.items).joined(separator: "\n")
        #expect(!text.contains("Mac ZIP download"))
        #expect(!text.contains("SHA-256"))
        #expect(!text.contains("pia-macos-"))
        #expect(changelog.entries[1].items == ["Connectivity improvements"])
    }

    @Test func missingDateStillKeepsTheRelease() throws {
        let page = """
        <article class="changelog-release">
          <h3>v3.7.2</h3>
          <ul><li>Connectivity improvements</li></ul>
        </article>
        """
        let changelog = try #require(ChangelogExtractor.extract(from: page, using: Self.recipe()))
        #expect(changelog.entries.map(\.version) == ["3.7.2"])
        #expect(changelog.entries[0].date == nil)
        #expect(changelog.entries[0].items == ["Connectivity improvements"])
    }

    @Test func emptyReleaseCannotBorrowTheNextReleaseNotes() throws {
        let page = """
        <article class="changelog-release">
          <h3>v3.8.0</h3><h4>Release Date: October 15, 2026</h4>
          <p class="sha256">pia-macos-3.8-08539.zip:abc</p>
        </article>
        <article class="changelog-release">
          <h3>v3.7.2</h3><ul><li>Connectivity improvements</li></ul>
        </article>
        """
        let changelog = try #require(ChangelogExtractor.extract(from: page, using: Self.recipe()))
        #expect(changelog.entries.map(\.version) == ["3.7.2"])
        #expect(changelog.entries[0].items == ["Connectivity improvements"])
    }

    @Test func unterminatedArticleCannotSwallowTheNextVersion() throws {
        let page = """
        <article class="changelog-release">
          <h3>v3.8.0</h3><h4>Release Date: October 15, 2026</h4>
          <ul><li>First release's notes</li></ul>
        <article class="changelog-release">
          <h3>v3.7.2</h3><ul><li>Second release's notes</li></ul>
        </article>
        """
        let changelog = try #require(ChangelogExtractor.extract(from: page, using: Self.recipe()))
        #expect(changelog.entries.map(\.version) == ["3.7.2"])
        #expect(changelog.entries[0].items == ["Second release's notes"])
    }

    @Test func unrelatedMarkupDegradesToNil() throws {
        let recipe = try Self.recipe()
        #expect(ChangelogExtractor.extract(from: "<main>Unrecognised page</main>", using: recipe) == nil)
        #expect(ChangelogExtractor.extract(from: "<article class=\"changelog-release\"><h3>v3.8.0</h3>", using: recipe) == nil)
    }

    @Test func betaUsesOnlyPublishedStableHistory() throws {
        let stable = try #require(ChangelogRecipeRegistry.recipe(forBundleID: Self.bundleID, channel: .stable))
        let beta = try #require(ChangelogRecipeRegistry.recipe(forBundleID: Self.bundleID, channel: .beta))
        #expect(stable.source == beta.source)
        #expect(beta.channel == nil)
        let changelog = try #require(ChangelogExtractor.extract(from: Self.page, using: beta))
        #expect(changelog.entries.map(\.version) == ["3.8.0", "3.7.2"])
    }
}
