import Testing
import Foundation
@testable import DuoUpdaterCore

/// Shift's release notes, read from the repo's Release Please `CHANGELOG.md`.
///
/// The fixture is the real file's shape, trimmed: its `# Changelog` title, the
/// first release with a few bullets from each of its three groups, and the file's
/// own `## Changelog` preamble that Release Please leaves at the END. Bullets are
/// verbatim, including the trailing commit-hash link every one of them carries.
struct ShiftChangelogRecipeTests {
    private static let bundleID = "app.shift"

    private static let fixture = """
    # Changelog

    ## [0.1.1](https://github.com/shift-editor/shift/compare/v0.1.0...v0.1.1) (2026-10-01)


    ### Features

    * adapt the launcher lockup and accent text to colour themes ([#474](https://github.com/shift-editor/shift/issues/474)) ([08be9ac](https://github.com/shift-editor/shift/commit/08be9aca65f004373f97e514e252c2400376d19e))
    * add desktop application updates ([92d54f1](https://github.com/shift-editor/shift/commit/92d54f17d0e41ad3080dbfd560a2151f4faec3c6))
    * **desktop:** add Nightly branding ([#293](https://github.com/shift-editor/shift/issues/293)) ([450f0f3](https://github.com/shift-editor/shift/commit/450f0f3fd67734e37da8e1b84a3494f6be7cb7c9))


    ### Bug Fixes

    * bundle Inter with packaged renderer ([fb7b37d](https://github.com/shift-editor/shift/commit/fb7b37d5f7156ed52cb7ff8ee81905a3fb78dd90))
    * **catalog:** render glyphs without WebGPU ([#329](https://github.com/shift-editor/shift/issues/329)) ([76ae659](https://github.com/shift-editor/shift/commit/76ae659bdb848e86f858199259e4ee6d6bb1a05b))


    ### Performance

    * **editor:** speed up large-outline editing ([#371](https://github.com/shift-editor/shift/issues/371)) ([4da6340](https://github.com/shift-editor/shift/commit/4da6340383463fca56f4b4dc451920949b1b0357))

    ## Changelog

    All notable changes to Shift will be documented in this file.

    This changelog is maintained by [Release Please](https://github.com/googleapis/release-please).
    """

    private static var recipe: ChangelogRecipe {
        get throws {
            try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == bundleID })
        }
    }

    @Test func theRecipeReadsTheRepositorysChangelogFile() throws {
        let recipe = try Self.recipe
        #expect(recipe.source.host == "raw.githubusercontent.com")
        #expect(recipe.source.path == "/shift-editor/shift/main/CHANGELOG.md")
        #expect(recipe.markdownSource)
        #expect(recipe.structuredFormat == nil,
                "every versioned release is a GitHub prerelease; .gitHubReleases would read none for a stable install")
    }

    /// Nightly is its own bundle id with `0.<run>.<attempt>` versions and no
    /// per-build notes. The Release recipe must not leak onto it.
    @Test func nightlyGetsNoRecipe() {
        #expect(ChangelogRecipeRegistry.recipe(forBundleID: "app.shift.nightly") == nil)
    }

    /// ⚠️ The file ends with a `## Changelog` preamble. A version pattern that
    /// accepted any heading would add it as an entry; one whose body ran past the
    /// next `##` would fold its prose into the Performance group.
    @Test func oneEntryAndThePreambleIsNotPartOfIt() throws {
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: Self.fixture))
        #expect(parsed.entries.map(\.version) == ["0.1.1"])
        #expect(parsed.entries.first?.date == "2026-10-01")
        let items = try #require(parsed.entries.first?.items)
        #expect(items.count == 6)
        #expect(!items.contains { $0.contains("Release Please") || $0.contains("###") })
    }

    /// The commit-hash link is dropped, the issue link is kept.
    /// Mutation: remove the optional commit group from the item pattern → every
    /// item ends in `(08be9ac)`-style noise again.
    @Test func theCommitHashTailIsDroppedAndTheIssueLinkKept() throws {
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: Self.fixture))
        let items = try #require(parsed.entries.first?.items)
        #expect(!items.contains { $0.contains("/commit/") || $0.contains("08be9ac") })
        #expect(items.first?.contains("474") == true)
        #expect(items.contains { $0.hasPrefix("add desktop application updates") })
    }

    @Test func theThreeGroupsSurviveAsHeadings() throws {
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: Self.fixture))
        let entry = try #require(parsed.entries.first)
        let headings = entry.content.compactMap { block -> String? in
            if case .heading(let h) = block { return h } else { return nil }
        }
        #expect(headings == ["Features", "Bug Fixes", "Performance"])
    }
}
