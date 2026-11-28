import Foundation
import Testing
@testable import DuoUpdaterCore

struct MagicQuitChangelogRecipeTests {
    // Excerpts from the vendor's v2.0 tag.
    private static let markdown = """
        ## Version 2.0 - 2026-07-20

        ### New
        - Time spent asleep or with the screen locked no longer counts as idle time.

        ### Improvements
        - Requires macOS 14 or later.

        ## Version 1.4 - 2023-12-21

        ### Improvements
        - Apps that should not have been terminated where terminated (e.g. apps that run in the background like Cleanshot X, Bartender or Paste)
        """

    @Test func rendersTaggedVersionHistoryAndNativeHeadings() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.MagicQuit", channel: .stable))
        #expect(recipe.source.absoluteString
            == "https://raw.githubusercontent.com/BigBerny/magicquit/v2.0/CHANGELOG.md")
        #expect(recipe.resolvedSource(forVersion: "2.11.3").absoluteString
            == "https://raw.githubusercontent.com/BigBerny/magicquit/v2.11.3/CHANGELOG.md")

        let history = try #require(ChangelogExtractor.extract(from: Self.markdown, using: recipe))
        #expect(history.entries.map(\.version) == ["2.0"])
        #expect(history.entries.map(\.date) == ["2026-07-20"])
        let release = try #require(history.entries.first)
        #expect(release.content == [
            .heading("New"),
            .note("Time spent asleep or with the screen locked no longer counts as idle time."),
            .heading("Improvements"),
            .note("Requires macOS 14 or later."),
        ])
    }

    @Test func aLegacyCopyUsesThePublishedSnapshotUntilItReceivesAnOffer() throws {
        let app = InstalledApp(
            name: "MagicQuit", bundleID: "com.MagicQuit", shortVersion: "1.4",
            buildVersion: "15", path: URL(fileURLWithPath: "/Applications/MagicQuit.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let offline = UpdateResult(app: app, remote: nil, status: .error("lookup failed"))
        let legacy = try #require(ChangelogRecipeSelection.recipe(for: offline))
        #expect(legacy.sourceTemplate == nil)
        #expect(legacy.resolvedSource(forVersion: ChangelogRecipeSelection.targetVersion(for: offline)).absoluteString
            == "https://raw.githubusercontent.com/BigBerny/magicquit/v2.0/CHANGELOG.md")
        let history = try #require(ChangelogExtractor.extract(from: Self.markdown, using: legacy))
        #expect(history.entries.map(\.version) == ["1.4"])
        #expect(history.entries.last?.items.count == 1)

        let offer = RemoteVersion(shortVersion: "2.1", version: "17",
                                  downloadURL: nil, sourceName: "Sparkle")
        let checked = UpdateResult(app: app, remote: offer, status: .updateAvailable(latest: "2.1"))
        let current = try #require(ChangelogRecipeSelection.recipe(for: checked))
        #expect(current.resolvedSource(forVersion: ChangelogRecipeSelection.targetVersion(for: checked)).absoluteString
            == "https://raw.githubusercontent.com/BigBerny/magicquit/v2.1/CHANGELOG.md")
    }
}
