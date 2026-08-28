import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite struct ChangelogItemSyntaxTests {
    /// A GitHub release body keeps its inline Markdown, so the changelog has to
    /// say so — `Text(someString)` renders Markdown syntax literally, and the
    /// user saw `**bold**` and `[text](url)` in the notes pane.
    @Test func gitHubNotesDeclareThemselvesMarkdown() throws {
        let body = """
        - **Fixed the thing**: it was broken ([#5954](https://example.com/5954)).
        - Another line.
        """
        let log = try #require(GitHubMarkdownParser.parse(body: body, version: "1.0", date: nil))
        #expect(log.itemSyntax == .markdown)
        // The raw syntax is deliberately still in the item — rendering decides.
        #expect(log.entries.first?.items.first?.contains("**") == true)
    }

    /// Page-scraped notes come out of `ChangelogExtractor` with tags already
    /// stripped, so they are plain prose: parsing them as Markdown would eat a
    /// literal `*` or `_` that a vendor actually typed.
    @Test func scrapedNotesStayPlain() throws {
        let recipe = ChangelogRecipe(
            bundleID: "test.app",
            source: URL(string: "https://example.com")!,
            entryPattern: #"<h4>(?<version>[0-9.]+)</h4>(?<body>.*)"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#])
        let log = try #require(ChangelogExtractor.extract(
            from: "<h4>1.0</h4><ul><li>a * b and _c_</li></ul>", using: recipe))
        #expect(log.itemSyntax == .plain)
        #expect(log.entries.first?.items.first == "a * b and _c_")
    }

    /// The flag rides along in `Changelog`'s own `Codable` conformance, and a
    /// `Changelog` written before the flag existed must still decode (as plain).
    /// Decoded here directly, NOT through either on-disk changelog cache: as of
    /// issue #112 both `ChangelogDiskCache` and `BrewFormulaReleaseService` wrap
    /// `Changelog` in a `Stored` type carrying `parserGeneration`, whose own
    /// decode fails first for a payload this old (see
    /// `Changelog.parserGeneration`'s doc comment) — so this tolerance is no
    /// longer reachable via either cache, only via the generation-less
    /// remote-catalog path `Changelog` is also `Codable` for.
    @Test func syntaxSurvivesTheDiskCacheAndOldPayloadsDecode() throws {
        let log = Changelog(
            entries: [.init(title: nil, version: "1.0", date: nil, items: ["x"], content: [])],
            itemSyntax: .markdown)
        let roundTripped = try JSONDecoder().decode(
            Changelog.self, from: try JSONEncoder().encode(log))
        #expect(roundTripped.itemSyntax == .markdown)

        let legacy = #"{"entries":[{"version":"1.0","items":["x"],"content":[]}]}"#
        let decoded = try JSONDecoder().decode(
            Changelog.self, from: Data(legacy.utf8))
        #expect(decoded.itemSyntax == .plain)
    }
}
