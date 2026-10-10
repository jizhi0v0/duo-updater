import Foundation
import Testing

@testable import DuoUpdaterCore

/// The changelog section of `sublimemerge.com/download`, fetched 2026-10-10: the
/// current build, 2130 (with section headings) and the first build at the bottom.
/// Lists are cut; every line kept is verbatim.
private let sublimeMergeChangelogFixture = #"""
	<h2>Changelog</h2>
	<article class="current">
<h3>Build 2132</h3>
<div class="release-date">18 September 2026</div>
<ul>
    <li>Added option to keep local changes when resetting</li>
    <li>Mac: Fixed window styling for macOS 27</li>
</ul>
</article>

<article>
<h3>Build 2130</h3>
<div class="release-date">14 September 2026</div>
<h3>New Features and Improvements</h3>
<ul class="topic">
    <li>Added <tt>submodule_head</tt> context variable for custom commands</li>
</ul>

<h3>Fixes</h3>
<ul class="topic">
    <li>Fixed stash operations failing when a branch named "stash" exists</li>
</ul>
</article>

<article>
<h3>Build 1055</h3>
<div class="release-date">20 September 2018</div>
<ul>
    <li>Welcome!</li>
</ul>
</article>
"""#

@Test func sublimeMergeReadsTheChangelogOnItsDownloadPage() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.sublimemerge"))
    let log = try #require(ChangelogExtractor.extract(from: sublimeMergeChangelogFixture, using: recipe))

    // The full "Build NNNN", the string the probe offers and the bundle reports.
    // The section <h3>s inside 2130 are not versions.
    #expect(log.entries.map(\.version) == ["Build 2132", "Build 2130", "Build 1055"])
    try #require(log.entries.count == 3)
    #expect(log.entries[0].date == "18 September 2026")
    #expect(log.entries[0].items == [
        "Added option to keep local changes when resetting",
        "Mac: Fixed window styling for macOS 27",
    ])
    #expect(log.entries[1].items == [
        "Added submodule_head context variable for custom commands",
        "Fixed stash operations failing when a branch named \"stash\" exists",
    ])
    #expect(log.entries[1].content.first == .heading("New Features and Improvements"))
}
