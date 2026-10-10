import Foundation
import Testing

@testable import DuoUpdaterCore

/// `alfredapp.com/changelog/`, fetched 2026-10-10: the page head, 5.8.1, 5.7.2
/// (a nested list), 5.6 (a section heading), the first early-access entry at the
/// bottom and the end of the section. Lists are cut; every line kept is verbatim.
private let alfredChangelogFixture = #"""
<h1>Change Log</h1>
<p>Please note that the Change Log covers all changes including Powerpack-only features. To enjoy all that Alfred has to offer, be sure to buy a Powerpack license. :)</p>
<hr />
<h2>Alfred 5.8.1</h2>
<p>Build 2349, Thursday 24th September 2026</p>
<ul>
<li>Improved Light Mode support in updated &quot;General&quot; preferences</li>
<li>Updated System Settings search to fix iCloud and General results on macOS 27</li>
<li>Update Google Chrome bookmarks feature to correctly search all bookmarks</li>
</ul>
<h2>Alfred 5.7.2</h2>
<p>Build 2312, Tuesday 9th December 2025</p>
<ul>
<li>File Search fallback ranking overhaul
<ul>
<li>Files will now be requested from macOS in a pre-sorted order</li>
<li>This is due to changes in the underlying metadata index. If you find this affects performance, you can return to the previous behaviour in Alfred's Features &gt; File Search &gt; Search &gt; Default Order</li>
<li>Changed default result limits to 40, 50, 75, 100 to work around sorting issue in default metadata query</li>
</ul></li>
<li>Add support for updated Recent Documents in Tahoe</li>
</ul>
<h2>Alfred 5.6</h2>
<p>Build 2290, Monday 24th February 2025</p>
<h3>Workflow Improvements and Fixes</h3>
<ul>
<li>Added fn+Click shortcut in Workflow Editor to automatically align objects to the selected object
<ul>
<li>Added hint for this in Workflow Editor overlay</li>
</ul></li>
<li>File Actions trigger name</li>
</ul>
<h2>Alfred 5.0 EA3</h2>
<ul>
<li>Fix the palette guide height calculations when macOS Scrollbars are set to &quot;Always&quot;</li>
</ul>

  </div>
  
</section>
"""#

@Test func alfredReadsItsChangelogPage() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.runningwithcrayons.Alfred"))
    let log = try #require(ChangelogExtractor.extract(from: alfredChangelogFixture, using: recipe))

    // The version both update plists carry; "5.0 EA3" is an early-access entry, not one.
    #expect(log.entries.map(\.version) == ["5.8.1", "5.7.2", "5.6"])
    try #require(log.entries.count == 3)
    // The build number ahead of the date is the plists' `build`, not part of the date.
    #expect(log.entries[0].date == "Thursday 24th September 2026")
    #expect(log.entries[0].items.first == "Improved Light Mode support in updated \"General\" preferences")
    // A parent and its children are separate lines.
    #expect(Array(log.entries[1].items.prefix(3)) == [
        "File Search fallback ranking overhaul",
        "Files will now be requested from macOS in a pre-sorted order",
        "This is due to changes in the underlying metadata index. If you find this affects performance, you can return to the previous behaviour in Alfred's Features > File Search > Search > Default Order",
    ])
    #expect(log.entries[2].content.first == .heading("Workflow Improvements and Fixes"))
}

@Test func alfredsPreReleaseCopyReadsTheSamePage() throws {
    // Both plists serve the same version, and the page names no pre-release.
    let stable = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.runningwithcrayons.Alfred"))
    let beta = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.runningwithcrayons.Alfred", channel: .beta))
    #expect(beta.source == stable.source)
}
