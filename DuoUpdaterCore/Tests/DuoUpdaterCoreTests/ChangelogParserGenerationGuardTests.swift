import Testing
import Foundation
@testable import DuoUpdaterCore

/// The mechanical guard `Changelog.parserGeneration` needed but didn't have: a
/// hand-maintained comment "bump this when extraction changes" is exactly the
/// failure mode `VendorProbeRecipe.channelAnchorSurface`'s doc comment already
/// argues against — a guard that goes on passing while inspecting nothing is
/// worse than no guard, because it *looks* covered. `channelAnchorSurface` fixed
/// that for its own surface by deriving mechanically AND pinning a count that
/// forces a human decision on every new field
/// (`channelAnchorSurfaceCoversEveryRecipeField`). There is no equivalent
/// mechanical derivation for "did extraction's output change" — parsing isn't a
/// field list, it's a function from (recipe data, page bytes) to `Changelog` — so
/// this pins the ACTUAL parsed output of two fixtures already carried by other
/// test files, run through the exact registered recipe (not a hand-built one, so
/// a recipe-data edit — `entryPattern`, `skipSections`, `source`, … — moves this
/// test exactly the way a parser-code edit does). A change to `ChangelogExtractor`,
/// `StructuredChangelogDecoder`, `GitHubMarkdownParser`, or `ChangelogRecipeRegistry`
/// that alters what either fixture parses to fails HERE, and the fix is always the
/// same two-part edit: bump `Changelog.parserGeneration` (with a one-line log entry
/// on its doc comment) and update the expected value below to match.
///
/// Two fixtures, chosen to jointly cover every trigger this generation exists for:
/// - `betterDisplayReleasesFixture` (`BetterDisplayChangelogRecipeTests.swift`)
///   depends on BOTH `GitHubMarkdownParser.isImageOnly` (the HTML `<img>` download
///   button — the fix issue #112 itself was filed over) AND
///   `ChangelogRecipe.skipSections` (the contributor-roster drop) — the two
///   already-merged commits (`9963e3e`, `a6ac16b`) that would have needed a
///   generation bump had this field existed at the time.
/// - `figmaFixture` (`ChangelogExtractorTests.swift`) depends on the registered
///   recipe's `entryPattern`/`itemPatterns`/`source` for a regex-recipe (not
///   structured-decoder) path — covers the third already-merged commit
///   (`0d9d424`, the Atom-feed migration) via the same mechanism: this recipe's
///   `entryPattern` only matches Atom `<entry>` blocks, so reverting to the old
///   HTML-page pattern changes (empties) the parsed result.
///
/// Deliberately NOT a hash of the JSON encoding: `Changelog`/`Entry` are already
/// `Equatable`, so direct struct equality is strictly stronger than a digest (no
/// serialization-format sensitivity to worry about, e.g. key ordering or a future
/// `Codable` key rename that changes JSON bytes without changing meaning) and
/// gives a real diff in the failure message instead of two opaque hex strings.
/// Both fixtures are static string literals with no dates, UUIDs, or network
/// calls, so this cannot be flaky.
@Suite struct ChangelogParserGenerationGuardTests {

    /// Pinned alongside the two fixture checks below on purpose: bumping the
    /// generation without touching this file is still *possible* (nothing forces
    /// them to be edited in the same commit), but the two are next to each other
    /// so a reviewer scanning this file sees both move together, and a bump that
    /// changes NEITHER fixture's output (a bump "just in case") is caught here for
    /// the opposite reason — it's a signal the bump might be unnecessary, worth a
    /// second look rather than a silent no-op.
    @Test func pinnedGeneration() {
        #expect(Changelog.parserGeneration == 1)
    }

    /// Stable (v4.3.6, bulleted): exercises `skipSections` — the `### Included
    /// Localizations` roster is a whole section, not a bullet-shaped item, so this
    /// path never calls `isImageOnly` at all (the trailing download button here
    /// isn't a bullet either; the bullet passes never look at a non-bullet line in
    /// the first place). That is the OTHER fixture's job, right below.
    @Test func betterDisplayStableFixtureOutputIsPinned() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: BetterDisplayChannel.bundleID, channel: .stable))
        let format = try #require(recipe.structuredFormat)
        let changelog = try #require(StructuredChangelogDecoder.decode(
            betterDisplayReleasesFixture, format: format, channel: recipe.channel,
            maxEntries: recipe.maxEntries, skipSections: recipe.skipSections))

        let expected = Changelog(entries: [
            Changelog.Entry(
                version: "4.3.6",
                date: "2026-08-11",
                items: [
                    "Fixed DDC capability retrieval through the console potentially hanging indefinitely - #5674",
                    "Improved default nits values for built-in displays on Intel Macs - #5684",
                ]),
        ], itemSyntax: .markdown)
        #expect(changelog == expected)
    }

    /// Beta (v5.0.2, bullet-less pre-release): the one that actually exercises
    /// `isImageOnly` — no bullets anywhere in the body, so this goes through the
    /// prose pass, which is the ONLY pass that ever looks at the trailing
    /// `<a href=…><img …/></a>` download-button line. This is the fixture that
    /// fails if `isImageOnly` regresses.
    @Test func betterDisplayBetaFixtureOutputIsPinned() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: BetterDisplayChannel.bundleID, channel: .beta))
        let format = try #require(recipe.structuredFormat)
        let changelog = try #require(StructuredChangelogDecoder.decode(
            betterDisplayReleasesFixture, format: format, channel: recipe.channel,
            maxEntries: recipe.maxEntries, skipSections: recipe.skipSections))

        let expected = Changelog(entries: [
            Changelog.Entry(
                version: "5.0.2",
                date: "2026-08-11",
                items: [
                    "This updated BetterDisplay 5 pre-release adds improved soft-disconnected display handling, direct display connection controls in Settings, new display-group actions, and better touch compatibility on macOS 27 Golden Gate. Additionally, this version reintroduces Intel support for macOS 26 Tahoe. Other highlights in BetterDisplay 5 include advanced compositor filters, expanded display reporting and integration capabilities, HDMI-CEC control, improved per-display automation, app menu and OSD refinements, performance improvements, custom 3D LUT filters, a built-in app console, and compatibility updates for the latest macOS versions.",
                    "_Please note that this pre-release was tested with macOS 27 Golden Gate public beta 3 (developer beta 5) and may not be fully compatible with earlier or later macOS 27 versions - an [updated release](https://github.com/waydabber/BetterDisplay/releases) is available._",
                ]),
        ], itemSyntax: .markdown)
        #expect(changelog == expected)
    }

    @Test func figmaFixtureOutputIsPinned() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.figma.Desktop"))
        let changelog = try #require(ChangelogExtractor.extract(from: figmaFixture, using: recipe))

        let expected = Changelog(entries: [
            Changelog.Entry(
                version: "Recommend resources you want users to discover and use",
                date: "2026-08-17",
                items: [
                    "Admins can now choose which resources (skills, templates, libraries, and Make kits) are recommended to your organization or workspace.",
                ]),
            Changelog.Entry(
                version: "Get responsive text across screens with text wrap",
                date: "2026-08-14",
                items: [
                    "Text wrap makes your text responsive with two new options: Balance and Pretty. Set either on a text layer, a text style, or an individual paragraph in text settings.",
                ]),
            Changelog.Entry(
                version: "Try skills from the Community and make your own with the Figma agent",
                date: "2026-08-13",
                items: [
                    "We've added more ways to discover, create, and share skills for the Figma agent.",
                ]),
        ], itemSyntax: .plain)
        #expect(changelog == expected)
    }
}
