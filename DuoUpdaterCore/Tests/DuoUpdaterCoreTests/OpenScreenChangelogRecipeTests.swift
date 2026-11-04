import Foundation
import Testing

@testable import DuoUpdaterCore

/// OpenScreen is detected by its Homebrew cask, which supplies no notes. The
/// release bodies do, so the recipe reads them with the shared `.gitHubReleases`
/// decoder. This fixture is the top of the real `v2.2.1` body (2026-11-03), which
/// opens with a call to action before `## What's Changed`.
private let openScreenBodyFixture = #"""
If OpenScreen saves you time, a star on the repo helps others find it.

## What's Changed

* ci: retry validating the stapled macOS DMG when Apple drops the connection by @EtienneLescot in https://github.com/getopenscreen/openscreen/pull/812
* fix(compositor): pick the YCbCr matrix per frame on macOS by @EtienneLescot in https://github.com/getopenscreen/openscreen/pull/815


**Full Changelog**: https://github.com/getopenscreen/openscreen/compare/v2.2.0...v2.2.1
"""#

@Suite struct OpenScreenChangelogRecipeTests {

    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == "com.etiennelescot.openscreen"
        })
    }

    @Test func readsTheReleaseBodies() throws {
        let r = try recipe()
        #expect(r.structuredFormat == .gitHubReleases)
        #expect(r.source.absoluteString.contains("api.github.com/repos/getopenscreen/openscreen/releases"))
        #expect(r.channel == .stable)
    }

    /// The generated "## What's Changed" list becomes the items, with the
    /// `by @author in <PR url>` suffix and the compare link stripped.
    @Test func theGeneratedBodyBecomesItsChanges() throws {
        let entry = try #require(GitHubMarkdownParser.parse(
            body: openScreenBodyFixture, version: "2.2.1", date: "2026-11-03")?.entries.first)
        #expect(entry.items.count == 2)
        #expect(entry.items.first == "ci: retry validating the stapled macOS DMG when Apple drops the connection")
        #expect(!entry.items.contains { $0.contains("by @") })
        #expect(!entry.items.contains { $0.contains("Full Changelog") })
    }
}
