import Testing
import Foundation
@testable import DuoUpdaterCore

/// Porting Kit's GitHub release bodies are only the tag, so the notes come from
/// the `changelog.html` asset each release carries. The fixture is the head of
/// the real v6.7.0 asset (fetched 2026-10-26) through 6.6.3, then the 6.1.3 /
/// 6.1.2 / 6.1.2 / 6.1.1 run verbatim, where the vendor repeats 6.1.2 with an
/// empty list.
private let portingKitChangelogFixture = """
<HTML><HEAD><style>@media (prefers-color-scheme: dark) {* {color: #ddd;background-color: #222;}}</style></HEAD><BODY>
Porting Kit 6.7.0 (19/11/2025):
<ul>
        <li>Introducing proper Silicon builds</li>
</ul>
Porting Kit 6.6.4 (17/11/2025):
<ul>
\t<li>Removing the 16Gb requirement of Metal ports</li>
\t<li>Drag and drop of icons should work again</li>
\t<li>When changing icons on the Properties window, the new icon should appear</li>
\t<li>Fixing issues with credentials manager</li>
\t<li>Image files should be properly loaded</li>
\t<li>7-zip should work on Silicon Macs again</li>
</ul>
Porting Kit 6.6.3 (06/11/2025):
<ul>
\t<li>Create builds targetting macOS Silicon</li>
\t<li>Trying to fix Tahoe build</li>
</ul>
Porting Kit 6.1.3 (22/03/2024):
<ul>
\t<li>Improving Wine prefix creation</li>
\t<li>Porting Kit should support the new location of the Wineskin.app</li>
</ul>
Porting Kit 6.1.2 (04/03/2024):
<ul>
\t<li>If resolution can't be determined, it shouldn't be changed back</li>
</ul>
Porting Kit 6.1.2 (04/03/2024):
<ul>

</ul>
Porting Kit 6.1.1 (19/01/2024):
<ul>
\t<li>Minor fix in the build process</li>
</ul>
</BODY>
"""

@Test func portingKitChangelogReadsTheReleaseAsset() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.paulthetall.portingkit"))
    let log = try #require(ChangelogService.parse(recipe, body: portingKitChangelogFixture))
    // The vendor's empty repeat of 6.1.2 yields no entry, and does not borrow
    // the next block's lines.
    #expect(log.entries.map(\.version) == ["6.7.0", "6.6.4", "6.6.3", "6.1.3", "6.1.2", "6.1.1"])
    let newest = try #require(log.entries.first)
    #expect(newest.date == "19/11/2025")
    #expect(newest.items == ["Introducing proper Silicon builds"])
    #expect(log.entries[1].items.count == 6)
    #expect(log.entries[1].items.last == "7-zip should work on Silicon Macs again")
    #expect(log.entries[4].items == ["If resolution can't be determined, it shouldn't be changed back"])
    #expect(log.entries[5].items == ["Minor fix in the build process"])
}
