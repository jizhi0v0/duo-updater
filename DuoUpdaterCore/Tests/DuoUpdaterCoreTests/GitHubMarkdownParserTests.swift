import Foundation
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

// MARK: - Dangling headings (`/code-review` on #562, PR review of #554)
//
// Measured live (30 releases each, the 10 repos this parser serves — a heading
// counts as dangling when the next block is another heading or there is none):
// 161 of 742 styled headings, 22%, would render this way without the fix below
// (`Windscribe 58/136, AnythingLLM 46/105, UTM 30/116, Zed 18/167,
// BetterDisplay 9/42, CotEditor/Rockxy/Yaak/cline 0`).

/// The reported reproduction: a heading whose only item dies on the
/// 6-character floor ("None" is 4 characters) must not style anyway just
/// because it was seen — a heading earns its block only once a note actually
/// lands under it.
///
/// Mutation this catches: appending a heading to `content` the instant it is
/// seen (reverting the `pendingHeading` buffer in `extractItems`) — `Fixed`
/// would render with nothing under it, directly above `Improvements`.
@Test func aHeadingWhoseOnlyLineFailsTheLengthFloorIsNotStyled() throws {
    let body = """
    ## Fixed
    - None
    ## Improvements
    - Made the scrolling much smoother in long lists
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0", date: nil)?.entries.first)
    #expect(entry.content == [
        .heading("Improvements"),
        .note("Made the scrolling much smoother in long lists"),
    ])
}

/// A body ending in a bare heading with nothing after it at all — the other
/// trigger, at the tail rather than mid-body.
///
/// Mutation this catches: same as above, but exercised at end-of-input, where
/// there is no following heading to trigger the "drop the pending one" branch
/// — only the fact that the loop ends with `pendingHeading` still set and
/// nothing ever flushes it.
@Test func aTrailingHeadingWithNoNoteAfterItIsNotStyled() throws {
    let body = """
    ## Added
    - A real change

    ## Known Issues
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0", date: nil)?.entries.first)
    #expect(entry.content == [.heading("Added"), .note("A real change")])
}

/// The same two triggers through the lenient pass, which has its own copy of
/// the buffer.
@Test func danglingHeadingsAreDroppedThroughTheLenientPassToo() throws {
    let body = """
    ## New Stuff
    ## Bug Fixes
     - reject version strings with disallowed characters
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0", date: nil)?.entries.first)
    #expect(entry.content == [
        .heading("Bug Fixes"), .note("reject version strings with disallowed characters"),
    ])
}

/// …and through the prose pass, which has its own copy too.
@Test func danglingHeadingsAreDroppedThroughTheProsePassToo() throws {
    let body = """
    ## Highlights
    ## Notes
    Nothing else changed in this release.
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0", date: nil)?.entries.first)
    #expect(entry.content == [
        .heading("Notes"), .note("Nothing else changed in this release."),
    ])
}

// MARK: - Headings inside a fenced code block (`/code-review` on #562)

/// The strict pass's own loop never tracks fences (its toggle is gated on
/// `lenient`), but `qualifyingHeadings` must track them anyway — a heading
/// whose only appearance is inside a fence must never earn a `.heading` block,
/// even though the strict pass's loop still walks into the fence's contents
/// and still sees those lines as heading-shaped.
///
/// The fenced heading is followed by what LOOKS like a bullet — deliberately,
/// so this cannot pass merely because the dangling-heading fix above already
/// drops a heading with nothing under it. `Added` here DOES get a "note"
/// right after it (the strict pass's own loop never tracks fences, so it
/// reads that line as a real bullet regardless of this fix); the only thing
/// this test isolates is whether `Added` itself gets promoted to a `.heading`
/// block for it.
///
/// Mutation this catches: passing `tracksCodeFences: false` (or an
/// equivalent) into the strict pass's call to `qualifyingHeadings` — `Added`
/// would then count toward the sibling threshold and render as a `.heading`
/// block despite living only inside the fence.
@Test func headingsInsideAFencedCodeBlockAreNeverStyled() throws {
    let body = """
    ## Improvements
    - A real change here

    ```
    ## Added
    - Example config, not a real change
    ```

    ## Notes
    - Another real change here
    """
    let entry = try #require(GitHubMarkdownParser.parse(
        body: body, version: "1.0", date: nil)?.entries.first)
    #expect(entry.content == [
        .heading("Improvements"), .note("A real change here"),
        .note("Example config, not a real change"),
        .heading("Notes"), .note("Another real change here"),
    ])
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

