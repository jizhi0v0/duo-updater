import Testing
import Foundation
@testable import DuoUpdaterCore

/// AnyDesk publishes one changelog for every platform, newest first, and Windows
/// runs ahead of macOS. Both facts are traps, so they are pinned here with the
/// real file's shape (captured 2026-08-16 from
/// `https://download.anydesk.com/changelog.txt`).
private let anyDeskChangelogFixture = """
10.08.2026 - 9.7.14 (Windows)
------------------
Fixed Bugs:
- Fixed an issue where the local camera image appeared frozen

28.07.2026 - 9.7.9 (Linux)
------------------
Fixed Bugs:
- Fixed a crash on Wayland

22.07.2026 - 9.7.3 (macOS)
------------------
New Features:
- Redesigned the Whiteboard UI

02.07.2026 - 9.7.2 (macOS)
------------------
Fixed Bugs:
- Fixed a rendering issue
"""

struct AnyDeskProbeRecipeTests {

    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.philandro.anydesk" }
    }

    @Test func readsTheNewestMacOSEntry() throws {
        let recipe = try #require(recipe)
        #expect(VendorProbeRecipe.extractVersion(
            from: anyDeskChangelogFixture, pattern: recipe.versionPattern) == "9.7.3")
    }

    /// Windows sits on a higher number in the same file. Taking the highest match,
    /// or dropping the `(macOS)` anchor, offers a build that will never install.
    @Test func neverTakesTheHigherWindowsVersion() throws {
        let recipe = try #require(recipe)
        #expect(!recipe.selectHighest)
        #expect(VendorProbeRecipe.highestVersion(
            from: anyDeskChangelogFixture, pattern: recipe.versionPattern) == "9.7.3")
        // The trap, kept explicit: without the platform anchor, Windows wins.
        #expect(VendorProbeRecipe.highestVersion(
            from: anyDeskChangelogFixture,
            pattern: #"([0-9]+(?:\.[0-9]+)+)\s+\("#) == "9.7.14")
    }

    /// The dmg is unversioned and always serves whatever the file names first, so
    /// the install URL is fixed rather than built from the version.
    @Test func installsTheUnversionedDMG() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        guard case .fixed(let url) = spec.urlSource else {
            Issue.record("expected a fixed URL"); return
        }
        #expect(url.absoluteString == "https://download.anydesk.com/anydesk.dmg")
        #expect(spec.kind == .dmg)
    }

    /// The probe must read the text endpoint, not either of the pages behind
    /// Cloudflare — those answer 403 to anything scripted.
    @Test func probesTheTextEndpointNotTheBlockedPages() throws {
        let recipe = try #require(recipe)
        #expect(recipe.url.absoluteString == "https://download.anydesk.com/changelog.txt")
        #expect(recipe.url.host == "download.anydesk.com")
    }
}
