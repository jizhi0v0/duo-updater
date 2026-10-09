import Testing
import Foundation
@testable import DuoUpdaterCore

/// `https://iterm2.com/appcasts/full_changes.txt` (the stable feed's notes link),
/// captured 2026-10-08: its first 19 lines verbatim, i.e. the version line, the
/// one section heading and the first three of its 15 items.
private let stableFixture = """
Version 3.7.3 of iTerm2 was built on September 22, 2026.

Bug Fixes:
- Fixed the Python API not reporting OSC 8
  hyperlinks. A cell’s CellStyle.url is now
  populated, so scripts reading screen contents
  can see the link target.
- Fixed the Screen setting in Settings >
  Profiles > Window. Choosing “Main Screen”
  left the popup blank and showed no checkmark
  next to it when reopened, although the
  setting was saved correctly.
- Fixed a crash when a program wrote a hyperlink
  whose web address contained an emoji or other
  character outside the Basic Multilingual
  Plane. The link is now handled correctly
  instead of terminating iTerm2, which could
  recur on restore because the saved session
  replayed the same link.

"""

/// The same file for 3.7.4, captured 2026-10-09: its first 10 lines verbatim
/// (the version line, the heading and the first two of its 17 items). This
/// version line ends at the year, with no period.
private let stableNoPeriodFixture = """
Version 3.7.4 was built on October 8, 2026

Bug Fixes:
- Fixed a crash that could recur every time
  iTerm2 saved window state. Quitting while a
  save was in progress could store duplicate
  entries in the saved-state database, which
  later saves could not handle.
- Fixed a crash when opening a new tab next to a
  tab in a tab group.

"""

/// `https://iterm2.com/appcasts/testing_changes3.txt` (the test-release feed's
/// notes link), captured 2026-10-08, trimmed to whole items: the wrapped version
/// line, the credit paragraph, all four section headings and one item under each
/// (lines 1–14, 48–49, 217–224, 343 and 357–361, every line verbatim).
private let testReleaseFixture = """
Version 3.7.4beta1 of iTerm2 was built on
September 30, 2026.

Credit to Nimanou (nuved) for the right-to-left
rendering, selection, and copy improvements in
this release.

Major New Features:
- iTerm2 is now localized: the interface follows
  your Mac’s language and is available in
  Brazilian Portuguese, German, Japanese, Russian,
  and Simplified Chinese.

New Features:
- iTerm2 now answers CSI 16 t (report character
  cell size), which was previously ignored.

Improvements:
- iTerm2 now recognizes when a terminal is running
  on your own Mac by machine identity rather than
  by hostname, so features that only work locally
  keep working over a VPN or Tailscale connection
  where the hostname no longer matches. Reinstall
  shell integration (iTerm2 > Install Shell
  Integration) to enable this.

Bug Fixes:
- Make Text Bigger works again when you type it as
  ⌘⇧= (the way you type ⌘+). Since 3.7.0, that
  keystroke opened the Clippings panel instead,
  because Show Clippings had claimed it. Show
  Clippings is now ⌘⇧⌥G. Issue 13022.

"""

/// `https://iterm2.com/appcasts/nightly_changes.txt`, captured 2026-10-08: its
/// first entry verbatim. A commit log, with no version line anywhere in the file.
private let nightlyFixture = """
2026-10-07: Keep session mentions linkable when markdown
pairs their underscores

Two stableIDs in one chat message (@ptys_A... and
@ptys_B...) put an underscore before each body, which
markdown treated as an emphasis pair and consumed, so the
ids rendered as dead ptysXXXX text. Mentions are now swapped
for alphanumeric placeholders before the markdown pass and
restored afterwards, on both the Mac and the Companion app.
Code blocks, indented code lines, inline code, link
destinations, and URLs are left alone so a placeholder never
leaks into a copy button or a link target.

"""