@Test func strictKeepsANestedBulletRightAfterItsParent() {
    // Top-level bullets with an indented one nested under the first: the strict
    // pass reads the nested bullet as an item of its own, in document order.
    let body = """
    - Top level change number one
      - indented sub detail of it
    - Top level change number two
    """
    let cl = GitHubMarkdownParser.parse(body: body, version: "1.0.0", date: nil)
    #expect(cl?.entries.first?.items == [
        "Top level change number one", "indented sub detail of it", "Top level change number two",
    ])
}

@Test func strictNestsOnlyInsideATopLevelList() {
    // An indented bullet after a heading, after unindented prose, or inside a
    // fence is not nested under any item, and the strict pass still drops it.
    let body = """
    - Top level change number one
    A paragraph that closes the list.
      - indented after prose
    - Top level change number two
      ```
      - inside a fence
      ```
    ## Heading
      - indented after a heading
    - Top level change number three
    """
    let cl = GitHubMarkdownParser.parse(body: body, version: "1.0.0", date: nil)
    #expect(cl?.entries.first?.items == [
        "Top level change number one", "Top level change number two", "Top level change number three",
    ])
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

/// A heading line inside a fenced code block must not clear a heading that is
/// still waiting for its first note.
///
/// The strict bullet pass deliberately does not track fences — it has always read
/// a fenced bullet as an item — so a `##` line inside a fence reaches the heading
/// branch. `qualifyingHeadings` DOES skip fenced lines, so such a heading can
/// never be styled; before the guard, its only effect was to discard a real
/// pending heading, and the entry rendered with one group labelled and an
/// identical group above it bare.
///
/// Mutation: drop the `if !inFencedBlock` guard around the `pendingHeading`
/// reassignment in `extractItems`. `Improvements` then disappears from `content`
/// while `Notes` survives, and this fails.
@Test func aFencedHeadingDoesNotDiscardThePendingRealHeading() {
    let body = """
    ## Improvements
    ```
    ## Added
    ```
    - Made the scrolling much smoother in long lists
    ## Notes
    - Another real change line here for length
    """
    let entry = GitHubMarkdownParser.parse(body: body, version: "1.0", date: nil)?.entries.first
    var headings: [String] = []
    for block in entry?.content ?? [] {
        if case let .heading(text) = block { headings.append(text) }
    }
    #expect(headings == ["Improvements", "Notes"])
}

/// The companion guard: turning fence tracking on for the strict pass must not
/// change which lines become items. `inCodeBlock` stays lenient-only and only the
/// new `inFencedBlock` is tracked in both, so a fenced bullet is still an item in
/// the strict pass and a fenced `## New Contributors` still opens a skipped
/// section there — both exactly as before.
///
/// Mutation: gate the strict pass's item extraction on `inFencedBlock` too (i.e.
/// make the fence skip items as well). The fenced bullet vanishes from `items`
/// and this fails.
@Test func fenceTrackingForHeadingsLeavesItemExtractionAlone() {
    let body = """
    ## Improvements
    ```
    - A fenced bullet the strict pass has always read as an item
    ```
    - Made the scrolling much smoother in long lists
    ## Notes
    - Another real change line here for length
    """
    let entry = GitHubMarkdownParser.parse(body: body, version: "1.0", date: nil)?.entries.first
    #expect(entry?.items.count == 3)
    #expect(entry?.items.first == "A fenced bullet the strict pass has always read as an item")
}

// MARK: - Real release bodies through the production decode path

/// One release as `api.github.com/repos/<owner>/<repo>/releases` returns it, so
/// a fixture goes through the production decode path
/// (`StructuredChangelogDecoder.decode(_:format: .gitHubReleases, …)`) rather
/// than the parser alone. `body` is the verbatim text with `\n`; the real
/// responses use CRLF, so it is converted back before encoding.
private func releasesJSON(tag: String, publishedAt: String, body: String) throws -> String {
    let release: [String: Any] = [
        "tag_name": tag, "prerelease": false, "draft": false,
        "published_at": publishedAt,
        "body": body.replacingOccurrences(of: "\n", with: "\r\n"),
    ]
    let data = try JSONSerialization.data(withJSONObject: [release])
    return try #require(String(data: data, encoding: .utf8))
}

