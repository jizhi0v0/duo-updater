import Testing
import Foundation
@testable import DuoUpdaterCore

// Sparkle lets a vendor repeat an <item> child once per language, tagged with
// `xml:lang`, and picks the one matching the reader. We used to ignore the
// attribute entirely and take a variant by POSITION — first-wins for
// <sparkle:releaseNotesLink>, last-wins for <description> — so the language a
// reader got was whatever the vendor happened to list at that end of the list.
// Issue #399 reported both halves: Mac Mouse Fix's notes came out German for
// everyone, Mole's came out in whichever language its feed listed last.
//
// Every case below states the reader's language preferences explicitly rather
// than letting `Locale.preferredLanguages` supply them. A test that read the
// host's would be asserting something about this Mac, not about the parser, and
// would answer differently on a CI runner set to another language.

/// Two langs on `<description>`, Mole's shape (CDATA bodies, `en` listed first
/// and the reader's language in the middle). Mutation: drop the language
/// selection and take the last non-empty `<description>` as before — the reader
/// gets `pt-BR` and this fails.
@Test func descriptionPicksTheReadersLanguage() {
    let items = SparkleAppcastParser.parse(Data(moleShapedFeed.utf8),
                                           preferredLanguages: ["zh-Hans-CN", "en-US"])
    #expect(items.count == 1)
    #expect(items.first?.descriptionHTML == "<ol><li>软件更新</li></ol>")
}

/// The same feed read by an English Mac: the `en` variant, not the first or last
/// one in the document.
@Test func descriptionFollowsADifferentReaderToADifferentLanguage() {
    let items = SparkleAppcastParser.parse(Data(moleShapedFeed.utf8),
                                           preferredLanguages: ["en-US"])
    #expect(items.first?.descriptionHTML == "<ol><li>Software updates</li></ol>")
}

/// Mac Mouse Fix's shape: the notes are LINKED, one URL per language, and the
/// first one listed is German. Mutation: restore the `releaseNotesLink == nil`
/// first-wins guard — every reader gets `de.html` and this fails.
@Test func releaseNotesLinkPicksTheReadersLanguage() {
    let items = SparkleAppcastParser.parse(
        Data(macMouseFixShapedFeed.utf8),
        relativeTo: URL(string: "https://example.com/appcast.xml")!,
        preferredLanguages: ["zh-Hans-CN", "en-US"])
    #expect(items.first?.releaseNotesLink?.lastPathComponent == "zh-Hans.html")
}

/// What an English reader gets from that same feed, which lists no `en` variant
/// at all: the FIRST one, German.
///
/// This is not a shrug: `Bundle.preferredLocalizations(from:forPreferences:)`
/// answers with the input array's first element when nothing matches, and
/// Sparkle's own `bestNodeInNodes:` rides on the same call — so Mac Mouse Fix
/// reading German to an English Mac is the vendor omitting `en` from its feed
/// (`…/3.0.8/en.html` is published and reachable, just never listed), not us
/// choosing badly. Pinned because the tempting "fix" is to invent a URL the feed
/// does not offer.
///
/// What this case does NOT cover is `preferredVariant`'s own `else` arm; the
/// fallback above happens inside Foundation, one level up from it. Removing that
/// arm leaves every test here green, which is exactly what its doc comment says
/// to expect.
@Test func aReaderWithNoMatchingVariantGetsTheFirstOne() {
    let items = SparkleAppcastParser.parse(
        Data(macMouseFixShapedFeed.utf8),
        relativeTo: URL(string: "https://example.com/appcast.xml")!,
        preferredLanguages: ["ja-JP"])
    #expect(items.first?.releaseNotesLink?.lastPathComponent == "de.html")
}

/// A lone variant is used whatever its `xml:lang` claims — Sparkle never even
/// reads the attribute when there is nothing to choose between. This is what
/// keeps every single-variant feed we already parse unchanged; without it a
/// vendor who tags their one `<description>` `de` would lose its notes entirely
/// for most readers.
@Test func aLoneVariantIsUsedWhateverLanguageItClaims() {
    let xml = feed(items: ["<description xml:lang=\"de\"><![CDATA[Nur Deutsch]]></description>"])
    let items = SparkleAppcastParser.parse(Data(xml.utf8), preferredLanguages: ["en-US"])
    #expect(items.first?.descriptionHTML == "Nur Deutsch")
}

/// An untagged variant among tagged ones counts as English — Sparkle assumes the
/// same (it logs an error and defaults to `en`). Mutation: treat untagged as
/// unknown and skip it, and the English reader falls through to `zh-Hans`.
@Test func anUntaggedVariantCountsAsEnglish() {
    let xml = feed(items: [
        "<description xml:lang=\"zh-Hans\"><![CDATA[中文]]></description>",
        "<description><![CDATA[English]]></description>",
    ])
    let items = SparkleAppcastParser.parse(Data(xml.utf8), preferredLanguages: ["en-US"])
    #expect(items.first?.descriptionHTML == "English")
}

