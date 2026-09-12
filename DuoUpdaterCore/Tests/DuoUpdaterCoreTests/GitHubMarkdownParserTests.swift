import Testing
@testable import DuoUpdaterCore

// MARK: - Category headings (#554, part of #399)
//
// Measured 2026-09-12 across the 10 repos already routed through
// `GitHubMarkdownParser` (30 releases each, `gh api repos/<owner>/<repo>/releases`):
// real category headings (`Added`/`Fixed`/`Improvements`/…) never carry a digit,
// while every version-restating heading found (UTM's `Changes (v5.0.4)`,
// Rockxy's `Rockxy 0.38.3 (build 58)`, AnythingLLM's `AnythingLLM v1.8.0 | …`,
// CotEditor's `Changes in 7.0.8 (unreleased)`) does — see
// `Changelog.parserGeneration`'s generation-3 entry and
// `GitHubMarkdownParser.isVersionLikeHeading`'s doc comment.

/// Two real categories: both style as `.heading` blocks, in document order,
/// interleaved with the notes they introduce — and `items` stays exactly the
/// flat list it always was (a heading is never one of its lines).
///
/// Mutations this catches: appending heading text into `items` (breaks the
/// `items`-doesn't-change assertion); building `content` as "all headings then
/// all notes" instead of interleaved (breaks the ordering assertion).
@Test func twoOrMoreCategoryHeadingsStyleAsHeadingBlocksInDocumentOrder() throws {
    let body = """
    ## Added
    - New feature one
    - New feature two

    ## Fixed
    - Fixed bug one
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0.0", date: nil)?.entries.first)
    #expect(entry.items == ["New feature one", "New feature two", "Fixed bug one"])
    #expect(entry.content == [
        .heading("Added"), .note("New feature one"), .note("New feature two"),
        .heading("Fixed"), .note("Fixed bug one"),
    ])
    #expect(!entry.items.contains("Added"), "a heading leaked into items")
    #expect(!entry.items.contains("Fixed"), "a heading leaked into items")
}

/// A single heading — Shotbase's real shape, "one heading restating the pane"
/// (`### What's new` on every release) — never earns a `.heading` block: below
/// the ≥2-sibling threshold it folds away exactly as it always did, invisible,
/// not even as a plain item.
///
/// Mutation this catches: dropping (or inverting) the `candidates.count >= 2`
/// threshold in `qualifyingHeadings` — a lone heading would start rendering.
@Test func aLoneHeadingStaysFoldedAwayBelowTheSiblingThreshold() throws {
    let body = """
    ## What's new
    - Something changed
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0.0", date: nil)?.entries.first)
    #expect(entry.items == ["Something changed"])
    #expect(entry.content.isEmpty, "a lone heading must not produce a .heading block")
}

/// UTM's real shape: `Highlights`/`Notes` are genuine sections, but the body
/// also nests OTHER releases' notes under `Changes (vX.Y.Z)` headings — styling
/// those would draw four version numbers next to the one the rail already
/// shows. Only the non-version headings qualify; the version-shaped ones fold
/// away, and their bullets still surface as plain (unheaded) items exactly as
/// before this change — nothing about `items` regresses for this shape.
///
/// Mutation this catches: deleting `isVersionLikeHeading` from
/// `qualifyingHeadings` (or always returning `false`) — the version headings
/// would join `Highlights`/`Notes` as styled blocks.
@Test func versionRestatingHeadingsDoNotQualifyEvenWithEnoughSiblings() throws {
    let body = """
    ## Highlights
    - Big new feature

    ## Notes
    - Some notes

    ## Changes (v5.0.4)
    - Old changes from a previous release

    ## Changes (v5.0.3)
    - Even older changes
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "5.0.5", date: nil)?.entries.first)
    #expect(entry.items == [
        "Big new feature", "Some notes",
        "Old changes from a previous release", "Even older changes",
    ], "the version-shaped headings' bullets must still come through as plain items")
    #expect(entry.content == [
        .heading("Highlights"), .note("Big new feature"),
        .heading("Notes"), .note("Some notes"),
        .note("Old changes from a previous release"),
        .note("Even older changes"),
    ])
}

/// Even with three siblings, an ALL-version-shaped set of headings never
/// qualifies — proving the digit filter is load-bearing on its own, not merely
/// riding along with the ≥2 threshold (which three headings would otherwise
/// clear easily).
@Test func allVersionShapedHeadingsNeverQualifyRegardlessOfCount() throws {
    let body = """
    ## Changes (v5.0.4)
    - A change

    ## Changes (v5.0.3)
    - Another change

    ## Changes (v5.0.2)
    - Yet another change
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "5.0.5", date: nil)?.entries.first)
    #expect(entry.content.isEmpty)
}

/// A recipe-declared `skipSections` heading must not count toward the ≥2
/// threshold for its SIBLINGS either — otherwise adding a `skipSections` entry
/// for a boilerplate section would, as a side effect, start styling the one
/// real heading left behind (1 real + 1 boilerplate reads as "2 siblings" if
/// the boilerplate one isn't excluded from the count first).
///
/// Mutation this catches: computing the sibling count from ALL headings before
/// filtering out `skipSections` matches, instead of after.
@Test func aSkippedHeadingDoesNotCountTowardTheSiblingThreshold() throws {
    let body = """
    ## Added
    - Real change

    ## Roster
    - Alice
    - Bob
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0.0", date: nil, skipSections: ["Roster"])?.entries.first)
    #expect(entry.items == ["Real change"], "the skipped section's bullets must still be dropped")
    #expect(entry.content.isEmpty,
            "one real heading left after excluding the skipped one is still below the threshold")
}

/// The lenient pass (indented bullets, strict pass finds nothing) wires up
/// headings exactly the same way the strict pass does.
@Test func headingsStyleThroughTheLenientPassToo() throws {
    let body = """
    ## New Stuff
     - install from cache without network access
    ## Bug Fixes
     - reject version strings with disallowed characters
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "0.40.5", date: nil)?.entries.first)
    #expect(entry.content == [
        .heading("New Stuff"), .note("install from cache without network access"),
        .heading("Bug Fixes"), .note("reject version strings with disallowed characters"),
    ])
}

/// …and so does the prose pass (both bullet passes come up empty).
@Test func headingsStyleThroughTheProsePassToo() throws {
    let body = """
    ## Highlights
    A faster startup on every platform.

    ## Notes
    Nothing else changed in this release.
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0", date: nil)?.entries.first)
    #expect(entry.content == [
        .heading("Highlights"), .note("A faster startup on every platform."),
        .heading("Notes"), .note("Nothing else changed in this release."),
    ])
}

/// Backward compatibility: the existing "What's Changed" + "New Contributors"
/// shape has exactly one non-boilerplate heading ("What's Changed" — "New
/// Contributors" is `skippedSectionKeywords` boilerplate, excluded from the
/// count same as `skipSections`), so it stays below the ≥2 threshold and
/// `content` stays empty exactly as it did before this change.
@Test func theExistingWhatsChangedShapeStaysUnstyled() {
    let body = """
    ## What's Changed
    - Fix the broken thing by @bob in https://github.com/o/r/pull/1
    - Add a useful feature (#42)
    ## New Contributors
    - @newbie made their first contribution
    """
    let cl = GitHubMarkdownParser.parse(body: body, version: "1.0.0", date: nil)
    #expect(cl?.entries.first?.content.isEmpty == true)
}

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
