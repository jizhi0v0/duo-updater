import Testing
import Foundation
@testable import DuoUpdaterCore

/// The head of `https://obsproject.com/osx_update/notes_stable.html` as served
/// on 2026-10-08, verbatim up to the third `<h2>`: the two `<p>Important:` notices,
/// a hotfix list with a nested sub-bullet, and a second hotfix list.
private let obsStableNotesFixture = #"""
<h1 id="obs-studio-32.2.2">OBS Studio 32.2.2</h1>
<p>Important: NVIDIA users must update their GPU drivers to 570.0 or
newer to continue using NVENC.</p>
<p>Important: Due to an update to Qt, macOS 12 is no longer supported.
For macOS 12, please use OBS Studio 32.1.2.</p>
<h2 id="hotfix-changes">32.2.2 Hotfix Changes</h2>
<ul>
<li>Fixed an issue where plugins might not load properly on the first
start after updating OBS on Windows [notr1ch]</li>
<li>Blocked OBS Studio from running on macOS 12 [RytoEX]
<ul>
<li>Due to a Qt update, OBS Studio 32.2.x fails to launch on macOS 12.
For macOS 12, please use OBS Studio 32.1.2.</li>
</ul></li>
</ul>
<h2 id="hotfix-changes-1">32.2.1 Hotfix Changes</h2>
<ul>
<li>Fixed game capture failing after updating OBS if the previous hook
was still in use [notr1ch]</li>
</ul>
"""#

/// The head of `notes_beta.html` the same day, verbatim up to its second `<h2>`.
/// The `<h1>` names the beta ("33.0.0 Beta 6"); the feed calls the same build
/// `33.0.0`.
private let obsBetaNotesFixture = #"""
<h1 id="obs-studio-33.0.0-beta-6">OBS Studio 33.0.0 Beta 6</h1>
<h2 id="beta-6-changes">Beta 6 Changes</h2>
<ul>
<li>Fixed a crash during certain actions involving groups in Beta 1-5
[prgmitchell]</li>
<li>Fixed scripting not working on macOS in Beta 1-5 [PatTheMav]</li>
<li>Fixed game capture hooks not updating in Beta 1-5 [Warchamp7]</li>
<li>Fixed clock Lua script not working in Beta 1-5 [RytoEX]</li>
<li>Changed Safe Mode to not start WebSocket Server
[FiniteSingularity/RytoEX]</li>
<li>Removed support for FFmpeg 6.x and 7.x [RytoEX]</li>
<li>Removed support for Qt 6.4-6.9 [RytoEX]</li>
</ul>
"""#

@Suite struct OBSChangelogRecipeTests {
    private var recipe: ChangelogRecipe {
        get throws { try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.obsproject.obs-studio")) }
    }

    private func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { if case .heading(let h) = $0 { h } else { nil } }
    }

    @Test func theStablePageIsOneEntryWithItsNoticesFirst() throws {
        let cl = try #require(ChangelogExtractor.extract(from: obsStableNotesFixture, using: try recipe))
        #expect(cl.entries.count == 1)
        let entry = try #require(cl.entries.first)
        #expect(entry.version == "32.2.2")
        #expect(headings(entry) == ["32.2.2 Hotfix Changes", "32.2.1 Hotfix Changes"])
        #expect(entry.items.count == 6)
        #expect(entry.items.first?.hasPrefix("Important: NVIDIA users must update") == true)
        #expect(entry.items[1].hasPrefix("Important: Due to an update to Qt, macOS 12"))
    }

    /// The parent bullet and its sub-bullet stay two lines.
    @Test func aNestedBulletIsNotMergedIntoItsParent() throws {
        let entry = try #require(
            ChangelogExtractor.extract(from: obsStableNotesFixture, using: try recipe)?.entries.first)
        #expect(entry.items.contains("Blocked OBS Studio from running on macOS 12 [RytoEX]"))
        #expect(entry.items.contains { $0.hasPrefix("Due to a Qt update, OBS Studio 32.2.x fails") })
    }

    /// The version is what the feed calls this build, not the page's "Beta 6".
    @Test func theBetaPageTakesTheFeedsVersion() throws {
        let entry = try #require(
            ChangelogExtractor.extract(from: obsBetaNotesFixture, using: try recipe)?.entries.first)
        #expect(entry.version == "33.0.0")
        #expect(headings(entry) == ["Beta 6 Changes"])
        #expect(entry.items.count == 7)
        #expect(entry.items.first == "Fixed a crash during certain actions involving groups in Beta 1-5 [prgmitchell]")
    }

    /// Both channels' pages are this recipe's; the 2023 item's link is not, and
    /// keeps embedding its page.
    @Test func bothChannelsPagesAreAccepted() throws {
        let recipe = try recipe
        for page in ["notes_stable", "notes_beta"] {
            let url = URL(string: "https://obsproject.com/osx_update/\(page).html")
            #expect(recipe.acceptedFeedPage(url) == url)
        }
        #expect(recipe.acceptedFeedPage(URL(string: "https://obsproject.com/osx_update/stable/notes.html")) == nil)
        #expect(recipe.acceptedFeedPage(URL(string: "https://obsproject.com/osx_update/notes_stable.html?x=1")) == nil)
    }
}
