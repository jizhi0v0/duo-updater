import Foundation
import Testing
@testable import DuoUpdaterCore

// Firefox's five changelog recipes (Release / Beta / ESR on `org.mozilla.firefox`,
// Developer Edition, Nightly). Fixtures are trimmed slices of the real
// www.firefox.com per-version pages fetched 2026-10-10: the release summary
// <h2>, the date, and `release-note` items, including the page's own
// `id="note-mdn"` "Developer Information" link, which is not a change.

private let firefoxBetaFixture = """
<div class="mzp-l-content mzp-has-sidebar mzp-l-sidebar-left fl-c-release-notes-summary fl-l-release-notes-wrapper fl-l-release-notes-with-sidebar">
<h2 class="c-release-summary fl-c-release-summary-sidebar fl-l-release-notes-sidebar">
  <span class="c-release-version fl-c-release-version fl-heading fl-heading-lg">158.0beta</span>
  <span class="c-release-product fl-c-release-product fl-heading fl-heading-xs fl-u-font-semibold">Firefox Beta</span>
</h2>

  <p class="c-release-date fl-c-release-date fl-l-release-notes-sidebar">September 28, 2026</p>

<div class="mzp-l-main mzp-l-article fl-c-release-summary-details fl-c-release-notes-main">
  <div class="c-release-first-title fl-heading fl-heading-xs fl-u-font-semibold">Version 158.0beta, first offered to Beta channel users on September 28, 2026</div>
</div></div>
<section class="c-release-notes fl-c-release-notes-content fl-l-release-notes-wrapper">
<ul>
  <li class="release-note" id="note-792289">
    <div class="release-note-content">
      <p>Firefox now supports the new <a href="https://jpeg.org/jpegxl/">JPEG XL image format </a>which generally has better compression than WebP, JPEG, PNG and GIF and is designed to supersede them. </p>


    </div>

  </li>
  <li class="release-note" id="note-792290">
    <div class="release-note-content">
      <p>The tab bar can now be shown at either the top or bottom of the screen on <a href="https://play.google.com/store/apps/details?id=org.mozilla.firefox_beta">Firefox for Android</a>. Check <code>Settings</code> -&gt; <code>Customize</code> to configure.</p>


    </div>

  </li>
</ul>
<ul>
  <li class="release-note" id="note-mdn">
    <div class="release-note-content">
      <a class="mdn-icon" rel="external" href="https://developer.mozilla.org/docs/Mozilla/Firefox/Releases/158">Developer Information</a>


    </div>

  </li>
</ul>
</section>
"""

private let firefoxESRFixture = """
<h2 class="c-release-summary fl-c-release-summary-sidebar fl-l-release-notes-sidebar">
  <span class="c-release-version fl-c-release-version fl-heading fl-heading-lg">140.17.0</span>
  <span class="c-release-product fl-c-release-product fl-heading fl-heading-xs fl-u-font-semibold">Firefox ESR</span>
</h2>

  <p class="c-release-date fl-c-release-date fl-l-release-notes-sidebar">September 29, 2026</p>
<ul>
  <li class="release-note" id="note-792255">
    <div class="release-note-content">
      <p>Various <a href="https://www.mozilla.org/security/advisories/mfsa2026-99/">security fixes</a>.</p>


    </div>

  </li>
</ul>
<ul>
  <li class="release-note" id="note-mdn">
    <div class="release-note-content">
      <a class="mdn-icon" rel="external" href="https://developer.mozilla.org/docs/Mozilla/Firefox/Releases/140">Developer Information</a>
    </div>
  </li>
</ul>
"""

private let firefoxReleaseFixture = """
<h2 class="c-release-summary fl-c-release-summary-sidebar fl-l-release-notes-sidebar">
  <span class="c-release-version fl-c-release-version fl-heading fl-heading-lg">157.0.1</span>
  <span class="c-release-product fl-c-release-product fl-heading fl-heading-xs fl-u-font-semibold">Firefox Release</span>
</h2>

  <p class="c-release-date fl-c-release-date fl-l-release-notes-sidebar">October 6, 2026</p>
<ul>
  <li class="release-note" id="note-792283">
    <div class="release-note-content">
      <p>Fixed downloads failing on macOS when Firefox is set to ask where to save files but doesn't have permission to access the Downloads folder. (<a href="https://bugzilla.mozilla.org/show_bug.cgi?id=2077390">Bug 2077390</a>)</p>


    </div>

  </li>
  <li class="release-note" id="note-792285">
    <div class="release-note-content">
      <p>Fixed the <em>Restore from Backup</em> option not appearing during onboarding on Windows. (<a href="https://bugzilla.mozilla.org/show_bug.cgi?id=2073401">Bug 2073401</a>)</p>


    </div>

  </li>
</ul>
"""

@Test func extractsFirefoxReleaseEntry() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.firefox", channel: .stable))
    #expect(recipe.channel == .stable)
    let cl = try #require(ChangelogExtractor.extract(from: firefoxReleaseFixture, using: recipe))
    #expect(cl.entries.count == 1)
    #expect(cl.entries[0].version == "157.0.1")
    #expect(cl.entries[0].date == "October 6, 2026")
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[1]
        == "Fixed the Restore from Backup option not appearing during onboarding on Windows. (Bug 2073401)")
}