@Suite struct ITerm2ChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes
            .first { $0.bundleID == "com.googlecode.iterm2" })
    }

    private func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { if case .heading(let text) = $0 { text } else { nil } }
    }

    private func result(installed: String, latest: String, changelogURL: String) -> UpdateResult {
        let app = InstalledApp(
            name: "ZZFixture iTerm", bundleID: "com.googlecode.iterm2",
            shortVersion: installed, buildVersion: installed,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-iTerm.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: latest, version: latest, downloadURL: nil,
            sourceName: "Sparkle", changelogURL: URL(string: changelogURL))
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: latest))
    }

    // MARK: - The text

    /// Mutation: drop `headingPattern` — the heading disappears.
    @Test func readsTheStableFile() throws {
        let log = try #require(ChangelogExtractor.extract(from: stableFixture, using: try recipe()))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "3.7.3")
        #expect(entry.date == "September 22, 2026")
        #expect(entry.items.count == 3)
        #expect(headings(entry) == ["Bug Fixes"])
    }

    /// Mutation: require the period after the year again — the entry no longer
    /// matches and the pane embeds the file.
    @Test func readsAStableFileWithNoPeriodAfterTheYear() throws {
        let log = try #require(ChangelogExtractor.extract(
            from: stableNoPeriodFixture, using: try recipe()))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "3.7.4")
        #expect(entry.date == "October 8, 2026")
        #expect(entry.items.count == 2)
        #expect(entry.items.last == "Fixed a crash when opening a new tab next to a tab in a tab group.")
        #expect(headings(entry) == ["Bug Fixes"])
    }

    /// Mutation: item pattern `(?m)^-[ \t]+(?<item>[^\n]+)` — each item stops at
    /// its first line ("Fixed the Python API not reporting OSC 8").
    @Test func aHardWrappedItemIsOneLine() throws {
        let log = try #require(ChangelogExtractor.extract(from: stableFixture, using: try recipe()))
        let items = try #require(log.entries.first).items
        #expect(items.first == "Fixed the Python API not reporting OSC 8 hyperlinks. A cell’s "
            + "CellStyle.url is now populated, so scripts reading screen contents can see the link target.")
        #expect(items[1] == "Fixed the Screen setting in Settings > Profiles > Window. Choosing "
            + "“Main Screen” left the popup blank and showed no checkmark next to it when reopened, "
            + "although the setting was saved correctly.")
        #expect(!items.contains { $0.contains("\n") })
    }

    /// The date wraps onto its own line here. Mutation: `[ \t]+` instead of `\s+`
    /// before the date — the entry no longer matches and the pane embeds the file.
    @Test func readsTheTestReleaseFile() throws {
        let log = try #require(ChangelogExtractor.extract(from: testReleaseFixture, using: try recipe()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "3.7.4beta1")
        #expect(entry.date == "September 30, 2026")
        #expect(headings(entry) == ["Major New Features", "New Features", "Improvements", "Bug Fixes"])
        #expect(entry.items.count == 4)
        #expect(!entry.items.contains { $0.contains("Nimanou") })
        #expect(entry.items.last == "Make Text Bigger works again when you type it as ⌘⇧= (the way you "
            + "type ⌘+). Since 3.7.0, that keystroke opened the Clippings panel instead, because Show "
            + "Clippings had claimed it. Show Clippings is now ⌘⇧⌥G. Issue 13022.")
        // Each heading sits in front of its own item, not bunched at the top.
        let order = entry.content.map { block -> String in
            if case .heading = block { "h" } else { "n" }
        }
        #expect(order == ["h", "n", "h", "n", "h", "n", "h", "n"])
    }

    @Test func theNightlyCommitLogYieldsNothing() throws {
        #expect(ChangelogExtractor.extract(from: nightlyFixture, using: try recipe()) == nil)
    }

    // MARK: - Which copy it is offered to

    /// The page is the one this copy's own feed resolved, so the track decides.
    /// Mutation: widen `feedPagePattern` to `[a-z_]+\d*\.txt` — a nightly copy
    /// is offered the recipe.
    @Test func offeredForStableAndTestReleaseButNotNightly() throws {
        let stable = result(installed: "3.7.2", latest: "3.7.3",
                            changelogURL: "https://iterm2.com/appcasts/full_changes.txt")
        let offered = try #require(ChangelogRecipeSelection.recipe(for: stable))
        #expect(ChangelogRecipeSelection.feedPage(for: stable, recipe: offered)?.absoluteString
            == "https://iterm2.com/appcasts/full_changes.txt")

        let testRelease = result(installed: "3.7.3", latest: "3.7.4beta1",
                                 changelogURL: "https://iterm2.com/appcasts/testing_changes3.txt")
        #expect(ChangelogRecipeSelection.recipe(for: testRelease) != nil)

        let nightly = result(installed: "3.7.20261007-nightly", latest: "3.7.20261008-nightly",
                             changelogURL: "https://iterm2.com/appcasts/nightly_changes.txt")
        #expect(ChangelogRecipeSelection.recipe(for: nightly) == nil)
        #expect(ChangelogRecipeSelection.fallbackPage(for: nightly)
            == .fromSource(URL(string: "https://iterm2.com/appcasts/nightly_changes.txt")!))
    }

    @Test func refusesOtherURLs() throws {
        let recipe = try recipe()
        for string in [
            "http://iterm2.com/appcasts/full_changes.txt",
            "https://iterm2.com/appcasts/full_changes.txt?x=1",
            "https://iterm2.com/downloads/stable/iTerm2-3_7_3.changelog",
            "https://iterm2.com/appcasts/nightly_changes.txt",
        ] {
            #expect(recipe.acceptedFeedPage(URL(string: string)!) == nil, "\(string)")
        }
    }
}