/// A channel-level `<description>` sits outside every `<item>` and has always
/// been dropped. Mutation: drop the `current != nil` guard in `recordLocalized`
/// and the channel blurb becomes a variant of the first item's notes — on an
/// English Mac it would even win, because it carries no `xml:lang`.
@Test func channelLevelNotesDoNotLeakIntoTheFirstItem() {
    let xml = """
    <?xml version="1.0" standalone="yes"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
      <title>Example feed</title>
      <description>Most recent changes with links to updates.</description>
      <item>
        <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
        <description xml:lang="zh-Hans"><![CDATA[中文]]></description>
        <description xml:lang="ja"><![CDATA[日本語]]></description>
        <enclosure url="https://example.com/App-1.0.zip" length="1" type="application/octet-stream"/>
      </item>
    </channel>
    </rss>
    """
    let items = SparkleAppcastParser.parse(Data(xml.utf8), preferredLanguages: ["en-US"])
    #expect(items.count == 1)
    #expect(items.first?.descriptionHTML == "中文")
}

/// One item's variants must not survive into the next. Mutation: drop the
/// `localizedChildren.removeAll()` that runs when an `<item>` opens, and 1.0's
/// two-language table is still standing while 0.9 is read — 0.9's own single
/// untagged note then competes with 1.0's stale `en` one, loses on position, and
/// this fails.
@Test func variantsDoNotLeakFromOneItemToTheNext() {
    let xml = """
    <?xml version="1.0" standalone="yes"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
      <item>
        <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
        <description xml:lang="en"><![CDATA[Newest, English]]></description>
        <description xml:lang="zh-Hans"><![CDATA[最新]]></description>
        <enclosure url="https://example.com/App-1.0.zip" length="1" type="application/octet-stream"/>
      </item>
      <item>
        <sparkle:shortVersionString>0.9</sparkle:shortVersionString>
        <description><![CDATA[Older, untagged]]></description>
        <enclosure url="https://example.com/App-0.9.zip" length="1" type="application/octet-stream"/>
      </item>
    </channel>
    </rss>
    """
    let items = SparkleAppcastParser.parse(Data(xml.utf8), preferredLanguages: ["en-US"])
    #expect(items.count == 2)
    #expect(items.first?.descriptionHTML == "Newest, English")
    #expect(items.last?.descriptionHTML == "Older, untagged")
}

/// `<markdownDescription>` is localizable the same way, and the two spellings
/// share one table — a feed mixing them compares its variants against each other
/// rather than letting whichever spelling came first win outright.
@Test func markdownDescriptionIsLocalizedAcrossBothSpellings() {
    // The reader's language sits on the `sparkle:` spelling and the other one on
    // the plain spelling, so a table keyed per spelling cannot answer "New": it
    // would only ever see one of the two and hand back "Neu".
    let xml = feed(items: [
        "<markdownDescription xml:lang=\"de\">Neu</markdownDescription>",
        "<sparkle:markdownDescription xml:lang=\"en\">New</sparkle:markdownDescription>",
    ])
    let items = SparkleAppcastParser.parse(Data(xml.utf8), preferredLanguages: ["en-US"])
    #expect(items.first?.markdownDescription == "New")
}

// MARK: - Fixtures

/// Wrap `items` — the localizable children under test — in the smallest feed the
/// parser will yield an item for.
private func feed(items children: [String]) -> String {
    """
    <?xml version="1.0" standalone="yes"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
      <item>
        <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
        \(children.joined(separator: "\n    "))
        <enclosure url="https://example.com/App-1.0.zip" length="1" type="application/octet-stream"/>
      </item>
    </channel>
    </rss>
    """
}

/// Mole's shape, trimmed: inline CDATA notes, `en` first and `pt-BR` last —
/// the two ends a positional reader would have landed on.
private let moleShapedFeed = feed(items: [
    "<description xml:lang=\"en\"><![CDATA[<ol><li>Software updates</li></ol>]]></description>",
    "<description xml:lang=\"zh-Hans\"><![CDATA[<ol><li>软件更新</li></ol>]]></description>",
    "<description xml:lang=\"pt-BR\"><![CDATA[<ol><li>Atualizações</li></ol>]]></description>",
])

/// Mac Mouse Fix's shape, trimmed: linked notes, one URL per language, German
/// first and no `en` variant anywhere.
private let macMouseFixShapedFeed = feed(items: [
    "<sparkle:releaseNotesLink xml:lang=\"de\">notes/3.0.8/de.html</sparkle:releaseNotesLink>",
    "<sparkle:releaseNotesLink xml:lang=\"zh-Hans\">notes/3.0.8/zh-Hans.html</sparkle:releaseNotesLink>",
    "<sparkle:releaseNotesLink xml:lang=\"ko\">notes/3.0.8/ko.html</sparkle:releaseNotesLink>",
])
