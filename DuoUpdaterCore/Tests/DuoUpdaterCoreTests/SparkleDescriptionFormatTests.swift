import Testing
import Foundation
@testable import DuoUpdaterCore

// Sparkle has TWO official ways to inline Markdown release notes, and we only
// read one of them. `<sparkle:markdownDescription>` (Surge's shape) was handled;
// `<description sparkle:format="markdown">` — added in Sparkle 2.9, documented at
// https://sparkle-project.org/documentation/publishing/ — was not, because the
// parser never looked at an element's `sparkle:format` attribute at all.
//
// The failure was silent and looked like a vendor problem: the body landed in
// `descriptionHTML`, `AppcastHTMLChangelogParser.isStructured` rejected it for
// having no `<li>` (Markdown bullets are `- `), `structuredChangelog` came back
// nil, and the notes fell through to the raw-text renderer. Measured on
// ShiftBar's live feed (2026-09-20, v0.1.13): 183 chars of notes, isStructured
// false, structured changelog nil.
//
// `plain-text` (Sparkle 2.4) is deliberately NOT routed here — see the field's
// own comment in `SparkleAppcastSource`.

/// ShiftBar's shape: Markdown bullets plus a trailing prose line, no `<li>`
/// anywhere, and no `<sparkle:markdownDescription>` element in the feed.
///
/// Mutation: drop the `currentDescriptionFormat == "markdown"` branch in
/// `didEndElement` — nothing reaches the markdown key, `structuredChangelog`
/// returns nil, and this fails.
@Test func markdownFormattedDescriptionBecomesNativeEntries() {
    let items = SparkleAppcastParser.parse(Data(markdownFormatFeed.utf8),
                                           preferredLanguages: ["en-US"])
    #expect(items.first?.markdownDescription != nil)

    let changelog = SparkleAppcastSource.structuredChangelog(from: items)
    #expect(changelog?.entries.count == 1)
    let entry = changelog?.entries.first
    #expect(entry?.version == "0.1.13")
    // Three bullets and the trailing prose line, in document order — the prose
    // is kept rather than dropped, which is why this parser exists instead of a
    // bullets-only one.
    #expect(entry?.items == [
        "Keeps the hidden state across desktop switches.",
        "Command-drag reordering then a capsule click completes cleanly.",
        "Sharper authorization card artwork.",
        "Requires macOS 27 on Apple silicon.",
    ])
}

/// The raw body stays in `descriptionHTML` too. That field becomes
/// `RemoteVersion.releaseNotesHTML`, which the detail window falls back to when
/// nothing structured parsed — routing the body instead of copying it would
/// trade that fallback away.
///
/// Mutation: change the new `recordLocalized` call into a move (skip recording
/// `description`) — this fails.
@Test func markdownFormattedDescriptionKeepsTheRawBodyAsFallback() {
    let items = SparkleAppcastParser.parse(Data(markdownFormatFeed.utf8),
                                           preferredLanguages: ["en-US"])
    #expect(items.first?.descriptionHTML?.contains("- Sharper authorization") == true)
}

/// `plain-text` means "these characters, literally". Routing it to the Markdown
/// parser would strip `**` and eat the `- `, so it keeps the existing path.
///
/// Mutation: relax the comparison to `!= nil` (accept any format) — this fails.
@Test func plainTextFormattedDescriptionIsNotTreatedAsMarkdown() {
    let items = SparkleAppcastParser.parse(Data(plainTextFormatFeed.utf8),
                                           preferredLanguages: ["en-US"])
    #expect(items.first?.markdownDescription == nil)
    #expect(items.first?.descriptionHTML?.contains("**not bold**") == true)
}

/// The overwhelming majority of feeds: a `<description>` with no `format` at all
/// is HTML and must reach neither the markdown key nor a changed `descriptionHTML`.
///
/// Mutation: default `currentDescriptionFormat` to `"markdown"` instead of nil —
/// this fails.
@Test func unformattedDescriptionIsUntouched() {
    let items = SparkleAppcastParser.parse(Data(htmlFeed.utf8),
                                           preferredLanguages: ["en-US"])
    #expect(items.first?.markdownDescription == nil)
    #expect(items.first?.descriptionHTML == "<ul><li>Fixed a thing</li></ul>")
}

/// The prefix is the feed's to choose — `sparkle:` is a convention, the URI is
/// the contract. Read through the bound prefix exactly as `sparkle:version` on
/// `<enclosure>` already is.
///
/// Mutation: replace the `sparkleAttribute` call with
/// `attributeDict["sparkle:format"]` — this fails.
@Test func formatIsReadThroughWhicheverPrefixIsBoundToSparkle() {
    let items = SparkleAppcastParser.parse(Data(foreignPrefixFeed.utf8),
                                           preferredLanguages: ["en-US"])
    #expect(items.first?.markdownDescription?.contains("- Bound to a different prefix") == true)
}

