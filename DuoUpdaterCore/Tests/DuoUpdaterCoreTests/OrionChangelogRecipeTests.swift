import Foundation
import Testing

@testable import DuoUpdaterCore

/// Six release headings of `orionbrowser.com/updates/orion-release-notes.html`,
/// fetched 2026-10-10, in page order but not contiguous: 1.1.3, the 1.1.2 hotfix
/// (151) and 1.1.2 (150) from the top; an RC block from the 1.0.x era and one from
/// 0.99.x; and 0.99.131.0.2, in the pre-1.0 layout whose sections are `<h2>`s.
/// Each list is cut to its first two items; the kept bytes are verbatim.
private let orionChangelogFixture = #"""
<h2 class="divider" id="macos-orion-1-1-3-152"><b>Orion 1.1.3 (152)</b> ✴︎ Sep 28, 2026</h2>
    <h3>Legacy macOS fixes</h3>
    <ul>
      <li>All Windows From Previous Session not preserved on upgrade to Orion 1.1 <a href="https://orionfeedback.org/d/14101" rel="noopener noreferrer">#14101</a> by @bzgnyc</li>
      <li>[Mojave] Look Up doesn't work <a href="https://orionfeedback.org/d/4772" rel="noopener noreferrer">#4772</a> by @orionuser6651</li>
    </ul>
    <h3>Other improvements and bug fixes</h3>
    <ul>
      <li>Navigation Arrows Dropping Down <a href="https://orionfeedback.org/d/14562" rel="noopener noreferrer">#14562</a> by @thefella</li>
      <li>Pin tab in unsave window showing up in saved tab group and very mess up <a href="https://orionfeedback.org/d/14356" rel="noopener noreferrer">#14356</a> by @JSiuDev</li>
    </ul>
  
    <h2 class="divider" id="macos-orion-1-1-2-151"><b>Orion 1.1.2 (151) - hotfix</b> ✴︎ Aug 18, 2026</h2>
    <h3>Improvements and bug fixes</h3>
    <ul>
      <li>Cannot open Orion after update to 1.1.2.150 MacOS version <a href="https://orionfeedback.org/d/14419" rel="noopener noreferrer">#14419</a> @Wartybliggens</li>
      <li>Fix pdf zoom support for MacOS touchpad <a href="https://orionfeedback.org/d/9262" rel="noopener noreferrer">#9262</a> @PengKen</li>
    </ul>
    <h2 class="divider" id="macos-orion-1-1-2-150"><b>Orion 1.1.2 (150)</b> ✴︎ Aug 17, 2026</h2>
    <h3>Improvements and bug fixes</h3>
    <ul>
      <li>Orion Browser keeps crashing due to tab number <a href="https://orionfeedback.org/d/13924" rel="noopener noreferrer">#13924</a> @KoroKara</li>
      <li><code>&lt;html&gt;</code> height and width ignored for extension popups <a href="https://orionfeedback.org/d/14111" rel="noopener noreferrer">#14111</a> @jeurissen</li>
    </ul>
  
    <h2 class="divider" id="macos-orion-1-0-4-143-2"><b>Orion RC 1.0.4.143.2</b> ✴︎ Mar 4, 2026</h2>
      In this release:
      <ul>
        <li>Google login popup show the the left of the screen <a href="https://orionfeedback.org/d/12705">#12705</a> @JSiuDev</li>
        <li>Fix Page Summary Not Working <a href="https://orionfeedback.org/d/13118">#13118</a> @fredcy</li>
      </ul>
      <h2 class="divider" id="macos-orion-rc-0-99-137-3">Orion RC 0.99.137.3 - Nov 14, 2025</h2>
      In this release:
      <ul>
        <li>::ERR_BLOCKED_BY_CLIENT error when accessing seemingly random websites <a href="https://orionfeedback.org/d/12269">#12269</a> @esiayo</li>
        <li>Google sheets formulae causes error <a href="https://orionfeedback.org/d/12162">#12162</a> @Tacketh</li>
      </ul>

            <h2 class="divider" id="macos-orion-0-99-131-0-2">Orion 0.99.131.0.2 - Mar 11, 2025</h2><h2>Improvements and bug fixes</h2><ul><li>Orion-specific issues with runbot.odoo.com @Zuilin</li><li>New Orion RC Crash <a href="https://orionfeedback.org/d/10040">#10040</a> @kfo21</li></ul>
  </main>
"""#

@Test func orionReadsStableReleasesInBothLayouts() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.kagi.kagimacOS"),
        "Orion changelog recipe must exist")
    let log = try #require(ChangelogExtractor.extract(from: orionChangelogFixture, using: recipe))

    // The RC blocks are skipped; the build in parentheses is dropped, and the
    // hotfix suffix becomes a title so both 1.1.2 builds keep their notes.
    #expect(log.entries.map(\.version) == ["1.1.3", "1.1.2", "1.1.2", "0.99.131.0.2"])
    #expect(log.entries.map(\.title) == [nil, "hotfix", nil, nil])
    #expect(log.entries.map(\.date) == ["Sep 28, 2026", "Aug 18, 2026", "Aug 17, 2026", "Mar 11, 2025"])

    let top = log.entries[0]
    #expect(top.items.count == 4)
    #expect(top.items.first
        == "All Windows From Previous Session not preserved on upgrade to Orion 1.1 #14101 by @bzgnyc")
    let headings = top.content.compactMap { block -> String? in
        if case .heading(let text) = block { return text } else { return nil }
    }
    #expect(headings == ["Legacy macOS fixes", "Other improvements and bug fixes"])
    // An escaped tag inside <code> survives as text.
    #expect(log.entries[2].items[1]
        == "<html> height and width ignored for extension popups #14111 @jeurissen")
    // In the old layout the section <h2> stays inside the entry as a heading.
    #expect(log.entries[3].items == [
        "Orion-specific issues with runbot.odoo.com @Zuilin", "New Orion RC Crash #10040 @kfo21",
    ])
}
