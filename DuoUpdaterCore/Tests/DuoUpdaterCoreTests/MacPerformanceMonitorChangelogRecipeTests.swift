import Testing
import Foundation
@testable import DuoUpdaterCore

/// Mac Performance Monitor's release notes (#374, reported by a user).
///
/// Its appcast carries none: one item, and no `sparkle:releaseNotesLink`, no
/// `sparkle:fullReleaseNotesLink`, no `<description>` (fetched 2026-09-06 from
/// the `appcast.xml` asset its `SUFeedURL` resolves to). The GitHub release body
/// is a single sentence pointing elsewhere — "Mac Performance Monitor 1.7.1
/// (build 206). See CHANGELOG.md for what's new." — so the repo's Keep a
/// Changelog file is the only place the notes exist.
///
/// The fixture is the real file's opening, verbatim through the head of the
/// second release: the `# Changelog` preamble, the `[Unreleased]` section, and
/// two entries whose bullets wrap across lines the way this vendor writes them.
struct MacPerformanceMonitorChangelogRecipeTests {
    private static let bundleID = "uk.co.bzwrd.macperfmonitor"

    private static let fixture = """
    # Changelog

    Notable changes to Mac Performance Monitor. This project follows
    [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
    [Semantic Versioning](https://semver.org/).

    ## [Unreleased]

    ### Security

    - Sparkle, the updater framework, moved from 2.9.3 to 2.9.6. That picks up two
      high-severity advisories published on 17 August 2026.

    ## [1.7.1] - 2026-09-03

    ### Fixed

    - In Simplified Chinese, the Hardware tab listed every CPU instruction-set
      feature as unsupported. The check compared the translated value against the
      English word "Supported", so nothing ever matched.
    - Two labels, the core count in the system header and the "N supported" count
      in Hardware, stayed English in Chinese.

    ### Changed

    - Localization moved to an Apple String Catalog: one file holding every
      language, compiled into the app at build time.

    ## [1.7.0] - 2026-09-01

    ### Added

    - Simplified Chinese localization, and a language picker in Settings (Follow
      System, English, or 简体中文).
    """

    private static var recipe: ChangelogRecipe {
        get throws {
            try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == bundleID })
        }
    }

    /// Read off the registry rather than restated, so deleting the recipe fails
    /// here instead of quietly removing the app's notes.
    @Test func theRecipeReadsTheRepositorysChangelogFile() throws {
        let recipe = try Self.recipe
        #expect(recipe.source.host == "raw.githubusercontent.com")
        #expect(recipe.source.path == "/Zesty0wl/mac-performance-monitor/main/CHANGELOG.md")
        #expect(recipe.markdownSource)
        #expect(recipe.channel == nil, "one train; a channel here would scope it to a rail that does not exist")
    }

    /// ⚠️ `## [Unreleased]` is a real section with real bullets sitting above the
    /// newest release, and it describes a build nobody can install. Requiring a
    /// digit inside the brackets is what excludes it — and the check that catches
    /// a pattern which stops doing so is that the FIRST entry is the shipped
    /// version, not merely that some entry is.
    @Test func theUnreleasedSectionIsNotAnEntry() throws {
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: Self.fixture))
        #expect(parsed.entries.first?.version == "1.7.1")
        #expect(!parsed.entries.contains { $0.version.lowercased().contains("unreleased") })
        #expect(parsed.entries.map(\.version) == ["1.7.1", "1.7.0"])
        #expect(parsed.entries.first?.date == "2026-09-03")
    }

    /// This vendor wraps its bullets at ~78 columns with a two-space continuation
    /// indent, so the single-line item pattern every other recipe uses would cut
    /// most items mid-sentence — "…every CPU instruction-set" and nothing more.
    /// The whole bullet has to come back.
    @Test func aWrappedBulletComesBackWhole() throws {
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: Self.fixture))
        let first = try #require(parsed.entries.first?.items.first)
        #expect(first.contains("instruction-set feature as unsupported"),
                "the item was truncated at the line break: \(first)")
        #expect(first.hasSuffix("so nothing ever matched."))
    }

    /// ⚠️ Keep a Changelog ends a file with a link-reference block, and the LAST
    /// entry's body runs to the end of the document — so without a boundary its
    /// final bullet swallows every one of those lines. Measured on the live file
    /// before the fix: the oldest entry's last item was 1709 characters of prose
    /// followed by 17 GitHub compare URLs; after it, 137.
    ///
    /// The fixture above could not catch this. It is the file's OPENING, and the
    /// block exists only at its tail — the same fixture-distribution trap
    /// CLAUDE.md describes, met again. Hence a second fixture that ends the way
    /// the real file ends.
    ///
    /// Mutation: drop `\n\[` from the item pattern's lookahead → the last item
    /// carries the link definitions again.
    @Test func theTrailingLinkBlockIsNotSwallowedByTheLastBullet() throws {
        let tail = """
        # Changelog

        ## [1.1.5] - 2026-07-05

        ### Added

        - A first bullet that wraps the way this vendor writes them, with a
          two-space continuation indent.
        - A clean split between a headless, unit-tested data layer and the
          SwiftUI app.

        [1.1.5]: https://github.com/Zesty0wl/mac-performance-monitor/releases/tag/v1.1.5.118
        [1.2.0]: https://github.com/Zesty0wl/mac-performance-monitor/compare/v1.1.5.118...v1.2.0.127
        """
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: tail))
        let last = try #require(parsed.entries.last)
        #expect(last.version == "1.1.5")
        #expect(last.items.count == 2)
        let final = try #require(last.items.last)
        #expect(final.hasSuffix("SwiftUI app."), "the item ran past its bullet: \(final)")
        for item in last.items {
            #expect(!item.contains("]: https://"), "a link definition leaked into an item: \(item)")
        }
    }

    /// The `### Fixed` / `### Changed` group headings are not items, and an item
    /// must not swallow the heading that follows it. Both entries' items are
    /// counted, because a pattern that ran past a heading would also merge the
    /// groups' bullets into one.
    @Test func groupHeadingsAreNotItemsAndDoNotLeakIntoThem() throws {
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: Self.fixture))
        #expect(parsed.entries.first?.items.count == 3)
        #expect(parsed.entries.last?.items.count == 1)
        for entry in parsed.entries {
            for item in entry.items {
                #expect(!item.contains("###"), "a group heading leaked into an item: \(item)")
                #expect(!item.hasPrefix("Fixed") && !item.hasPrefix("Changed") && !item.hasPrefix("Added"))
            }
        }
    }
}
