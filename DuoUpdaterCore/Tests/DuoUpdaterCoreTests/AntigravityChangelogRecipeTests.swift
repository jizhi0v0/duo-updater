import Testing
import Foundation
@testable import DuoUpdaterCore

/// One page, two apps. `antigravity.google/docs/changelog` lists the hub
/// (`com.google.antigravity`) and the IDE (`com.google.antigravity-ide`) in
/// separate panels of the same document, and the two recipes tell them apart by
/// the product token in each row's own id (`rel-hub-…` / `rel-ide-…`) rather
/// than by the panel wrapper, which a flat regex cannot scope to. So the test
/// that matters is that neither recipe can see the other's releases.
///
/// Fixture: two hub rows and one IDE row from the live page (fetched
/// 2026-10-03), each disclosure list trimmed to its first two items and the
/// chevron SVGs dropped.
@Suite struct AntigravityChangelogRecipeTests {

    @Test func hubReadsOnlyTheHubPanel() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.google.antigravity"))
        let changelog = try #require(
            ChangelogExtractor.extract(from: antigravityChangelogFixture, using: recipe))

        // The bare version from the row id, not the `v`-prefixed link text.
        #expect(changelog.entries.map(\.version) == ["2.19.1", "2.18.1"])
        let newest = try #require(changelog.entries.first)
        #expect(newest.date == "September 30, 2026")
        #expect(newest.title
            == "Message subagents directly, export Markdown as PDF, and conversation-only undo")
        // Lead paragraph first, then both disclosure lists in document order; the
        // "Improvements" / "Fixes" labels are not items.
        #expect(newest.items.count == 5)
        #expect(newest.items.first?.hasPrefix("You can now send messages straight to a subagent") == true)
        #expect(newest.items.last
            == "Fixed an issue where custom agents ignored your global and project rules.")
        #expect(!newest.items.contains { $0.hasPrefix("Improvements") || $0.hasPrefix("Fixes") })
    }

    @Test func theIDEReadsOnlyTheIDEPanel() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.google.antigravity-ide"))
        let changelog = try #require(
            ChangelogExtractor.extract(from: antigravityChangelogFixture, using: recipe))

        // 2.5.5 is exactly what this app's `VendorProbeRecipe` detected when the
        // fixture was fetched — confirmation that the page's `ide` panel covers the
        // IDE, not only the hub.
        #expect(changelog.entries.map(\.version) == ["2.5.5"])
        #expect(changelog.entries.first?.date == "August 13, 2026")
        #expect(changelog.entries.first?.items.count == 3)
    }

    /// The two products' version lines are unrelated (2.19.1 against 2.5.5), so a
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
        #expect(Set(ideLog.entries.map(\.version)).isDisjoint(with: ["2.19.1", "2.18.1"]))
    }

    /// The runs from a row's id to its date and headline are fenced by the row's
    /// own `</article>`, and an unfenced one is how a row without a headline pairs
    /// its version with the NEXT row's notes — or, for the last hub row, with the
    /// IDE panel's. Every row on the live page has a headline, so nothing there
    /// would ever have noticed; this removes one.
    @Test func aRowWithoutAHeadingIsDroppedRatherThanBorrowingTheNextRows() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.google.antigravity"))
        let headless = antigravityChangelogFixture.replacingOccurrences(
            of: #"<h3 class="rn-headline astro-oabwef3t">"#
                + "Message subagents directly, export Markdown as PDF, and conversation-only undo</h3>",
            with: "")
        #expect(headless != antigravityChangelogFixture, "the heading markup moved")

        let changelog = try #require(ChangelogExtractor.extract(from: headless, using: recipe))
        // 2.19.1 is gone, and 2.18.1 still has its OWN title and notes.
        #expect(changelog.entries.map(\.version) == ["2.18.1"])
        #expect(changelog.entries.first?.title == "Manage & Install plugins in AGY")
    }

    /// The old `/changelog` URL, as it answers now: a meta-refresh stub that
    /// URLSession does not follow. Neither recipe can read anything out of it, so
    /// both must name the page it points at.
    @Test func bothRecipesReadTheDocsPageNotTheRedirectStub() throws {
        let stub = #"<!doctype html><title>Redirecting to: /docs/changelog</title>"#
            + #"<meta http-equiv="refresh" content="0;url=/docs/changelog">"#
        for id in ["com.google.antigravity", "com.google.antigravity-ide"] {
            let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: id))
            #expect(recipe.source.absoluteString == "https://antigravity.google/docs/changelog")
            #expect(ChangelogExtractor.extract(from: stub, using: recipe)?.entries.isEmpty ?? true)
        }
    }

}

