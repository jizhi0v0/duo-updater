import Foundation
import Testing

@testable import DuoUpdaterCore

/// Brave's stable changelog is the repo's `CHANGELOG_DESKTOP.md`, not the appcast:
/// the feed item's `<description>` only links to it. This fixture is the top of
/// that file (the 1.98.63 and 1.98.62 entries) with the long link targets kept —
/// they are what `markdownSource` has to unwrap.
private let braveChangelogFixture = #"""
# Changelog

## [1.98.63](https://github.com/brave/brave-browser/releases/tag/v1.98.63)

 - Upgraded Chromium to 156.0.8078.80. ([#60306](https://github.com/brave/brave-browser/issues/60306)) ([Changelog for 156.0.8078.80](https://chromium.googlesource.com/chromium/src/+log/156.0.8078.74..156.0.8078.80?pretty=fuller&n=1000))

## [1.98.62](https://github.com/brave/brave-browser/releases/tag/v1.98.62)

 - [Security] Fixed "brave://" scheme navigation issue as reported on HackerOne by miauuu. ([#60127](https://github.com/brave/brave-browser/issues/60127))
 - Upgraded Chromium to 156.0.8078.74. ([#60210](https://github.com/brave/brave-browser/issues/60210)) ([Changelog for 156.0.8078.74](https://chromium.googlesource.com/chromium/src/+log/156.0.8078.48..156.0.8078.74?pretty=fuller&n=1000))

## [1.98.60](https://github.com/brave/brave-browser/releases/tag/v1.98.60)

### Leo

 - Added passages to the reader-mode summary. ([#60102](https://github.com/brave/brave-browser/issues/60102))
"""#

@Suite struct BraveChangelogRecipeTests {

    private func changelog() throws -> Changelog {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.brave.Browser"))
        return try #require(
            ChangelogExtractor.extract(from: braveChangelogFixture, using: recipe))
    }

    /// The recipe reads the markdown file, not the appcast's link-only description.
    @Test func readsTheDesktopChangelog() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.brave.Browser"))
        #expect(recipe.source.absoluteString.contains("CHANGELOG_DESKTOP.md"))
        #expect(recipe.markdownSource)
    }

    /// The file's own `# Changelog` preamble is not a version block, and a version
    /// with no category heading still becomes an entry.
    @Test func versionBlocksBecomeEntries() throws {
        let entries = try changelog().entries
        #expect(entries.map(\.version) == ["1.98.63", "1.98.62", "1.98.60"])
    }

    /// Inline links are unwrapped: the reader sees `#60306`, not `[#60306](…)`.
    @Test func markdownLinksInBulletsAreUnwrapped() throws {
        let newest = try #require(try changelog().entries.first)
        #expect(newest.items.count == 1)
        let item = try #require(newest.items.first)
        #expect(item.hasPrefix("Upgraded Chromium to 156.0.8078.80."))
        #expect(item.contains("#60306"))
        #expect(!item.contains("]("))
    }

    /// `### Leo` is a section, not a bullet.
    @Test func categoryHeadingsBecomeSections() throws {
        let oldest = try #require(try changelog().entries.last)
        #expect(oldest.items.count == 1)
        #expect(oldest.items.first?.contains("Added passages") == true)
    }
}
