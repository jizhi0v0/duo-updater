import Testing
import Foundation
@testable import DuoUpdaterCore

// Sparkle's inline Markdown notes are rendered as written (`Changelog.Entry.markdown`
// → `ChangelogMarkdown.blocks`) after the noise is taken out
// (`AppcastMarkdownParser.renderableMarkdown`). These pin both halves.

// MARK: - What is taken out

/// Mutation: drop the `**<keyword>` prefix check in `renderableMarkdown` — the
/// Full Changelog line survives and this fails.
@Test func fullChangelogLineIsTakenOut() throws {
    let md = """
    ## 🧰 Maintenance

    - Postpone the Raptor Product Hunt dialogs (#2905) by @tpae

    **Full Changelog**: https://github.com/osaurus-ai/osaurus/compare/0.25.13...0.25.14
    """
    let out = try #require(AppcastMarkdownParser.renderableMarkdown(from: md, version: "0.25.14"))
    #expect(!out.contains("Full Changelog"))
    #expect(out.contains("- Postpone the Raptor Product Hunt dialogs"))
}

/// A boilerplate section goes as a whole, heading and body, up to the next heading.
///
/// Mutation: stop setting `inSkippedSection` — the contributor line survives.
@Test func boilerplateSectionIsTakenOutUpToTheNextHeading() throws {
    let md = """
    ## What's Changed
    - Fix a crash
    ## New Contributors
    - @someone made their first contribution in #12
    ## Fixed
    - Another fix
    """
    let out = try #require(AppcastMarkdownParser.renderableMarkdown(from: md, version: "1.0"))
    #expect(!out.contains("New Contributors"))
    #expect(!out.contains("first contribution"))
    #expect(out.contains("## Fixed\n- Another fix"))
}

/// TablePro opens every body with a title restating the version the rail shows.
/// A heading that merely contains a longer number is not that title.
///
/// Mutation: match with a plain `heading.contains(version)` — `macOS 26.0` is
/// taken for version `6.0`, and the second half fails.
@Test func versionRestatingTitleIsTakenOutButNotALongerNumber() throws {
    let tablePro = """
    # What's New in TablePro 0.76.1
    ### Changed
    - Read-only CQL editor results on Cassandra and ScyllaDB.
    """
    let out = try #require(AppcastMarkdownParser.renderableMarkdown(from: tablePro, version: "0.76.1"))
    #expect(!out.contains("What's New in TablePro"))
    #expect(out.hasPrefix("### Changed"))

    let other = """
    ### Changes for macOS 26.0
    - Adapted the menu bar icon.
    ### In 6.0.1
    - Fixed a crash.
    """
    let kept = try #require(AppcastMarkdownParser.renderableMarkdown(from: other, version: "6.0"))
    #expect(kept.contains("### Changes for macOS 26.0"))
    #expect(kept.contains("### In 6.0.1"))
}

/// Code is shown as the vendor wrote it: a line inside a fence is never judged.
@Test func fencedCodeIsLeftAlone() throws {
    let md = """
    ### Configuration
    ```
    **Full Changelog**: not a real one, just config text
    ```
    """
    let out = try #require(AppcastMarkdownParser.renderableMarkdown(from: md, version: "1.0"))
    #expect(out.contains("**Full Changelog**: not a real one"))
}

// MARK: - Block structure

@Test func blocksCarryHeadingsListsNestingAndCode() {
    let md = """
    ### Improvements

    - Top-level item with **bold**
      - Nested item

      A second paragraph of the top-level item.
    1. First
    2. Second

    ```
    Proxy = http, example.com, 8080
    ```
    """
    let blocks = ChangelogMarkdown.blocks(from: md)
    let kinds = blocks.map(\.kind)
    let texts = blocks.map { String($0.text.characters) }

    #expect(kinds == [
        .heading(level: 3),
        .listItem(depth: 1, marker: "•"),
        .listItem(depth: 2, marker: "•"),
        .listItem(depth: 1, marker: nil),
        .listItem(depth: 1, marker: "1."),
        .listItem(depth: 1, marker: "2."),
        .code,
    ])
    #expect(texts == [
        "Improvements",
        "Top-level item with bold",
        "Nested item",
        "A second paragraph of the top-level item.",
        "First",
        "Second",
        "Proxy = http, example.com, 8080",
    ])
    // Emphasis stays on the text for `Text` to draw, rather than as literal `**`.
    #expect(blocks[1].text.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
}

// MARK: - End to end

/// Surge's beta 6.10.0 has a single `### Improvements`. In `items` it is one
/// more line; rendered as Markdown it is the heading the vendor wrote.
///
/// Mutation: stop passing `markdown:` in `AppcastMarkdownParser.entry` —
/// `entry.markdown` is nil and this fails.
@Test func singleHeadingReleaseRendersItsHeading() throws {
    let md = """
    ### Improvements
    - A category parameter has been added to policy groups for grouped display.
    - Optimized Tailscale and WireGuard behavior when switching networks.
    """
    let entry = try #require(AppcastMarkdownParser.entry(from: md, version: "6.10.0", date: nil))
    #expect(entry.content.isEmpty)
    let blocks = ChangelogMarkdown.blocks(from: try #require(entry.markdown))
    #expect(blocks.first?.kind == .heading(level: 3))
    #expect(blocks.first.map { String($0.text.characters) } == "Improvements")
}

/// The Osaurus shape through the real feed parser: the Markdown the pane renders
/// has its headings and bullets, and not the compare-link line.
@Test func osaurusEntryCarriesRenderableMarkdown() throws {
    let parsed = SparkleAppcastParser.parse(Data(osaurusFeed.utf8))
    let entry = try #require(SparkleAppcastSource.structuredChangelog(from: parsed)?.entries.first)
    let markdown = try #require(entry.markdown)
    #expect(!markdown.contains("Full Changelog"))

    let blocks = ChangelogMarkdown.blocks(from: markdown)
    #expect(blocks.map(\.kind) == [
        .heading(level: 2), .listItem(depth: 1, marker: "•"),
        .heading(level: 2), .listItem(depth: 1, marker: "•"),
    ])
    #expect(blocks.map { String($0.text.characters) } == [
        "What's Changed", "added iOS app integrations (#2875) by @RaajeevChandran",
        "🐛 Bug Fixes", "Fix timing export choices for restored chats (#2902) by @jjang-ai",
    ])
}

/// Trimmed from the live Osaurus appcast (0.25.14, fetched 2026-09-29).
private let osaurusFeed = """
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel>
  <item>
    <title>0.25.14</title>
    <pubDate>Sun, 27 Sep 2026 07:10:28 +0000</pubDate>
    <sparkle:version>0.25.14</sparkle:version>
    <sparkle:shortVersionString>0.25.14</sparkle:shortVersionString>
    <enclosure url="https://github.com/osaurus-ai/osaurus/releases/download/0.25.14/Osaurus-0.25.14.dmg" length="79256834" type="application/octet-stream"/>
    <description sparkle:format="markdown"><![CDATA[
## What's Changed

- added iOS app integrations (#2875) by @RaajeevChandran

## 🐛 Bug Fixes

- Fix timing export choices for restored chats (#2902) by @jjang-ai

**Full Changelog**: https://github.com/osaurus-ai/osaurus/compare/0.25.13...0.25.14
]]></description>
  </item>
</channel>
</rss>
"""