private let antigravityChangelogFixture = #"""
<div class="rn-panel active astro-oabwef3t" id="panel-hub" role="tabpanel" aria-labelledby="tab-hub" data-panel-id="hub" style="display: block;"><h2 class="rn-panel-heading astro-oabwef3t">Antigravity 2.0</h2><div class="rn-timeline astro-oabwef3t"><article class="rn-row astro-oabwef3t" id="rel-hub-2.19.1"><div class="rn-version-col astro-oabwef3t"><div class="rn-version-row astro-oabwef3t"><h3 class="rn-version-heading astro-oabwef3t"><a href="/releases?tab=hub&amp;version=2.19.1" class="rn-version-tag astro-oabwef3t" title="View release 2.19.1">v2.19.1</a></h3><span class="rn-latest-tag astro-oabwef3t">Latest</span></div><time class="rn-date-text astro-oabwef3t">September 30, 2026</time></div><div class="rn-card astro-oabwef3t"><h3 class="rn-headline astro-oabwef3t">Message subagents directly, export Markdown as PDF, and conversation-only undo</h3><div class="rn-summary astro-oabwef3t"><p>You can now send messages straight to a subagent from the message box, export rendered Markdown as a PDF, and revert only the conversation when you undo. You can also reopen the window from the tray icon on Windows and Linux. This release includes 5 improvements and 5 fixes.</p></div><div class="rn-categories astro-oabwef3t"><details class="rn-accordion astro-oabwef3t" data-release-detail data-product="hub" data-version="2.19.1" data-item-title="Improvements"><summary class="rn-accordion-summary astro-oabwef3t"><span class="rn-cat-title astro-oabwef3t">Improvements<span class="rn-count astro-oabwef3t">(5)</span></span></summary><ul class="rn-list astro-oabwef3t"><li class="rn-item astro-oabwef3t">You can now send a message directly to a subagent from the message box, without going through the main agent.</li><li class="rn-item astro-oabwef3t">Rendered Markdown in artifacts and in files opened in the side pane can now be exported as a PDF from the overflow menu, including tables, code blocks, and diagrams.</li></ul></details><details class="rn-accordion astro-oabwef3t" data-release-detail data-product="hub" data-version="2.19.1" data-item-title="Fixes"><summary class="rn-accordion-summary astro-oabwef3t"><span class="rn-cat-title astro-oabwef3t">Fixes<span class="rn-count astro-oabwef3t">(5)</span></span></summary><ul class="rn-list astro-oabwef3t"><li class="rn-item astro-oabwef3t">Fixed an issue where a terminal command step you had expanded collapsed again when the command finished.</li><li class="rn-item astro-oabwef3t">Fixed an issue where custom agents ignored your global and project rules.</li></ul></details></div></div></article><article class="rn-row astro-oabwef3t" id="rel-hub-2.18.1"><div class="rn-version-col astro-oabwef3t"><div class="rn-version-row astro-oabwef3t"><h3 class="rn-version-heading astro-oabwef3t"><a href="/releases?tab=hub&amp;version=2.18.1" class="rn-version-tag astro-oabwef3t" title="View release 2.18.1">v2.18.1</a></h3></div><time class="rn-date-text astro-oabwef3t">September 28, 2026</time></div><div class="rn-card astro-oabwef3t"><h3 class="rn-headline astro-oabwef3t">Manage & Install plugins in AGY</h3><div class="rn-summary astro-oabwef3t"><p>This release introduces a Customizations tab and marketplace for discovering and installing plugins and includes overall improvements to the sidebar and chat experience.</p></div><div class="rn-categories astro-oabwef3t"><details class="rn-accordion astro-oabwef3t" data-release-detail data-product="hub" data-version="2.18.1" data-item-title="Improvements"><summary class="rn-accordion-summary astro-oabwef3t"><span class="rn-cat-title astro-oabwef3t">Improvements<span class="rn-count astro-oabwef3t">(14)</span></span></summary><ul class="rn-list astro-oabwef3t"><li class="rn-item astro-oabwef3t">You can now discover, install and manage plugins within the Customizations tab, with curated shelves for development tools and workspace integrations.</li><li class="rn-item astro-oabwef3t">You can now switch the sidebar to show only archived conversations from the Display Options menu and filter by archived conversations on the Conversation History page, with archive folder icons marking archived projects.</li></ul></details><details class="rn-accordion astro-oabwef3t" data-release-detail data-product="hub" data-version="2.18.1" data-item-title="Fixes"><summary class="rn-accordion-summary astro-oabwef3t"><span class="rn-cat-title astro-oabwef3t">Fixes<span class="rn-count astro-oabwef3t">(15)</span></span></summary><ul class="rn-list astro-oabwef3t"><li class="rn-item astro-oabwef3t">Fixed an issue where Google Sign-In could fail with a browser security error when signing in from the app or the built-in browser.</li><li class="rn-item astro-oabwef3t">Fixed an issue where scrolling up in long conversations could stall after collapsed tool steps, unloading earlier turns could jump the scroll position, and page bounds could collapse to zero.</li></ul></details></div></div></article></div></div><div class="rn-panel astro-oabwef3t" id="panel-ide" role="tabpanel" aria-labelledby="tab-ide" data-panel-id="ide" style="display: none;"><h2 class="rn-panel-heading astro-oabwef3t">Antigravity IDE</h2><div class="rn-timeline astro-oabwef3t"><article class="rn-row astro-oabwef3t" id="rel-ide-2.5.5"><div class="rn-version-col astro-oabwef3t"><div class="rn-version-row astro-oabwef3t"><h3 class="rn-version-heading astro-oabwef3t"><a href="/releases?tab=ide&amp;version=2.5.5" class="rn-version-tag astro-oabwef3t" title="View release 2.5.5">v2.5.5</a></h3><span class="rn-latest-tag astro-oabwef3t">Latest</span></div><time class="rn-date-text astro-oabwef3t">August 13, 2026</time></div><div class="rn-card astro-oabwef3t"><h3 class="rn-headline astro-oabwef3t">Windows Media Attachments and Chat Responsiveness Improvements</h3><div class="rn-summary astro-oabwef3t"><p>Bug fixes addressing media attachment failures on Windows and improving message responsiveness when interacting with the agent.</p></div><div class="rn-categories astro-oabwef3t"><details class="rn-accordion astro-oabwef3t" data-release-detail data-product="ide" data-version="2.5.5" data-item-title="Fixes"><summary class="rn-accordion-summary astro-oabwef3t"><span class="rn-cat-title astro-oabwef3t">Fixes<span class="rn-count astro-oabwef3t">(2)</span></span></summary><ul class="rn-list astro-oabwef3t"><li class="rn-item astro-oabwef3t">Fixed an issue where the agent failed when attaching images or media files on Windows machines.</li><li class="rn-item astro-oabwef3t">Improved responsiveness and reduced hanging issues when sending messages to the agent.</li></ul></details></div></div></article></div></div>
"""#
