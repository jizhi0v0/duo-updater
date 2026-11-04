import Foundation
import Testing

@testable import DuoUpdaterCore

/// SmartClose's Sparkle feed carries no notes, so the recipe reads the GitHub
/// release bodies through the shared `.gitHubReleases` decoder. This fixture is
/// the real `v0.4.1` body (2026-10-04), which is hand-written rather than
/// generated: `## Fixes` with bullets that name the issue.
private let smartCloseBodyFixture = #"""
## Fixes

- **macOS 27 crash fixed (#20).** Clicking anywhere in SmartClose's own Settings window (or its menu bar icon) while monitoring was active could crash SmartClose with `EXC_BREAKPOINT`. SmartClose now keeps its settings window out of the monitored set.
- **Menu bar icon no longer hides behind the notch.**
"""#

@Suite struct SmartCloseChangelogRecipeTests {

    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == "com.smartclose.app"
        })
    }

    /// Notes come from the release JSON, because the Sparkle feed has none.
    @Test func readsTheReleaseBodies() throws {
        let r = try recipe()
        #expect(r.structuredFormat == .gitHubReleases)
        #expect(r.source.absoluteString.contains("api.github.com/repos/mahirozdin/SmartClose/releases"))
        #expect(r.channel == .stable)
    }

    /// The body's `## Fixes` heading is dropped and its bullets become the items.
    @Test func theBodyBecomesItsFixes() throws {
        let entry = try #require(GitHubMarkdownParser.parse(
            body: smartCloseBodyFixture, version: "0.4.1", date: "2026-10-04")?.entries.first)
        #expect(entry.version == "0.4.1")
        #expect(entry.date == "2026-10-04")
        #expect(entry.items.count == 2)
        #expect(entry.items.first?.contains("macOS 27 crash fixed (#20)") == true)
        #expect(!entry.items.contains { $0 == "Fixes" })
    }
}
