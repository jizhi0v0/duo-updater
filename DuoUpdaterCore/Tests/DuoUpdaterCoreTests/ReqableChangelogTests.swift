import Foundation
import Testing

@testable import DuoUpdaterCore

/// Reqable writes one cross-platform release body, sectioned by platform
/// (`### windows-macos-linux-android-ios` for the shared notes, then
/// per-platform sections). This is the real body of `3.3.9`.
@Suite struct ReqableChangelogTests {

    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == "com.reqable.macosx"
        })
    }

    /// The platform-only sections are skipped, and the shared one is not.
    /// Mutation: drop `skipSections` from the recipe → the linux line appears and
    /// both assertions fail.
    @Test func platformOnlySectionsAreSkipped() throws {
        let r = try recipe()
        #expect(r.skipSections.contains("linux"))
        #expect(r.skipSections.contains("android-ios"))

        let body = """
        ### windows-macos-linux-android-ios
        - ❗ [IMP] For security reasons, the MCP service now requires the configuration of an access token.
        - 💪 [OPT] The API service is disabled by default for security reasons and must be manually enabled in the settings, with the access token being mandatory.
        - 🐞 [FIX] A bug where some MCP tools might not work correctly due to access token issues.
        ### android-ios
        - 💪 [OPT] SSL proxy, access control, report server, and secondary proxy now support control via MCP.
        ### linux
        - 💪 [OPT] The installation package now includes the libdbusmenu-gtk dependency.
        """
        let entry = try #require(GitHubMarkdownParser.parse(
            body: body, version: "3.3.9", date: nil, skipSections: r.skipSections)?.entries.first)
        #expect(entry.items.count == 3)
        #expect(!entry.items.contains { $0.contains("libdbusmenu") })
        #expect(entry.items.first?.hasPrefix("❗ [IMP]") == true)
    }

    /// A Windows-only release (3.3.8's body is a single `### windows` section)
    /// parses to nothing, so it never shows a Mac reader a release it cannot
    /// install.
    @Test func aWindowsOnlyReleaseHasNothingToShow() throws {
        let body = """
        ### windows
        - 🐞 [FIX] A bug where the main window could not be brought to the front from a child window.
        """
        #expect(GitHubMarkdownParser.parse(
            body: body, version: "3.3.8", date: nil,
            skipSections: try recipe().skipSections) == nil)
    }
}