/// HandBrake 1.11.2's release body, verbatim (`HandBrake/HandBrake`, fetched
/// 2026-10-08). Its library bumps are nested under one `- Updated libraries`
/// line, and the strict pass used to drop every indented bullet that did not
/// sit under a `**scope**:` label — the pane said "Updated libraries" and
/// nothing about which. Across HandBrake's last ten releases that was 77 lines.
///
/// A nested item comes out as an item of its own, right after its parent, in
/// both `items` and `content`.
///
/// Mutation: drop indented bullets again whenever there is no `**scope**:`
/// label above them. The two library lines vanish and this fails.
@Test func handBrakeNestedLibraryBumpsAreItemsAfterTheirParent() throws {
    let body = """
    ## Upgrade Notice

    Before updating HandBrake, please make sure there are no pending encodes in the queue, and be sure to make a backup of any custom presets and app preferences you have, as they may not be compatible with newer versions.

    Windows users, please make sure to install [Microsoft .NET Desktop Runtime version 10.0](https://dotnet.microsoft.com/en-us/download/dotnet/10.0/runtime)
    Download available from Microsoft:
    - [For x64 (AMD or Intel CPUs)](https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe)
    - [For Arm64 (Qualcomm or other)](https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-arm64.exe)


    ## HandBrake 1.11.2

    ### All platforms

    #### Video

    - Fixed a crash that happened when doing a 2-pass lossless x265 encode
    - Fixed a memory leak that happened when doing a 2-pass MPEG-4/MPEG-2/VP9/FFV1 encode

    #### Audio

    - Updated the list of supported dithers and encoders combinations
    - Fixed the Core Audio AAC encoder 7.1 channel layout

    #### Subtitles

    - Fixed the VobSub palette creation in the MP4 container

    #### Build system

    - Improved build system compatibility with older build tools

    #### Third-party libraries

    - Updated libraries
      - FFmpeg 8.0.2 (decoding and filters)
      - SVT-AV1 4.1.0 (AV1 video encoding)

    ### Linux

    - Added WebM MIME type to the list of the supported formats

    ### Mac

    - Improved handling of unsupported presets
    - Updated Sparkle automatic update library

    ### Windows

    - Improved handling of unsupported presets
    - Improved queue low space pause behaviour
    - Fixed the automatic audio track name generation
    - Fixed the summary description of HDR video
    """
    let json = try releasesJSON(tag: "1.11.2", publishedAt: "2026-06-07T19:08:25Z", body: body)
    let entry = try #require(StructuredChangelogDecoder.decode(
        json, format: .gitHubReleases, channel: nil, maxEntries: nil)?.entries.first)

    let parent = try #require(entry.items.firstIndex(of: "Updated libraries"))
    #expect(Array(entry.items[parent...].prefix(4)) == [
        "Updated libraries",
        "FFmpeg 8.0.2 (decoding and filters)",
        "SVT-AV1 4.1.0 (AV1 video encoding)",
        "Added WebM MIME type to the list of the supported formats",
    ])
    #expect(entry.items.count == 18)

    let notes = entry.content.compactMap { block -> String? in
        if case let .note(text) = block { return text }; return nil
    }
    #expect(notes == entry.items, "content must carry the nested items in the same order")
    let note = try #require(entry.content.firstIndex(of: .note("Updated libraries")))
    #expect(Array(entry.content[note...].prefix(4)) == [
        .note("Updated libraries"),
        .note("FFmpeg 8.0.2 (decoding and filters)"),
        .note("SVT-AV1 4.1.0 (AV1 video encoding)"),
        .heading("Linux"),
    ])
}

// MARK: - Another release's notes repeated in the body (Keka)

