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

    /// MediaWiki now nests the page title in spans and puts section ids on h2.
    /// Trimmed from the live 1.4.4 page; navigation stays outside the body.
    @Test func readsCurrentMediaWikiHeadings() throws {
        let fixture = #"""
        <h1 id="firstHeading" class="firstHeading mw-first-heading"><span lang="en" dir="ltr"><span class="mw-page-title-main">Release notes/1.4.4</span></span></h1>
        <ul><li>Commit History Main Program</li></ul>
        <div class="mw-heading mw-heading2"><h2 id="Changes_and_Bug_Fixes">Changes and Bug Fixes</h2></div>
        <div class="mw-heading mw-heading3"><h3 id="Crash_Fixes">Crash Fixes</h3></div>
        <ul><li>… <b>trying to start Inkscape</b> when there are two entries for the same file in the list of recently used files (<a rel="nofollow" class="external text" href="https://gitlab.com/inkscape/inkscape/-/work_items/6002">Bug 6002</a>, <a rel="nofollow" class="external text" href="https://gitlab.com/inkscape/inkscape/-/merge_requests/7750">MR #7750</a>)</li>
        <li>… <b> trying to start Inkscape on Windows</b>, when two recently opened files are in the same folder on different drives (<a rel="nofollow" class="external text" href="https://gitlab.com/inkscape/inkscape/-/work_items/6028">Bug #6028</a>, <a rel="nofollow" class="external text" href="https://gitlab.com/inkscape/inkscape/-/merge_requests/7754">MR #7754</a>)</li></ul>
        <div class="mw-heading mw-heading2"><h2 id="Other_releases">Other releases</h2></div>
        <ul><li>Inkscape 1.5 — development branch</li></ul>
        """#
        let log = try #require(ChangelogExtractor.extract(from: fixture, using: try recipe()))
        let entry = try #require(log.entries.first)
        #expect(log.entries.count == 1)
        #expect(entry.version == "1.4.4")
        #expect(entry.date == nil)
        #expect(entry.items.count == 2)
        #expect(entry.items[0] == "… trying to start Inkscape when there are two entries for the same file in the list of recently used files (Bug 6002, MR #7750)")
        #expect(!entry.items.contains { $0.contains("Commit History") || $0.contains("Inkscape 1.5") })
    }

    @Test func eachPageIsOneRelease() throws {
        let recipe = try self.recipe()
        #expect(recipe.maxEntries == 1)
        #expect(recipe.resolvedSource(forVersion: "1.4.4").absoluteString
            == "https://wiki.inkscape.org/wiki/Release_notes/1.4.4")
    }
}
