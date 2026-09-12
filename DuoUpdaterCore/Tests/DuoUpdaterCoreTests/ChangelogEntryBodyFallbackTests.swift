import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ChangelogExtractor`'s entry loop says "Items come from the `body` group when
/// present, else the whole entry", but its fallback was `group(match, nil, …)`,
/// whose own contract is "capture group 1 if present, else the whole match". A
/// named group IS a numbered group in `NSRegularExpression`, so for any entry
/// pattern without a `<body>` group the fallback handed the item regexes the
/// `version` capture — a few characters of version string — instead of the entry.
/// Every one of the 65 registered entry patterns carries a `body` group today, so
/// nothing failed; the next recipe written without one would have produced an
/// empty pane with no diagnostic saying why.
///
/// The fallback now takes the whole match, which is what the comment always
/// claimed. `firstNonEmptyItemHits`, `imageHits` and `headingHits` keep the
/// group-1-first fallback on purpose — that one is documented at those call sites
/// and several registered `itemPatterns` rely on it.
@Suite struct ChangelogEntryBodyFallbackTests {

    /// The entry pattern has no `body` group, so the items must be looked for in
    /// the whole match. Before the fix they were looked for inside "3.1.0" and the
    /// entry was dropped for having none, taking the whole changelog to nil.
    @Test func anEntryPatternWithoutABodyGroupSearchesTheWholeMatch() throws {
        let page = """
            <div class="rel"><h2>3.1.0</h2>\
            <ul><li>Fixed a crash on launch</li><li>Added a preference</li></ul></div>
            """
        let recipe = ChangelogRecipe(
            bundleID: "zz.fixture.bodyless",
            source: URL(string: "https://zzfixture.example/notes")!,
            entryPattern: #"<h2>(?<version>[^<]+)</h2>(?:.*?)(?=</div>)"#,
            itemPatterns: [#"<li>(?<item>[^<]+)</li>"#])
        let log = try #require(ChangelogExtractor.extract(from: page, using: recipe))
        #expect(log.entries.count == 1)
        #expect(log.entries[0].version == "3.1.0")
        #expect(log.entries[0].items == ["Fixed a crash on launch", "Added a preference"])
    }

    /// The other half: a pattern that DOES declare `body` still reads only that
    /// group, so an entry can't absorb the markup around it.
    @Test func anEntryPatternWithABodyGroupStillReadsOnlyThatGroup() throws {
        let page = """
            <li>Leaked from before the entry</li>\
            <div class="rel"><h2>3.1.0</h2><ul><li>Inside the body</li></ul></div>
            """
        let recipe = ChangelogRecipe(
            bundleID: "zz.fixture.bodied",
            source: URL(string: "https://zzfixture.example/notes")!,
            entryPattern: #"<h2>(?<version>[^<]+)</h2>(?<body>.*?)(?=</div>)"#,
            itemPatterns: [#"<li>(?<item>[^<]+)</li>"#])
        let log = try #require(ChangelogExtractor.extract(from: page, using: recipe))
        #expect(log.entries.count == 1)
        #expect(log.entries[0].items == ["Inside the body"])
    }
}
