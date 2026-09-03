import Testing
import Foundation
@testable import DuoUpdaterCore

/// AnyDesk publishes every platform's releases in one plain-text file, so the
/// thing worth pinning is that the recipe reads the macOS ones and ONLY those:
/// Windows runs on a higher number (9.7.12 here, 9.7.15 live) and iOS/Android
/// ship from the same file, so a pattern that lost the `(macOS)` anchor would
/// silently list another platform's notes under this app.
///
/// Fixture: four consecutive entries from `download.anydesk.com/changelog.txt`
/// (fetched 2026-09-03), two of them decoys.
@Suite struct AnyDeskChangelogRecipeTests {

    @Test func readsOnlyTheMacEntries() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.philandro.anydesk"))
        let changelog = try #require(
            ChangelogExtractor.extract(from: anyDeskChangelogFixture, using: recipe))

        #expect(changelog.entries.map(\.version) == ["9.7.3", "9.7.2"])
        let newest = try #require(changelog.entries.first)
        #expect(newest.date == "22.07.2026")
        #expect(newest.items == [
            "Visibility and online status for AnyDesk One Chat can be set manually",
            "Broad group notifications in AnyDesk One Chat",
            "Accept window color scheme fix",
            "Improved management of remote clicks in Accept Window",
        ])
    }

    /// The section labels are headings, not changes — they end in a colon and
    /// carry no leading dash, so the item pattern must not pick them up.
    @Test func sectionLabelsAreNotItems() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.philandro.anydesk"))
        let changelog = try #require(
            ChangelogExtractor.extract(from: anyDeskChangelogFixture, using: recipe))
        for entry in changelog.entries {
            #expect(!entry.items.contains { $0.hasSuffix(":") })
        }
    }
}

private let anyDeskChangelogFixture = #"""
27.07.2026 - 9.7.12 (Windows)
------------------
New Features:
- Added a warning when closing an Accept window with active sessions

Fixed Bugs:
- Fixed an issue affecting application stability

Other Changes:
- Redesigned AnyDesk One Meeting UI
- Improved the AnyDesk One UI

22.07.2026 - 9.7.3 (macOS)
------------------
New Features:
- Visibility and online status for AnyDesk One Chat can be set manually
- Broad group notifications in AnyDesk One Chat

Fixed Bugs:
- Accept window color scheme fix
- Improved management of remote clicks in Accept Window

23.07.2026 - 8.2.2 (iOS)
------------------
Fixed Bugs:
- fixed audio transmission issue
- UI fixes and adjustments

02.07.2026 - 9.7.2 (macOS)
------------------
Fixed Bugs:
- Improved toolbar icons appearance
- Fixed a bug that could cause a crash
- Minor UX improvements
"""#
