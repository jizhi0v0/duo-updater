import Testing
@testable import DuoUpdaterCore

struct MagicQuitChangelogRecipeTests {
    @Test func rendersTaggedVersionHistoryAndNativeHeadings() throws {
        // Excerpts from the vendor's v2.0 tag.
        let markdown = """
        ## Version 2.0 - 2026-07-20

        ### New
        - Time spent asleep or with the screen locked no longer counts as idle time.

        ### Improvements
        - Requires macOS 14 or later.

        ## Version 1.4 - 2023-12-21

        ### Improvements
        - Apps that should not have been terminated where terminated (e.g. apps that run in the background like Cleanshot X, Bartender or Paste)
        """
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.MagicQuit", channel: .stable))
        #expect(recipe.source.absoluteString
            == "https://raw.githubusercontent.com/BigBerny/magicquit/v2.0/CHANGELOG.md")
        #expect(recipe.resolvedSource(forVersion: "2.11.3").absoluteString
            == "https://raw.githubusercontent.com/BigBerny/magicquit/v2.11.3/CHANGELOG.md")

        let history = try #require(ChangelogExtractor.extract(from: markdown, using: recipe))
        #expect(history.entries.map(\.version) == ["2.0", "1.4"])
        #expect(history.entries.map(\.date) == ["2026-07-20", "2023-12-21"])
        let release = try #require(history.entries.first)
        #expect(release.content == [
            .heading("New"),
            .note("Time spent asleep or with the screen locked no longer counts as idle time."),
            .heading("Improvements"),
            .note("Requires macOS 14 or later."),
        ])
        #expect(history.entries.last?.items.count == 1)
    }
}
