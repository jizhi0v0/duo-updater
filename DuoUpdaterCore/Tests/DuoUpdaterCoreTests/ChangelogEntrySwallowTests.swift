import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ChangelogExtractor.anEntrySwallowsAnother` — what `duo verify` asks a page
/// that has fallen to one entry, to tell a collapse from a vendor that simply
/// published one post (#821).
@Suite struct ChangelogEntrySwallowTests {

    /// Start and terminator are different tokens, which is the shape a collapse
    /// needs: a restyle that renames only the separator leaves every heading
    /// matching and the `\z` alternative carrying the first body to the end.
    private static let separated = ChangelogRecipe(
        bundleID: "com.example.swallow",
        source: URL(string: "https://example.invalid/changelog")!,
        entryPattern: #"<h2>(?<version>[0-9.]+)</h2>(?<body>.*?)(?=<hr class="sep">|\z)"#,
        itemPatterns: [#"<li>(?<item>[^<]+)</li>"#])

    private static func page(_ versions: [String], separator: String) -> String {
        "<html><body>"
            + versions.map { "<h2>\($0)</h2><ul><li>Fixed a crash in \($0).</li></ul>" }
                .joined(separator: separator)
            + "</body></html>"
    }

    /// Mutation: `return false` at the end of the loop body (or skip the
    /// `firstMatch` search) — the collapse reads as a page that holds one post.
    @Test func aPageWhoseTerminatorStoppedMatchingIsCaught() throws {
        let healthy = Self.page(["3.0", "2.0", "1.0"], separator: #"<hr class="sep">"#)
        #expect(ChangelogExtractor.extract(from: healthy, using: Self.separated)?.entries.count == 3)
        #expect(ChangelogExtractor.anEntrySwallowsAnother(in: healthy, using: Self.separated) == false)

        let restyled = Self.page(["3.0", "2.0", "1.0"], separator: #"<hr class="divider">"#)
        let collapsed = try #require(ChangelogExtractor.extract(from: restyled, using: Self.separated))
        // The collapse as the sweep sees it: one entry, newest version intact.
        #expect(collapsed.entries.count == 1)
        #expect(collapsed.entries.first?.version == "3.0")
        #expect(ChangelogExtractor.anEntrySwallowsAnother(in: restyled, using: Self.separated) == true)
    }

    /// A page holding one release, with a footer after it, swallowed nothing.
    @Test func aPageThatHoldsOneEntryIsNotACollapse() {
        let single = Self.page(["3.0"], separator: "")
            .replacingOccurrences(of: "</body>", with: #"<hr class="sep"><footer>© Example</footer></body>"#)
        #expect(ChangelogExtractor.extract(from: single, using: Self.separated)?.entries.count == 1)
        #expect(ChangelogExtractor.anEntrySwallowsAnother(in: single, using: Self.separated) == false)
    }

    /// Chrome's own recipe on a page with the live page's shape (#821): one
    /// desktop post among other posts, its body closed by its own `</script>`.
    @Test func chromeWithOneDesktopPostIsNotACollapse() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipes(forBundleID: "com.google.Chrome").first)
        let page = ChromeChangelogPatternTests.generatedPage(posts: 1, bodyKB: 4)
            .replacingOccurrences(of: "</body>", with:
                "<h3 class='post-title'><a href='/x.html' title='Chrome for Android Update'>Chrome for Android Update</a></h3>"
                + "<script type='text/template'><p>Android 155.0.8059.40</p></script></body>")
        #expect(ChangelogExtractor.extract(from: page, using: recipe)?.entries.count == 1)
        #expect(ChangelogExtractor.anEntrySwallowsAnother(in: page, using: recipe) == false)
    }

    /// The search starts at the BODY, not one character into the match. Under
    /// `(?m)` a `(?:^|\n)` start re-matches its own heading one character in, and
    /// every single-entry Markdown page would read as swallowing itself.
    ///
    /// Mutation: search from `match.range.location + 1` instead of the body.
    @Test func anEntryIsNotFoundInsideItselfThroughItsOwnHeading() {
        let recipe = ChangelogRecipe(
            bundleID: "com.example.swallow-md",
            source: URL(string: "https://example.invalid/CHANGELOG.md")!,
            entryPattern: #"(?m)(?:^|\n)## (?<version>[0-9.]+)\n(?<body>.*?)(?=\n## |\z)"#,
            itemPatterns: [#"(?m)^- (?<item>[^\n]+)"#])
        let single = "# Changelog\n\n## 3.0.0\n- Fixed a crash.\n- Faster start.\n"
        #expect(ChangelogExtractor.extract(from: single, using: recipe)?.entries.count == 1)
        #expect(ChangelogExtractor.anEntrySwallowsAnother(in: single, using: recipe) == false)
    }

    /// Nil, not false, when there is nothing to judge — so the caller keeps
    /// warning on the count instead of standing the check down.
    @Test func noMatchOrNoBodyGroupIsUnknown() {
        #expect(ChangelogExtractor.anEntrySwallowsAnother(in: "<html></html>", using: Self.separated) == nil)
        let bodiless = ChangelogRecipe(
            bundleID: "com.example.swallow-nobody",
            source: URL(string: "https://example.invalid/")!,
            entryPattern: #"<h2>(?<version>[0-9.]+)</h2>"#,
            itemPatterns: [#"<li>(?<item>[^<]+)</li>"#])
        #expect(ChangelogExtractor.anEntrySwallowsAnother(
            in: Self.page(["3.0"], separator: ""), using: bodiless) == nil)
    }
}
