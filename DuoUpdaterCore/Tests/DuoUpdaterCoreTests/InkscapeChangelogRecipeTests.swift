import Testing
import Foundation
@testable import DuoUpdaterCore

/// The shape of `wiki.inkscape.org/wiki/Release_notes/1.4.4`, assembled from the
/// real page (captured 2026-08-16) and trimmed to one item per region. Every
/// region here is a `<li>` that must NOT become a change line, except the two
/// inside the `Changes_and_Bug_Fixes` section.
private let inkscapeWikiFixture = #"""
<h1 id="firstHeading" class="firstHeading" >Release notes/1.4.4</h1>
<div id="bodyContent" class="mw-body-content">
<div class="mw-parser-output"><table><tbody><tr>
<td style="font-weight: bold;"><b>These Release Notes are in Draft Status.</b>
<ul><li><a rel="nofollow" class="external text" href="https://gitlab.com/inkscape/inkscape/commits/1.4.x">Commit History Main Program</a></li>
<li><a rel="nofollow" class="external text" href="https://gitlab.com/inkscape/extensions/-/commits/1.4.x">Commit History Extensions</a></li></ul>
</td></tr></tbody></table>
<div id="toc" class="toc"><div class="toctitle"><h2 id="mw-toc-heading">Contents</h2></div>
<ul>
<li class="toclevel-1 tocsection-1"><a href="#Changes_and_Bug_Fixes"><span class="toctext">Changes and Bug Fixes</span></a></li>
<li class="toclevel-2 tocsection-2"><a href="#Highlights"><span class="toctext">Highlights</span></a></li>
</ul></div>
<h2><span class="mw-headline" id="Changes_and_Bug_Fixes">Changes and Bug Fixes</span></h2>
<h3><span class="mw-headline" id="Crash_Fixes">Crash Fixes</span></h3>
<ul><li>… when creating a new page (Bug #5904, MR #7417)</li>
<li><code>libuemf</code> is now a <b>submodule</b> (MR #7787).</li></ul>
<h2><span class="mw-headline" id="Other_releases">Other releases</span></h2>
<ul><li><a href="/wiki/Release_notes/0.42" title="Release notes/0.42">Inkscape 0.42</a></li>
<li><a href="/wiki/Release_notes/0.41" title="Release notes/0.41">Inkscape 0.41</a></li></ul>
<div class="printfooter">Retrieved from …</div>
</div></div>
"""#

@Suite struct InkscapeChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes
            .first { $0.bundleID == "org.inkscape.Inkscape" })
    }

    @Test func readsOnlyTheChangeSections() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: inkscapeWikiFixture, using: try recipe()))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "1.4.4")
        #expect(entry.items.count == 2)
        #expect(entry.items.first == "… when creating a new page (Bug #5904, MR #7417)")
    }

    /// Three different `<li>` regions on this page are navigation, not changes:
    /// the draft banner's commit-history links, MediaWiki's table of contents,
    /// and the "Other releases" index at the bottom. The first is excluded by
    /// where `body` starts, the last by where it ends, and the TOC by the item
    /// pattern requiring a BARE `<li>` (TOC entries carry `class="toclevel-…"`).
    @Test func navigationListsAreNotChanges() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: inkscapeWikiFixture, using: try recipe()))
        let items = log.entries.flatMap(\.items)
        #expect(!items.contains { $0.contains("Commit History") })
        #expect(!items.contains { $0.contains("Contents") })
        #expect(!items.contains { $0.contains("Inkscape 0.4") })
    }

    @Test func eachPageIsOneRelease() throws {
        let recipe = try self.recipe()
        #expect(recipe.maxEntries == 1)
        #expect(recipe.resolvedSource(forVersion: "1.4.4").absoluteString
            == "https://wiki.inkscape.org/wiki/Release_notes/1.4.4")
    }
}
