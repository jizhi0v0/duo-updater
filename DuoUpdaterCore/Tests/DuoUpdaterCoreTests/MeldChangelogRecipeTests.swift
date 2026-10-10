import Testing
import Foundation
@testable import DuoUpdaterCore

// Meld — the first three releases of the real
// `gitlab.com/api/v4/projects/dehesselle%2Fmeld_macos/releases` response, each
// cut right after its `released_at` field (author, commit and assets dropped),
// plus one release with a null `description`, which must be skipped and must
// not borrow the next release's notes.
private let meldReleases = #"""
[{"name":"v3.22.3+105","tag_name":"v3.22.3+105","description":"- Update dependencies.\n- Modernize application bundle structure.","created_at":"2025-03-03T20:25:12.636Z","released_at":"2025-03-03T20:25:12.000Z"},{"name":"v3.22.3+101","tag_name":"v3.22.3+101","description":null,"created_at":"2025-01-20T10:00:00.000Z","released_at":"2025-01-20T10:00:00.000Z"},{"name":"v3.22.3+100","tag_name":"v3.22.3+100","description":"- Set UI font to \"SF Pro\" to improve font rendering quality (most notably: kerning).\n- Update dependencies.","created_at":"2025-01-19T22:58:30.274Z","released_at":"2025-01-19T22:58:30.000Z"},{"name":"v3.22.3+96","tag_name":"v3.22.3+96","description":"- Update Meld to 3.22.3.\n- Update Pango to fix the infamous \"garbled characters\" issue.\n- Update Python to 3.10.16.","created_at":"2025-01-11T23:09:07.238Z","released_at":"2025-01-11T23:09:07.000Z"}]
"""#

@Test func meldChangelogReadsGitLabReleases() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.gnome.Meld"))
    let log = try #require(ChangelogExtractor.extract(from: meldReleases, using: recipe))
    // The null-description release is skipped, not merged into its neighbour.
    #expect(log.entries.map(\.version) == ["3.22.3+105", "3.22.3+100", "3.22.3+96"])
    let newest = try #require(log.entries.first)
    #expect(newest.date == "2025-03-03")
    #expect(newest.items == ["Update dependencies.", "Modernize application bundle structure."])
    // JSON escapes are decoded: `\"SF Pro\"` renders as a quoted name.
    #expect(log.entries[1].items.first
        == #"Set UI font to "SF Pro" to improve font rendering quality (most notably: kerning)."#)
    #expect(log.entries[2].items.count == 3)
}
