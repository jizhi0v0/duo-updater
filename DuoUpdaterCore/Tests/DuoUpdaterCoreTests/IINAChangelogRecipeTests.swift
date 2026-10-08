import Testing
import Foundation
@testable import DuoUpdaterCore

/// `https://www.iina.io/release-note/1.5.0.html` as served on 2026-10-08 (the
/// head of both appcasts that day), cut down by whole lines: every section keeps
/// its `<h3>` and one or two of its `<li>`s, including two with nested sub-bullets,
/// and the intro and the trailing deprecation notice are kept as served.
private let stableFixture = #"""
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">
    <link rel="stylesheet" type="text/css" href="common.css">
    <title>IINA 1.5.0</title>
</head>

<body>
    <h2>IINA 1.5.0</h2>
    <p>IINA 1.5.0 introduces the biggest interface redesign since its launch. Check out our new website at <a href="https://iina.io">iina.io</a> and read our <a href="https://iina.io/blog/150-release/">blog post</a> about the 1.5.0 release!</p>
    <h3>New</h3>
    <ul class="fl">
        <li class="n">Added a new Settings window <a href="https://github.com/iina/iina/issues/6016">#6016</a>.<ul><li>Added a confirmation prompt when deleting keybinding config files <a href="https://github.com/iina/iina/issues/5972">#5972</a>.</li><li>Split the &quot;Video/Audio&quot; settings page into two pages <a href="https://github.com/iina/iina/issues/5310">#5310</a>.</li><li>Added a new plugin store in Settings <a href="https://github.com/iina/iina/issues/6081">#6081</a>.</li></ul></li>
        <li class="n">You can now unshuffle the playlist if it hasn&#x27;t changed since the last shuffle <a href="https://github.com/iina/iina/issues/6171">#6171</a>.</li>
    </ul>
    <h3>Bug Fixes</h3>
    <ul class="fl">
        <li class="f">Fixed OSC freeze when interacting with UI (slider, button, etc.) <a href="https://github.com/iina/iina/issues/168">#168</a>.</li>
        <li class="f">Fixed unintended auto-play when connecting or switching Bluetooth devices <a href="https://github.com/iina/iina/issues/6025">#6025</a>.</li>
    </ul>
    <h3>Improvements</h3>
    <ul class="fl">
        <li class="e">Revamped the playback history window <a href="https://github.com/iina/iina/issues/6117">#6117</a>.<ul><li>The history window now shows the media title <a href="https://github.com/iina/iina/issues/6113">#6113</a>.</li></ul></li>
    </ul>
    <h3>Updates</h3>
    <ul class="fl">
        <li class="u">Updated mpv to 0.41.0 and FFmpeg to 9.0.1 <a href="https://github.com/iina/iina/issues/6261">#6261</a>.<ul><li>Added the new <code>--sub-border-style</code> option from mpv 0.39.0, <a href="https://github.com/iina/iina/issues/6305">#6305</a>.</li></ul></li>
    </ul>
    <h3>Plugin API</h3>
    <ul class="fl">
        <li class="p">Added plugin i18n support.</li>
    </ul>
    <p><strong>Deprecation Notice</strong><br>IINA 1.5.0 now requires macOS 11 Big Sur or later for Intel Macs and macOS 12 Monterey or later for Apple Silicon Macs. Due to limitations of Xcode, we expect to deprecate macOS 11 in the following IINA release.</p>
</body>

</html>
"""#

/// `https://www.iina.io/release-note/1.5.0-beta2.html` as served on 2026-10-08,
/// whole and unedited: the page `appcast-beta.xml` links for build 172. No intro
/// paragraph; the version carries its `-beta2` suffix.
private let betaFixture = #"""
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">
    <link rel="stylesheet" type="text/css" href="common.css">
    <title>IINA 1.5.0-beta2</title>
</head>