/// A localized feed must resolve BOTH keys to the same variant. Recording the
/// markdown copy under the reader's own language is what makes that hold; a copy
/// recorded with no language would read as `en` and cross the two keys.
///
/// Mutation: pass a literal nil language by calling
/// `localizedChildren["markdownDescription", default: []].append((nil, text))`
/// instead of `recordLocalized` — the zh reader gets the English notes structured
/// while the raw body is Chinese, and this fails.
@Test func localizedMarkdownDescriptionsFollowTheReader() {
    let items = SparkleAppcastParser.parse(Data(localizedMarkdownFeed.utf8),
                                           preferredLanguages: ["zh-Hans-CN", "en-US"])
    #expect(items.first?.markdownDescription?.contains("修复") == true)
    #expect(items.first?.descriptionHTML?.contains("修复") == true)
}

/// The format does not carry from one item to the next. What makes that hold is
/// that `didStartElement` assigns `currentDescriptionFormat` UNCONDITIONALLY when
/// a `<description>` opens — to nil when the element names no `format` — so the
/// second item's plain `<description>` clears what the first one set. There is no
/// separate reset beside `currentLanguage`'s, and adding one would be dead code.
///
/// The flag is therefore only meaningful when read at `</description>`, which is
/// its one reader. Between two `<description>` elements it holds the previous
/// one's value rather than nil, so a future end-tag handler must not read it.
///
/// Mutation: make that assignment conditional —
/// `if let f = sparkleAttribute("format", attributeDict, sortedAttributeKeys) {
/// currentDescriptionFormat = f.lowercased() }` — the second item inherits
/// `markdown` and this fails.
@Test func formatDoesNotLeakIntoTheNextItem() {
    let items = SparkleAppcastParser.parse(Data(twoItemMixedFormatFeed.utf8),
                                           preferredLanguages: ["en-US"])
    #expect(items.count == 2)
    #expect(items.first?.markdownDescription != nil)
    #expect(items.last?.markdownDescription == nil)
}

// MARK: - Feeds

/// ShiftBar's live shape, notes translated to keep the fixture readable.
private let markdownFormatFeed = """
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Example</title>
    <item>
      <title>0.1.13</title>
      <pubDate>Sun, 20 Sep 2026 08:00:36 +0000</pubDate>
      <sparkle:version>14</sparkle:version>
      <sparkle:shortVersionString>0.1.13</sparkle:shortVersionString>
      <description sparkle:format="markdown"><![CDATA[- Keeps the hidden state across desktop switches.
- Command-drag reordering then a capsule click completes cleanly.
- Sharper authorization card artwork.

Requires macOS 27 on Apple silicon.
]]></description>
      <enclosure url="https://example.com/App-0.1.13.dmg" length="3465095" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""

private let plainTextFormatFeed = """
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
      <description sparkle:format="plain-text"><![CDATA[- literal dash, **not bold**]]></description>
      <enclosure url="https://example.com/App-2.0.dmg"/>
    </item>
  </channel>
</rss>
"""

private let htmlFeed = """
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <sparkle:shortVersionString>3.0</sparkle:shortVersionString>
      <description><![CDATA[<ul><li>Fixed a thing</li></ul>]]></description>
      <enclosure url="https://example.com/App-3.0.dmg"/>
    </item>
  </channel>
</rss>
"""

/// Same URI, different prefix — and a decoy `sparkle:` prefix bound to nothing
/// relevant is not needed to make the point; the absence of the literal spelling
/// is what the assertion turns on.
private let foreignPrefixFeed = """
<?xml version="1.0" standalone="yes"?>
<rss xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <s:shortVersionString>4.0</s:shortVersionString>
      <description s:format="markdown"><![CDATA[- Bound to a different prefix]]></description>
      <enclosure url="https://example.com/App-4.0.dmg"/>
    </item>
  </channel>
</rss>
"""

private let localizedMarkdownFeed = """
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <sparkle:shortVersionString>5.0</sparkle:shortVersionString>
      <description xml:lang="en" sparkle:format="markdown"><![CDATA[- Fixed a thing]]></description>
      <description xml:lang="zh-Hans" sparkle:format="markdown"><![CDATA[- 修复了一个问题]]></description>
      <enclosure url="https://example.com/App-5.0.dmg"/>
    </item>
  </channel>
</rss>
"""

private let twoItemMixedFormatFeed = """
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <sparkle:shortVersionString>6.1</sparkle:shortVersionString>
      <description sparkle:format="markdown"><![CDATA[- Markdown notes]]></description>
      <enclosure url="https://example.com/App-6.1.dmg"/>
    </item>
    <item>
      <sparkle:shortVersionString>6.0</sparkle:shortVersionString>
      <description><![CDATA[<p>HTML notes</p>]]></description>
      <enclosure url="https://example.com/App-6.0.dmg"/>
    </item>
  </channel>
</rss>
"""
