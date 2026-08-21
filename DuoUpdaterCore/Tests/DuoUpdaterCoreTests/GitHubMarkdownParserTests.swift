import Testing
@testable import DuoUpdaterCore

// MARK: - Strict pass (existing behavior — must not regress)

@Test func parsesTopLevelBulletsAndStripsPRNoise() {
    let body = """
    ## What's Changed
    - Fix the broken thing by @bob in https://github.com/o/r/pull/1
    - Add a useful feature (#42)
    ## New Contributors
    - @newbie made their first contribution
    """
    let cl = GitHubMarkdownParser.parse(body: body, version: "1.0.0", date: nil)
    #expect(cl?.entries.first?.items == ["Fix the broken thing", "Add a useful feature"])
}

@Test func strictStillSkipsIndentedSubBulletsWhenTopLevelExist() {
    // A PR-style body with top-level bullets and indented sub-detail: the strict
    // pass takes only the top-level ones (the lenient pass must NOT run here, or
    // the sub-details would leak in — the regression we're guarding against).
    let body = """
    - Top level change number one
      - indented sub detail that duplicates
    - Top level change number two
    """
    let cl = GitHubMarkdownParser.parse(body: body, version: "1.0.0", date: nil)
    #expect(cl?.entries.first?.items == ["Top level change number one", "Top level change number two"])
}

// MARK: - Lenient fallback (new — only when strict finds nothing)

@Test func lenientRescuesIndentedBulletsUnderHeadings() {
    // nvm-style: section headings + single-space-indented bullets, which the strict
    // pass skips entirely (0 items) → lenient pass should recover them.
    let body = """
    ## New Stuff
     - install from cache without network access
    ## Bug Fixes
     - reject version strings with disallowed characters
     - avoid an unbound variable somewhere
    """
    let cl = GitHubMarkdownParser.parse(body: body, version: "0.40.5", date: nil)
    #expect(cl?.entries.first?.items.count == 3)
}

@Test func lenientRescuesNumberedLists() {
    let body = """
    1. First meaningful change in the list
    2. Second meaningful change in the list
    """
    let cl = GitHubMarkdownParser.parse(body: body, version: "2.0.0", date: nil)
    #expect(cl?.entries.first?.items.count == 2)
}

@Test func lenientSkipsChecksumCodeBlocksSoHashOnlyBodyStaysNil() {
    // azure-cli-style: a link plus a SHA256 code block, no real change items. Even
    // leniently this must yield nothing (→ the UI keeps the web-view fallback)
    // rather than surfacing hash lines as "changes".
    let body = """
    https://example.com/release-notes

    ### SHA256 hashes of the release artifacts

    ```
    abc123  azure-cli-2.87.0-macos-arm64.tar.gz
    def456  azure-cli-2.87.0.msi
    ```
    """
    let cl = GitHubMarkdownParser.parse(body: body, version: "2.87.0", date: nil)
    #expect(cl == nil)
}

@Test func emptyBodyReturnsNil() {
    #expect(GitHubMarkdownParser.parse(body: "", version: "1.0.0", date: nil) == nil)
}

// MARK: - Prose pass (bodies with no list at all)

/// The shape that motivated it, verbatim from Zed's `v1.5.3-pre` (2026-08-22).
/// Before this pass a multi-release source dropped such a release entirely, so a
/// user sitting on exactly that build found no entry for their own version.
@Test func proseBodyWithoutBulletsStillProducesAnEntry() throws {
    let cl = try #require(GitHubMarkdownParser.parse(
        body: "No public-facing changes in this release. "
            + "[View the commits](https://github.com/zed-industries/zed/compare/a...b)",
        version: "1.5.3", date: nil))
    #expect(cl.entries.first?.items.count == 1)
    // Markdown syntax is declared, so the link is left intact to be rendered.
    #expect(cl.itemSyntax == .markdown)
}

/// LuLu's real notes (v4.5.1): emoji change lines with descriptions under them,
/// preceded by a shields.io sponsor badge and followed by a SHA256 block. The
/// change lines survive; the badge and the hash do not.
@Test func proseBodyDropsBadgesAndChecksumsButKeepsChangeLines() throws {
    let body = """
    🆕 You can now sponsor **LuLu**/**Objective-See Foundation**:

    [![](https://img.shields.io/static/v1?label=Sponsor)](https://github.com/sponsors/objective-see)

    ## LuLu v4.5.1
    ☑️ Improved 'Add Rules' window logic
    Better handing of deleted/invalid rules.

    🔐 Disk Image Hash (`SHA256`):
    LuLu_4.5.1.dmg: `98F4D3427F4C6FCCF9680FED22879BE90A5AE81E80EB8616C1D758755B6BB624`
    """
    let items = try #require(GitHubMarkdownParser.parse(
        body: body, version: "4.5.1", date: nil)?.entries.first?.items)
    #expect(items == [
        "🆕 You can now sponsor **LuLu**/**Objective-See Foundation**:",
        "☑️ Improved 'Add Rules' window logic",
        "Better handing of deleted/invalid rules.",
    ])
}

/// A body written as Markdown TABLES is not prose and must not be converted.
/// Headlamp's v0.45.0 notes are 142 table rows; line-by-line they render as
/// bullets reading `|:--|--:|` and `| <img src="…">`, next to download links for
/// other platforms — strictly worse than the fallback, which shows the body whole.
@Test func tableShapedBodyIsLeftToTheFallback() {
    let body = """
    Headlamp 0.45.0 reduces desktop startup memory.

    ## ⚡ Performance
    | <img src="https://example.com/icon.png" width="800"> |
    |:--|--:|
    | Plugin i18n now fetches only the active locale's translation file. |
    | Desktop startup now defers optional work. |
    """
    #expect(GitHubMarkdownParser.parse(body: body, version: "0.45.0", date: nil) == nil)
}

/// And a body with many prose lines is treated as structure this pass is
/// misreading, not as a long list of changes — abandoned, not truncated.
@Test func tooManyProseLinesIsAbandonedRatherThanTruncated() {
    let body = (1...20).map { "Some sentence number \($0) about the release." }
        .joined(separator: "\n")
    #expect(GitHubMarkdownParser.parse(body: body, version: "1.0", date: nil) == nil)
}

/// The pass runs ONLY when both bullet passes come up empty, so a body that
/// already parsed is untouched — markers stripped, `by @user in <url>` removed,
/// the contributors section skipped.
@Test func prosePassNeverPreemptsAWorkingBulletBody() throws {
    let body = """
    ## What's Changed
    * Fix the sidebar flicker by @alice in https://github.com/o/r/pull/1
    * Improve startup time by @bob in https://github.com/o/r/pull/2

    ## New Contributors
    * @carol made their first contribution
    """
    let items = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0", date: nil)?.entries.first?.items)
    #expect(items == ["Fix the sidebar flicker", "Improve startup time"])
}