@Test func extractsFirefoxBetaCycleAndSkipsTheDeveloperLink() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.firefox", channel: .beta))
    #expect(recipe.channel == .beta)
    let cl = try #require(ChangelogExtractor.extract(from: firefoxBetaFixture, using: recipe))
    #expect(cl.entries.count == 1)
    #expect(cl.entries[0].version == "158.0beta")
    #expect(cl.entries[0].date == "September 28, 2026")
    // Two changes; the `note-mdn` "Developer Information" link is not one.
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[1]
        == "The tab bar can now be shown at either the top or bottom of the screen on Firefox for Android. Check Settings -> Customize to configure.")
    #expect(!cl.entries[0].items.contains("Developer Information"))
}

@Test func extractsFirefoxESREntry() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.firefox", channel: .esr))
    #expect(recipe.channel == .esr)
    let cl = try #require(ChangelogExtractor.extract(from: firefoxESRFixture, using: recipe))
    #expect(cl.entries.count == 1)
    #expect(cl.entries[0].version == "140.17.0")
    #expect(cl.entries[0].date == "September 29, 2026")
    #expect(cl.entries[0].items == ["Various security fixes."])
}

/// Developer Edition and Nightly parse the same page template; what differs is
/// only which page their version resolves to (below).
@Test func firefoxDevEditionAndNightlyShareThePageShape() throws {
    let dev = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.firefoxdeveloperedition", channel: .dev))
    let devLog = try #require(ChangelogExtractor.extract(from: firefoxBetaFixture, using: dev))
    #expect(devLog.entries.first?.version == "158.0beta")
    #expect(devLog.entries.first?.items.count == 2)
    let nightly = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.nightly", channel: .nightly))
    #expect(ChangelogExtractor.extract(from: firefoxReleaseFixture, using: nightly)?
        .entries.first?.version == "157.0.1")
}

/// Every page each channel is offered or installed with, as firefox.com names it
/// (each URL checked for a 200 on 2026-10-10, and the alternative forms for a 404).
@Test func firefoxResolvedSourcePerChannel() throws {
    func url(_ id: String, _ channel: ReleaseChannel, _ version: String) throws -> String {
        try #require(ChangelogRecipeRegistry.recipe(forBundleID: id, channel: channel))
            .resolvedSource(forVersion: version).absoluteString
    }
    let base = "https://www.firefox.com/en-US/firefox/"
    #expect(try url("org.mozilla.firefox", .stable, "157.0.1") == base + "157.0.1/releasenotes/")
    // Beta: offered `158.0b5` and installed `158.0` both land on the cycle page.
    #expect(try url("org.mozilla.firefox", .beta, "158.0b5") == base + "158.0beta/releasenotes/")
    #expect(try url("org.mozilla.firefox", .beta, "158.0") == base + "158.0beta/releasenotes/")
    // ESR: bare once the minor is past 0, whether offered (`esr`) or installed.
    #expect(try url("org.mozilla.firefox", .esr, "140.17.0esr") == base + "140.17.0/releasenotes/")
    #expect(try url("org.mozilla.firefox", .esr, "140.17.0") == base + "140.17.0/releasenotes/")
    // …but `X.0` and `X.0.Y` ESRs share their number with a Release and keep it.
    #expect(try url("org.mozilla.firefox", .esr, "153.0esr") == base + "153.0esr/releasenotes/")
    #expect(try url("org.mozilla.firefox", .esr, "115.0.2") == base + "115.0.2esr/releasenotes/")
    // Developer Edition reads the Beta cycle page.
    #expect(try url("org.mozilla.firefoxdeveloperedition", .dev, "158.0b5")
        == base + "158.0beta/releasenotes/")
    #expect(try url("org.mozilla.firefoxdeveloperedition", .dev, "158.0")
        == base + "158.0beta/releasenotes/")
    #expect(try url("org.mozilla.nightly", .nightly, "160.0a1") == base + "160.0a1/releasenotes/")
}

/// `{firefoxVersion}` is the only difference between the two Mozilla sites'
/// ESR URLs. `{version}` keeps Thunderbird's always-`esr` form for the same input.
@Test func firefoxVersionPlaceholderLeavesThunderbirdESRUnchanged() throws {
    let thunderbird = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbird", channel: .esr))
    #expect(thunderbird.resolvedSource(forVersion: "140.11.1").absoluteString
        == "https://www.thunderbird.net/en-US/thunderbird/140.11.1esr/releasenotes/")
    let firefox = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.firefox", channel: .esr))
    #expect(firefox.resolvedSource(forVersion: "140.11.1").absoluteString
        == "https://www.firefox.com/en-US/firefox/140.11.1/releasenotes/")

    #expect(ChangelogRecipe.firefoxVersionToken(for: "140.17.0esr") == "140.17.0")
    #expect(ChangelogRecipe.firefoxVersionToken(for: "140.0esr") == "140.0esr")
    #expect(ChangelogRecipe.firefoxVersionToken(for: "115.0.2esr") == "115.0.2esr")
    // Non-ESR tokens pass through.
    #expect(ChangelogRecipe.firefoxVersionToken(for: "158.0beta") == "158.0beta")
    #expect(ChangelogRecipe.firefoxVersionToken(for: "160.0a1") == "160.0a1")
    #expect(ChangelogRecipe.firefoxVersionToken(for: "157.0.1") == "157.0.1")
}
