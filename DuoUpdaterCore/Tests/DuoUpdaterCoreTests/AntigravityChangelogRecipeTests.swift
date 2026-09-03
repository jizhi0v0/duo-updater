import Testing
import Foundation
@testable import DuoUpdaterCore

/// One page, two apps. `antigravity.google/changelog` lists the hub
/// (`com.google.antigravity`) and the IDE (`com.google.antigravity-ide`) in
/// separate panels of the same document, and the two recipes tell them apart by
/// the product token in each row's release link rather than by the panel
/// wrapper, which a flat regex cannot scope to. So the test that matters is that
/// neither recipe can see the other's releases.
///
/// Fixture: two hub rows and one IDE row from the live page (fetched
/// 2026-09-03), each disclosure list trimmed to its first item or two.
@Suite struct AntigravityChangelogRecipeTests {

    @Test func hubReadsOnlyTheHubPanel() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.google.antigravity"))
        let changelog = try #require(
            ChangelogExtractor.extract(from: antigravityChangelogFixture, using: recipe))

        #expect(changelog.entries.map(\.version) == ["2.12.0", "2.11.0"])
        let newest = try #require(changelog.entries.first)
        #expect(newest.date == "September 2, 2026")
        #expect(newest.title == "Quoting, /boost, and improved Settings")
        // Lead paragraph first, then the disclosure lists in document order.
        #expect(newest.items.count == 5)
        #expect(newest.items.first?.hasPrefix("Antigravity 2.12.0 includes") == true)
        // `<code>/boost</code>` — the tag goes, the text stays.
        #expect(newest.items.contains {
            $0 == "Introduced the /boost slash command to enhance thinking effort by using "
                + "a multi-agent reasoning pipeline."
        })
    }

    @Test func theIDEReadsOnlyTheIDEPanel() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.google.antigravity-ide"))
        let changelog = try #require(
            ChangelogExtractor.extract(from: antigravityChangelogFixture, using: recipe))

        // 2.5.5 is exactly what this app's `VendorProbeRecipe` detects — the
        // confirmation its comment said it could not get that the page covers the
        // IDE at all.
        #expect(changelog.entries.map(\.version) == ["2.5.5"])
        #expect(changelog.entries.first?.date == "August 13, 2026")
    }

    /// The two products' version lines are unrelated (2.12.0 against 2.5.5), so a
    /// leak in either direction is a wrong version on a row, not just extra notes.
    @Test func neitherRecipeSeesTheOtherProduct() throws {
        let hub = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.google.antigravity"))
        let ide = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.google.antigravity-ide"))
        let hubLog = try #require(
            ChangelogExtractor.extract(from: antigravityChangelogFixture, using: hub))
        let ideLog = try #require(
            ChangelogExtractor.extract(from: antigravityChangelogFixture, using: ide))

        #expect(!hubLog.entries.contains { $0.version == "2.5.5" })
        #expect(Set(ideLog.entries.map(\.version)).isDisjoint(with: ["2.12.0", "2.11.0"]))
    }

    /// The run from a row's date to its heading is the one part of the match that
    /// is not fenced by the row/panel markers, and an unfenced one is how a row
    /// without a heading pairs its version with the NEXT row's notes — or, for the
    /// last hub row, with the IDE panel's. Every row on the live page has a
    /// heading, so nothing here would ever have noticed; this removes one.
    @Test func aRowWithoutAHeadingIsDroppedRatherThanBorrowingTheNextRows() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.google.antigravity"))
        let headless = antigravityChangelogFixture.replacingOccurrences(
            of: #"<h3 class="heading-7 col-lg-4 astro-l7qxtvnw" data-h3-pin>"#
                + "Quoting, /boost, and improved Settings</h3>",
            with: "")
        #expect(headless != antigravityChangelogFixture, "the heading markup moved")

        let changelog = try #require(ChangelogExtractor.extract(from: headless, using: recipe))
        // 2.12.0 is gone, and 2.11.0 still has its OWN title and notes.
        #expect(changelog.entries.map(\.version) == ["2.11.0"])
        #expect(changelog.entries.first?.title == "Generative UI and UI improvements")
    }

}

