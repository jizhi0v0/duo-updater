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
