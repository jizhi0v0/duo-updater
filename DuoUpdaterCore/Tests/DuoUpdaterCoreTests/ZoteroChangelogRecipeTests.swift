import Foundation
import Testing

@testable import DuoUpdaterCore

/// `zotero.org/support/changelog`, fetched 2026-10-10: the page head, 10.0.6,
/// 10.0.4 (a paragraph before its list), 10.0.2 (a developer sub-section), the
/// "Older Changes" link and the end of the article. Lists are cut; every line kept
/// is verbatim.
private let zoteroChangelogFixture = #"""
    <h1 id="zotero_version_history">Zotero Version History<a class="headerlink" href="#zotero_version_history" title="Permanent link">#</a></h1>
<p>Changes in released versions of Zotero 10.0 are documented on this page. To follow development, see the <a href="https://github.com/zotero/zotero/commits/">commit log on GitHub</a>. More recent changes may be available in a <a href="/support/beta_builds">beta build</a>.</p>
<h2 id="changes_in_1006_october_7_2026">Changes in 10.0.6 (October 7, 2026)<a class="headerlink" href="#changes_in_1006_october_7_2026" title="Permanent link">#</a></h2>
<ul>
<li>Fixed Find Full Text not finding files on some sites</li>
<li>[Developer] Local API: Decode <code>+</code> as a space in form-encoded requests</li>
</ul>
<h2 id="changes_in_1004_september_22_2026">Changes in 10.0.4 (September 22, 2026)<a class="headerlink" href="#changes_in_1004_september_22_2026" title="Permanent link">#</a></h2>
<p><em>Zotero for Mac only</em></p>
<ul>
<li>Restored old Zotero Connector for Safari for macOS 11 Big Sur and macOS 12 Monterey</li>
</ul>
<h2 id="changes_in_1002_september_9_2026">Changes in 10.0.2 (September 9, 2026)<a class="headerlink" href="#changes_in_1002_september_9_2026" title="Permanent link">#</a></h2>
<ul>
<li>Fixed “false” appearing in Added By/Modified By columns for trashed collections</li>
</ul>
<h3 id="developer-specific_changesfixes">Developer-specific changes/fixes<a class="headerlink" href="#developer-specific_changesfixes" title="Permanent link">#</a></h3>
<ul>
<li><a href="/support/dev/zotero_10_for_developers#singular_selection_getters">Singular selection getters</a> such as <code>CollectionTree#getSelectedSearch()</code> no longer throw when a single row is selected in the collections list; plugins should still be updated to use the new plural getters</li>
</ul>
<h2 id="older_changes">Older Changes<a class="headerlink" href="#older_changes" title="Permanent link">#</a></h2>
<p><a href="/support/9.0_changelog">View the 9.0 changelog</a></p>
  </article>
"""#

@Test func zoteroReadsItsVersionHistory() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.zotero.zotero"))
    let log = try #require(ChangelogExtractor.extract(from: zoteroChangelogFixture, using: recipe))

    // "Older Changes" is a link to the previous major's page, not an entry.
    #expect(log.entries.map(\.version) == ["10.0.6", "10.0.4", "10.0.2"])
    try #require(log.entries.count == 3)
    #expect(log.entries.map(\.date) == ["October 7, 2026", "September 22, 2026", "September 9, 2026"])
    #expect(log.entries[0].items == [
        "Fixed Find Full Text not finding files on some sites",
        "[Developer] Local API: Decode + as a space in form-encoded requests",
    ])
    // The paragraph ahead of the list is a note of its own.
    #expect(log.entries[1].items == [
        "Zotero for Mac only",
        "Restored old Zotero Connector for Safari for macOS 11 Big Sur and macOS 12 Monterey",
    ])
    // The developer sub-section is a heading, without the permalink's "#".
    #expect(log.entries[2].content.contains(.heading("Developer-specific changes/fixes")))
    #expect(log.entries[2].items.count == 2)
}