<body>
    <h2>IINA 1.5.0-beta2</h2>
    <h3>New</h3>
    <ul class="fl">
        <li class="n">Added support for <code>tone-mapping-param</code> <a href="https://github.com/iina/iina/issues/6338">#6338</a>.</li>
    </ul>
    <h3>Bug Fixes</h3>
    <ul class="fl">
        <li class="f">Fixed duration text field not using monospaced digit font in main window <a href="https://github.com/iina/iina/issues/6322">#6322</a>.</li>
        <li class="f">Fixed adjusting bold/italic doesn&#x27;t work, and font space/blur not updated continously <a href="https://github.com/iina/iina/issues/6326">#6326</a>.</li>
        <li class="f">Fixed the settings sidebar cannot scroll to bottom on macOS 11 <a href="https://github.com/iina/iina/issues/6320">#6320</a>.</li>
        <li class="f">Fixed wrong legacy full screen housing adjustment <a href="https://github.com/iina/iina/issues/6325">#6325</a>.</li>
        <li class="f">Fixed edit/delete buttons in key mapping disappear after scrolling <a href="https://github.com/iina/iina/issues/6329">#6329</a>.</li>
        <li class="f">Fixed plugin links cannot be opened <a href="https://github.com/iina/iina/issues/6329">#6329</a>.</li>
        <li class="f">Fixed &quot;Default&quot; and &quot;None&quot; in the sidebar not localized <a href="https://github.com/iina/iina/issues/6340">#6340</a>.</li>
        <li class="f">Fixed unwanted scroll actions on sliders <a href="https://github.com/iina/iina/issues/6324">#6324</a>.</li>
        <li class="f">Fixed artist and album info sometimes not being updated for Now Playing <a href="https://github.com/iina/iina/issues/6364">#6364</a>.</li>
        <li class="f">Fixed window size broken after returning from full screen <a href="https://github.com/iina/iina/issues/6361">#6361</a>.</li>
        <li class="f">Fixed misaligned filename text field on the titlebar for macOS 15 and below.</li>
        <li class="f">Fixed dragging multiple media onto initial window always opening them in one player window <a href="https://github.com/iina/iina/issues/6281">#6281</a>.</li>
        <li class="f">Fixed legacy full screen camera housing issues <a href="https://github.com/iina/iina/issues/6201">#6201</a>.</li>
        <li class="f">Fixed ICC profile not properly applied <a href="https://github.com/iina/iina/issues/6334">#6334</a>.</li>
    </ul>
    <h3>Improvements</h3>
    <ul class="fl">
        <li class="e">Disable ytdl section when the online media plugin is enabled.</li>
        <li class="e">Now the width of the sidebar in the settings window is fixed <a href="https://github.com/iina/iina/issues/6299">#6299</a>.</li>
        <li class="e">The settings window is now not movable by background <a href="https://github.com/iina/iina/issues/6323">#6323</a>.</li>
        <li class="e">Don&#x27;t allow removing black bars in full screen <a href="https://github.com/iina/iina/issues/6280">#6280</a>.</li>
        <li class="e">Don&#x27;t show permission alert when the plugin requires no permission.</li>
    </ul>
    <h3>Plugin API</h3>
    <ul class="fl">
        <li class="p">Fixed a crash when trying to open a URL <a href="https://github.com/iina/iina/issues/6230">#6230</a>.</li>
        <li class="p">Fixed various permission issues <a href="https://github.com/iina/iina/issues/6372">#6372</a>.</li>
        <li class="p">Use main branch to check for updates.</li>
    </ul>
    <p><strong>Deprecation Notice</strong><br>IINA 1.5.0 now requires macOS 11 Big Sur or later for Intel Macs and macOS 12 Monterey or later for Apple Silicon Macs. Due to limitations of Xcode, we expect to deprecate macOS 11 in the following IINA release.</p>
</body>