/// Keka 1.6.7's release body, verbatim (`aonez/Keka`, fetched 2026-10-08). A
/// hot-fix release that repeats the previous release's notes under
/// `# Changes in version 1.6.6`. Those notes are 1.6.6's own entry in the same
/// list, and Keka's site lists one change for 1.6.7; read as 1.6.7's they made
/// it nine items, with a second "Fixes" heading.
///
/// Mutation: stop dropping the section (return the body unchanged from the
/// function that removes it). 1.6.7 is nine items again and this fails.
@Test func kekaHotFixDropsTheRepeatedPreviousRelease() throws {
    let body = """
    👉 Do not miss [Keka for iOS](https://ios.keka.io) 🤩🤩🤩
    👉 Follow us on [Mastodon](https://techhub.social/@keka) and [X](https://x.com/kekaosx) to get all the Keka news

    This is a hot-fix release.

    ## Fixes
    - Reverted BSDTAR from 3.8.8 to 3.8.7 due to issues on macOS 26.5.2 (Thanks to @suishouen) #1762

    # Changes in version 1.6.6

    ## Fixes
    - Enhanced ISO detection and extraction (Thanks to @frvctal) [#1756](https://github.com/aonez/Keka/issues/1756)

    ## Formats
    - Updated 7ZZ from 26.01 to 26.02 (Thanks to Igor Pavlov)
    - Updated BSDTAR from 3.8.7 to 3.8.8 (Thanks to Tim Kientzle and authors)
    - Updated LZIP from 1.25 to 1.26 (Thanks to Antonio Diaz Diaz)
    - Updated PLZIP from 1.12 to 1.13 (Thanks to Antonio Diaz Diaz)
    - Updated XZ from 5.8.1 to 5.8.3 (Thanks to Lasse Collin)
    - Stripped P7ZIP ARM support, only used as fallback on 10.13 or older (Intel)

    ## Translations
    - Japanese translation updated (Thanks to @SakiPapa) [#1753](https://github.com/aonez/Keka/issues/1753) [#1761](https://github.com/aonez/Keka/issues/1761)
    """
    let json = try releasesJSON(tag: "v1.6.7", publishedAt: "2026-06-30T12:42:14Z", body: body)
    let entry = try #require(StructuredChangelogDecoder.decode(
        json, format: .gitHubReleases, channel: nil, maxEntries: nil)?.entries.first)
    #expect(entry.version == "1.6.7")
    #expect(entry.items == [
        "Reverted BSDTAR from 3.8.8 to 3.8.7 due to issues on macOS 26.5.2 (Thanks to @suishouen) #1762",
    ])
    #expect(entry.content.isEmpty)
}

/// What the rule must NOT drop. A heading that names this release's own version,
/// a newer one, or one that cannot be compared is this release's notes; so is
/// any other heading that mentions a version — only the "changes in version X"
/// shape announces another release's notes.
@Test func onlyAnOlderVersionsChangesHeadingIsDropped() throws {
    func items(_ body: String, version: String) -> [String] {
        GitHubMarkdownParser.parse(body: body, version: version, date: nil)?.entries.first?.items ?? []
    }
    let ownVersion = """
    # Changes in version 1.6.7
    - Reverted the archiver to the previous release
    """
    #expect(items(ownVersion, version: "1.6.7") == ["Reverted the archiver to the previous release"])
    // A build that is not a version (Diri's `nightly` tag) is not judged.
    #expect(items(ownVersion, version: "nightly") == ["Reverted the archiver to the previous release"])
    // A dev build lists the release it leads up to.
    #expect(items(ownVersion, version: "1.6.6") == ["Reverted the archiver to the previous release"])

    let otherShapes = """
    ## What's new in 2.0
    - Brand new interface for everything
    ## Changes since 1.5.0
    - Faster launch on every Mac
    ## macOS 14 support
    - Runs on Sonoma now as well
    """
    #expect(items(otherShapes, version: "2.1") == [
        "Brand new interface for everything", "Faster launch on every Mac", "Runs on Sonoma now as well",
    ])

    // The section ends at the next heading of its own level or higher.
    let resumes = """
    ## Fixes
    - Fixed the one thing in this release
    # Changes in version 1.6.6
    ## Fixes
    - Fixed something back in the last release
    # Downloads
    - Universal build for every Mac here
    """
    #expect(items(resumes, version: "1.6.7") == [
        "Fixed the one thing in this release", "Universal build for every Mac here",
    ])
}
