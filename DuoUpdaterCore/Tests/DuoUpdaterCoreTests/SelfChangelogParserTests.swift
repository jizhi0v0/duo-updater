import Testing
import Foundation
@testable import DuoUpdaterCore

/// Verbatim shape of the repository's own `CHANGELOG.md`: a preamble, then
/// `## <version>` sections of blank-line-separated paragraphs, each opening with a
/// bold lead sentence.
private let selfChangelogFixture = """
# Changelog

User-facing release notes. The release script reads the section matching the
version being shipped, so this file is the single source of truth.

## 0.3.50

**豆包输入法 now gets checked.** It was in the list — Duo Updater looks inside
`/Library/Input Methods` — but nothing knew where to ask about it.

**Zed's release notes come back instead of an error.** GitHub lets an
unidentified caller ask only sixty questions an hour.

## 0.3.49

**Confirming a quit late no longer leaves the app updated but closed.** Some apps
guard their own quit with a dialog.

## 0.1.9

**One paragraph only.**
"""

@Test func parsesEveryVersionSectionInOrder() throws {
    let log = try #require(SelfChangelogParser.parse(selfChangelogFixture))
    #expect(log.entries.map(\.version) == ["0.3.50", "0.3.49", "0.1.9"])
    #expect(log.entries[0].items.count == 2)
    #expect(log.entries[1].items.count == 1)
    #expect(log.entries[2].items.count == 1)
}

/// The file's own preamble sits above the first `##` and is not a release.
@Test func theFilePreambleIsNotAnEntry() throws {
    let log = try #require(SelfChangelogParser.parse(selfChangelogFixture))
    #expect(!log.entries.contains { $0.items.contains { $0.contains("single source of truth") } })
}

/// A paragraph wrapped across source lines is ONE item — the wrapping is an
/// artifact of editing the file, not of what it says.
@Test func aWrappedParagraphIsOneItem() throws {
    let log = try #require(SelfChangelogParser.parse(selfChangelogFixture))
    #expect(log.entries[0].items[0]
        == "**豆包输入法 now gets checked.** It was in the list — Duo Updater looks inside `/Library/Input Methods` — but nothing knew where to ask about it.")
}

/// Markdown syntax is declared: the bold lead that opens every paragraph is the
/// whole readability of this file, and plain rendering would print the asterisks.
@Test func itemsKeepTheirMarkdownSyntax() throws {
    let log = try #require(SelfChangelogParser.parse(selfChangelogFixture))
    #expect(log.itemSyntax == .markdown)
}

/// nil, not an empty changelog, when the body carries no version section — a 404
/// body or an error page. An empty list would read as "no releases".
@Test func aBodyWithNoVersionsYieldsNil() {
    #expect(SelfChangelogParser.parse("404: Not Found") == nil)
    #expect(SelfChangelogParser.parse("") == nil)
    #expect(SelfChangelogParser.parse("# Changelog\n\nJust a preamble, no releases.\n") == nil)
}

/// A heading with no paragraphs under it (a version stubbed in ahead of writing
/// its notes) is skipped rather than shown as a bare version with nothing in it.
@Test func anEmptySectionIsSkipped() throws {
    let log = try #require(SelfChangelogParser.parse("## 9.9.9\n\n## 1.0.0\n\n**Real notes.**\n"))
    #expect(log.entries.map(\.version) == ["1.0.0"])
}

/// The live file, so a format drift in our own release notes is caught here
/// rather than by a user opening an empty window.
@Test func theRepositoryChangelogParses() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoUpdaterCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // DuoUpdaterCore
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("CHANGELOG.md")
    let text = try #require(try? String(contentsOf: url, encoding: .utf8))
    let log = try #require(SelfChangelogParser.parse(text))
    #expect(log.entries.count > 20, "the file has 50+ versions; a handful means the shape drifted")
    // Newest first, and every entry has something to show.
    #expect(log.entries.allSatisfy { !$0.items.isEmpty && !$0.version.isEmpty })
}