</html>
"""#

@Suite struct IINAChangelogRecipeTests {
    private var recipe: ChangelogRecipe {
        get throws { try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.colliderli.iina")) }
    }

    private func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { if case .heading(let h) = $0 { h } else { nil } }
    }

    /// Mutation: remove `headingPattern` — the six headings disappear.
    @Test func theStablePageIsOneEntryWithItsSections() throws {
        let cl = try #require(ChangelogExtractor.extract(from: stableFixture, using: try recipe))
        #expect(cl.entries.count == 1)
        let entry = try #require(cl.entries.first)
        #expect(entry.version == "1.5.0")
        #expect(headings(entry) == ["New", "Bug Fixes", "Improvements", "Updates", "Plugin API", "Deprecation Notice"])
        #expect(entry.items.count == 14)
        // The intro paragraph leads, before the first heading.
        #expect(entry.items.first?.hasPrefix("IINA 1.5.0 introduces the biggest interface redesign") == true)
        if case .note(let first) = entry.content.first {
            #expect(first == entry.items.first)
        } else {
            Issue.record("the entry does not open with the intro note")
        }
    }

    @Test func entitiesAreDecoded() throws {
        let entry = try #require(
            ChangelogExtractor.extract(from: stableFixture, using: try recipe)?.entries.first)
        #expect(entry.items.contains("Split the \"Video/Audio\" settings page into two pages #5310."))
        #expect(entry.items.contains("You can now unshuffle the playlist if it hasn't changed since the last shuffle #6171."))
    }

    /// Mutation: item pattern ending at `</li>` only — the parent line swallows
    /// its sub-bullets and the two are one line.
    @Test func aSubBulletIsNotMergedIntoItsParent() throws {
        let items = try #require(
            ChangelogExtractor.extract(from: stableFixture, using: try recipe)?.entries.first).items
        let parent = try #require(items.firstIndex(of: "Added a new Settings window #6016."))
        #expect(items[parent + 1] == "Added a confirmation prompt when deleting keybinding config files #5972.")
    }

    /// The bold lead of the notice is its heading, and only its heading, and the
    /// heading comes before its note. Mutations: let the plain `<p>` branch take
    /// the notice too — the note then starts with "Deprecation Notice"; or start
    /// the bold-lead branch at the `<p>` — note and heading tie on position and
    /// the note lands above its heading.
    @Test func theDeprecationNoticeIsASectionNotARepeatedLine() throws {
        let entry = try #require(
            ChangelogExtractor.extract(from: stableFixture, using: try recipe)?.entries.first)
        #expect(!entry.items.contains { $0.contains("Deprecation Notice") })
        #expect(entry.items.last?.hasPrefix("IINA 1.5.0 now requires macOS 11 Big Sur or later for Intel Macs") == true)
        let tail = entry.content.suffix(2)
        #expect(tail.first == .heading("Deprecation Notice"))
        #expect(tail.last == entry.items.last.map(Changelog.Entry.Block.note))
    }

    /// Mutation: stop the version at the first non-digit — the entry reads `1.5.0`
    /// and no longer equals the feed's `shortVersionString`.
    @Test func theBetaPageKeepsItsSuffixedVersion() throws {
        let cl = try #require(ChangelogExtractor.extract(from: betaFixture, using: try recipe))
        #expect(cl.entries.count == 1)
        let entry = try #require(cl.entries.first)
        #expect(entry.version == "1.5.0-beta2")
        #expect(headings(entry) == ["New", "Bug Fixes", "Improvements", "Plugin API", "Deprecation Notice"])
        #expect(entry.items.count == 24)
        #expect(entry.items.first == "Added support for tone-mapping-param #6338.")
        #expect(entry.items.contains("Fixed \"Default\" and \"None\" in the sidebar not localized #6340."))
    }

    /// Links both appcasts publish, including a build-specific name and the beta
    /// pages. The rejected ones: two 1.3.0 items in both feeds link outside
    /// `/release-note/`, plus the shapes a loose pattern would let through.
    @Test func bothFeedsPagesAreAcceptedAndNothingElse() throws {
        let recipe = try recipe
        for page in ["1.5.0", "1.4.4", "1.4.2-build164", "0.0.14.1", "1.5.0-beta2", "1.5.0-beta1"] {
            let url = URL(string: "https://www.iina.io/release-note/\(page).html")
            #expect(recipe.acceptedFeedPage(url) == url, "\(page)")
        }
        for string in [
            "https://www.iina.io/IINA.v1.3.0.html",
            "http://www.iina.io/release-note/1.5.0.html",
            "https://www.iina.io/release-note/1.5.0.html?x=1",
            "https://www.iina.io/release-note/old/1.5.0.html",
            "https://iina.io.example/release-note/1.5.0.html",
            "https://github.com/iina/iina/releases/tag/v1.5.0",
        ] {
            #expect(recipe.acceptedFeedPage(URL(string: string)) == nil, "\(string)")
        }
    }
}