private let antigravityChangelogFixture = #"""
<div class="grid-body active astro-l7qxtvnw" data-list-panel="hub"><div class="section-row-wrapper astro-l7qxtvnw" data-section-row><div class="version astro-l7qxtvnw" data-date-pin><p class="body astro-l7qxtvnw"><a class="version-link astro-l7qxtvnw" href="/releases?tab=hub&amp;version=2.12.0" title="View release 2.12.0">2.12.0</a><br class="astro-l7qxtvnw">September 2, 2026</p></div><div class="description main-left-container astro-l7qxtvnw" data-content-ref><h3 class="heading-7 col-lg-4 astro-l7qxtvnw" data-h3-pin>Quoting, /boost, and improved Settings</h3><div class="accordion body astro-l7qxtvnw"><div class="changes astro-l7qxtvnw"><p>Antigravity 2.12.0 includes several UX improvements across settings, the chat panel, and sidebar navigation. This release also includes a new slash command for paid users.</p></div><div class="expandable-items astro-l7qxtvnw"><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Improvements (7)</summary><ul class="astro-l7qxtvnw"><li class="caption astro-l7qxtvnw">You can now highlight portions of Antigravity responses to quote as context for follow-up prompts.</li><li class="caption astro-l7qxtvnw">Introduced the <code>/boost</code> slash command to enhance thinking effort by using a multi-agent reasoning pipeline.</li></ul></details><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Fixes (9)</summary><ul class="astro-l7qxtvnw"><li class="caption astro-l7qxtvnw">Added drag-and-drop and improved support for attaching audio files to conversations, and fixed an issue where WebM files were treated as audio.</li><li class="caption astro-l7qxtvnw">Fixed an issue that could cause authentication errors part way through a turn on slower network connections.</li></ul></details><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Patches (0)</summary><ul class="astro-l7qxtvnw"></ul></details></div></div></div></div><div class="section-row-wrapper astro-l7qxtvnw" data-section-row><div class="version astro-l7qxtvnw" data-date-pin><p class="body astro-l7qxtvnw"><a class="version-link astro-l7qxtvnw" href="/releases?tab=hub&amp;version=2.11.0" title="View release 2.11.0">2.11.0</a><br class="astro-l7qxtvnw">August 26, 2026</p></div><div class="description main-left-container astro-l7qxtvnw" data-content-ref><h3 class="heading-7 col-lg-4 astro-l7qxtvnw" data-h3-pin>Generative UI and UI improvements</h3><div class="accordion body astro-l7qxtvnw"><div class="changes astro-l7qxtvnw"><p>Antigravity 2.11.0 adds generative UI to render HTML artifacts inline in chat, alongside several UX improvements and bug fixes.</p></div><div class="expandable-items astro-l7qxtvnw"><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Improvements (10)</summary><ul class="astro-l7qxtvnw"><li class="caption astro-l7qxtvnw">Added support for referencing and inlining external files directly using <code>@path/to/file</code> syntax within <code>AGENTS.md</code> and custom rule files.</li></ul></details><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Fixes (30)</summary><ul class="astro-l7qxtvnw"><li class="caption astro-l7qxtvnw">Fixed an issue where slash commands unavailable to a selected custom agent were incorrectly shown in the command menu.</li></ul></details><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Patches (0)</summary><ul class="astro-l7qxtvnw"></ul></details></div></div></div></div></div><div class="grid-body astro-l7qxtvnw" data-list-panel="ide"><div class="section-row-wrapper astro-l7qxtvnw" data-section-row><div class="version astro-l7qxtvnw" data-date-pin><p class="body astro-l7qxtvnw"><a class="version-link astro-l7qxtvnw" href="/releases?tab=ide&amp;version=2.5.5" title="View release 2.5.5">2.5.5</a><br class="astro-l7qxtvnw">August 13, 2026</p></div><div class="description main-left-container astro-l7qxtvnw" data-content-ref><h3 class="heading-7 col-lg-4 astro-l7qxtvnw" data-h3-pin>Windows Media Attachments and Chat Responsiveness Improvements</h3><div class="accordion body astro-l7qxtvnw"><div class="changes astro-l7qxtvnw"><p>Bug fixes addressing media attachment failures on Windows and improving message responsiveness when interacting with the agent.</p></div><div class="expandable-items astro-l7qxtvnw"><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Improvements (0)</summary><ul class="astro-l7qxtvnw"></ul></details><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Fixes (2)</summary><ul class="astro-l7qxtvnw"><li class="caption astro-l7qxtvnw">Fixed an issue where the agent failed when attaching images or media files on Windows machines.</li></ul></details><details data-details class="astro-l7qxtvnw"><summary class="astro-l7qxtvnw">Patches (0)</summary><ul class="astro-l7qxtvnw"></ul></details></div></div></div></div></div></section>
"""#
