import Testing
import Foundation
@testable import DuoUpdaterCore

/// `code.kimi.com/kimi-code/desktop/binaries/1.0.1/changelog.en.md` as served
/// (fetched 2026-09-18), trimmed to three bullets per group. The file never names
/// its version, which is the whole reason for `versionFromTemplate`.
private let kimiCodeChangelogFixture = #"""
### Polish

- Chat links gain a hover bubble: full URL plus one-click external or right-panel opening.
- The Changes detail page adds an "Open file" button for viewing the file directly.
- Terminal tabs now use Control+backtick; toggling the bottom panel no longer has a default shortcut.

### Bug Fixes

- Fixed some models being unable to invoke the built-in browser.
- Fixed the built-in browser failing to open on the first turn of a new session.
- Fixed the image preview close button being unclickable on macOS.

"""#

/// The body `cdn.kimi.com` answers for a version it has no notes for, under a 404.
/// The fetch fails before any parse, so this only proves the pattern would not
/// read it as notes if a CDN ever served it under a 200.
private let kimiCodeMissingNotesBody = #"""
{"Code":"NoSuchKey","Message":"The specified key does not exist."}
"""#

@Suite struct KimiCodeChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == "com.kimi.code.desktop" })
    }

    @Test func theEntryIsNamedByTheRequestedVersion() throws {
        let recipe = try recipe()
        #expect(recipe.resolvedSource(forVersion: "1.0.1").absoluteString
            == "https://code.kimi.com/kimi-code/desktop/binaries/1.0.1/changelog.en.md")

        let log = try #require(
            ChangelogService.parse(recipe, body: kimiCodeChangelogFixture, version: "1.0.1"))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "1.0.1")
        #expect(entry.date == nil)
        #expect(entry.items.count == 6)
        #expect(entry.items.first
            == "Chat links gain a hover bubble: full URL plus one-click external or right-panel opening.")
        #expect(entry.items.last == "Fixed the image preview close button being unclickable on macOS.")
        // The group headings are headings, in document order around their bullets.
        let headings = entry.content.compactMap { block -> String? in
            if case .heading(let text) = block { return text }
            return nil
        }
        #expect(headings == ["Polish", "Bug Fixes"])
        guard case .heading("Bug Fixes") = entry.content[4] else {
            Issue.record("expected the second heading after three notes: \(entry.content)")
            return
        }
    }

    /// With no version there is nothing that could name the entry, so nothing is
    /// extracted — the notes are not shown under an empty version.
    @Test func withoutAVersionNothingIsExtracted() throws {
        let recipe = try recipe()
        #expect(ChangelogService.parse(recipe, body: kimiCodeChangelogFixture) == nil)
        #expect(ChangelogService.parse(recipe, body: kimiCodeChangelogFixture, version: "") == nil)
    }

    @Test func aBodyThatIsNotNotesIsNotRead() throws {
        #expect(ChangelogService.parse(
            try recipe(), body: kimiCodeMissingNotesBody, version: "1.0.2") == nil)
    }
}

/// The flag's contract, held over the registry. Each property here fails silently
/// when broken: a template on `{major}` or a fixed `source` puts one version's name
/// on another version's notes; a second entry on one page would carry the same
/// version twice; a `version` group of the recipe's own would be read and then
/// ignored, and a `title` group would keep an entry that has no version. The other
/// routes don't fit: a structured decoder never sees the version, and an index
/// link or a feed page chooses the page by something other than the version.
@Test func versionFromTemplateOnlyLandsOnAOneReleasePerVersionPage() {
    let recipes = ChangelogRecipeRegistry.recipes.filter(\.versionFromTemplate)
    #expect(!recipes.isEmpty, "no versionFromTemplate recipe left — this check would pass vacuously")
    for recipe in recipes {
        #expect(recipe.sourceTemplate?.contains("{version}") == true,
                "\(recipe.bundleID): the version must be the one in the URL")
        #expect(recipe.maxEntries == 1, "\(recipe.bundleID): one page is one release")
        #expect(!recipe.entryPattern.contains("(?<version>"),
                "\(recipe.bundleID): a version group is ignored beside versionFromTemplate")
        // A title names an entry on its own, so with no version to request it
        // would be kept and shown without one.
        #expect(!recipe.entryPattern.contains("(?<title>"),
                "\(recipe.bundleID): a titled entry survives a missing version")
        #expect(recipe.structuredFormat == nil, "\(recipe.bundleID): regex path only")
        #expect(recipe.indexLinkPattern == nil, "\(recipe.bundleID): the index link names the page, not the version")
        #expect(recipe.feedPagePattern == nil, "\(recipe.bundleID): a feed page is not templated")
    }
}
