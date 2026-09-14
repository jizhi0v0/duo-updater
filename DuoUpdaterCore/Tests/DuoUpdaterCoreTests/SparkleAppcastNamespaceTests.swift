import Testing
import Foundation
@testable import DuoUpdaterCore

/// Sparkle's vocabulary is a NAMESPACE
/// (`http://www.andymatuschak.org/xml-namespaces/sparkle`), not the literal
/// string `sparkle:`. The prefix a feed binds it to is the vendor's choice, and
/// until #641 this parser recognised only the conventional one — so a feed that
/// bound the same namespace to `s:`, or made it the document's default, parsed
/// with the whole vocabulary missing. For `maximumSystemVersion` that fails
/// OPEN: the vendor's "not for an OS this new" disappears and the item is
/// offered to the Mac it was capped away from.
///
/// ## What was measured before writing the fallback
///
/// The proposal kept the literal-prefix path "for feeds that declare no
/// namespace at all (some do)". Measured 2026-09-15 over this checkout
/// (`git ls-files`, every `<rss …>…</rss>` block in .swift/.xml/.json/.md):
/// **47 appcast bodies, 40 of which use a `sparkle:` name, and all 40 declare
/// `xmlns:sparkle`. Zero declare none; zero bind the URI to another prefix.**
/// So the fallback is NOT justified by an observed feed — no such body exists in
/// the repo, and the live feeds are read off installed bundles, not stored here.
/// What justifies it is measured too, on Foundation rather than on feeds (see
/// `docs/engine-notes/sparkle-appcast-source.md` §1): with
/// `shouldProcessNamespaces = true`, an UNDECLARED `sparkle:` prefix does not
/// fail the parse — libxml2 recovers and reports local name `version` with an
/// empty namespace URI. Dropping the literal path would therefore silently lose
/// the vocabulary of any feed that declares nothing, or that declares the URI
/// with a typo, and both parse today. The fallback is what makes this change a
/// strict superset of the old behaviour instead of a trade.
///
/// ## Mutations
///
/// Every row below was applied to `SparkleAppcastSource.swift` for real, run,
/// and reverted (2026-09-15). "RED" names the cases that failed.
///
/// | #  | Mutation | Result |
/// |----|----------|--------|
/// |  1 | `parser.shouldProcessNamespaces = false` | RED — `altPrefix…`, `defaultNamespace…`, `anUnprefixedEnclosureAttributeIsNotSparkles` |
/// |  2 | drop `parser.shouldReportNamespacePrefixes = true` | RED — `altPrefix…`, `defaultNamespace…`, `aBoundPrefixBeatsTheLiteralOneOnAttributesToo`, `aPrefixReboundOnAnInnerElementIsRestoredAfterIt` |
/// |  3 | `sparkleLocalName`: delete the literal-`sparkle:` fallback (clause 2) | RED — `anUndeclaredPrefixStillParses`, `aTypoedNamespaceURIStillParses` |
/// |  4 | `sparkleAttribute`: delete the prefix-scan loop, keep only the literal key | RED — `altPrefix…`, `defaultNamespace…`, `aBoundPrefix…`, `aPrefixRebound…` |
/// |  5 | `sparkleAttribute`: fall back to an unprefixed key as well | RED — `anUnprefixedEnclosureAttributeIsNotSparkles` |
/// |  6 | `didEndElement`: drop the `handled` guard, let both switches run | **GREEN** |
/// |  7 | `didStartElement`: match `deltas` on local name only, no namespace check | RED — `aForeignDeltasBlockDoesNotSwallowTheRealEnclosure` |
/// |  8 | `didEndElement`: delete the Sparkle `releaseNotesLink` case | RED — `theConventionalSpellingReadsEveryField` only |
/// |  9 | `didEndMappingPrefix`: clear the prefix outright instead of popping one binding | RED — `aPrefixReboundOnAnInnerElementIsRestoredAfterIt` |
/// | 10 | `rssLocalName`: return `elementName` unconditionally (match every namespace) | RED — `aForeignVocabularyIsNotReadAsRSS` |
/// | 11 | `rssLocalName`: gate on `namespaceURI` being empty or Sparkle's instead of on the prefix | RED — `aForeignDefaultNamespaceStillParses` |
/// | 12 | `sparkleAttribute`: check the literal `sparkle:` key BEFORE the resolved scan | RED — `aBoundPrefixBeatsTheLiteralOneOnAttributesToo` |
/// | 13 | `VendorAppcastDeltas`: restore the `contains("sparkle:deltas")` gate | RED — `anAltPrefixDeltasBlockIsNotShortCircuitedByTheGate` |
/// | 14 | hoisted `sortedAttributeKeys` returns empty (sort never happens) | RED — 6 cases across both suites |
/// | 15 | `maximumSystemVersion` becomes first-wins like `version` | RED — `aFeedCarryingBothSpellingsOfAnElementIsOrderDecided` |
///
/// Four rows are worth more than their verdict:
///
///  * **10 and 11 are the two ways to get `rssLocalName` wrong, and they fail
///    in opposite directions** — which is why the rule is "the qualified name
///    carries no prefix" and not either of them. 10 is what the first draft of
///    this change actually did, and it was caught in review, not by a test:
///    with `elementName` now the bare local name, a `<dc:description>` became
///    the release notes and a nested `<x:item>` made the genuine release vanish.
///    11 is the obvious correction, and it silently drops every element of a
///    feed whose default namespace is somebody else's.
///  * **6 is GREEN and left green; 7 was wrongly assumed to be.** Dropping
///    `handled` really does record a Sparkle-namespaced `<markdownDescription>`
///    twice, but the two copies are the same text in the same language, so
///    `preferredVariant` returns the same string either way — covering it would
///    be writing `f(X) == f(X)`. 7 was in this paragraph too, on the reasoning
///    that "no appcast vocabulary names a non-Sparkle `<deltas>`". That reasoning
///    was about the START tag and missed the asymmetry: the mutation changes only
///    the start, while `didEndElement` still resolves the namespace and correctly
///    answers nil, so `deltasDepth` goes up and never comes down and every later
///    `<enclosure>` — the real download included — is filed as a patch. A
///    five-line fixture makes it red. **A green mutation is a claim that needs a
///    fixture attempted against it, not a conclusion.**
///  * **8 went red in ONE case, and not the three that look like they should
///    have.** Losing `releaseNotesLink` loses it from the reference feed and
///    from each re-spelling alike, so all three `…ParsesLikeTheConventionalOne`
///    comparisons stayed green comparing one empty field to another. That is
///    exactly why `theConventionalSpellingReadsEveryField` asserts literal
///    values instead of a fourth parse: without it, this whole suite could agree
///    on nothing at all.
@Suite struct SparkleAppcastNamespaceTests {

    private static let sparkleURI = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    /// Every field the parser can fill, flattened, so "the three feeds agree"
    /// is an assertion about all of them rather than about the two somebody
    /// remembered. A new field added to `SparkleAppcastItem` and not added here
    /// is invisible to this suite — which is why the mutation table above tests
    /// the MATCHING, not the field list.
    private static func fingerprint(_ items: [SparkleAppcastItem]) -> [String] {
        items.map { i in
            [
                "short=\(i.shortVersionString ?? "-")",
                "version=\(i.version ?? "-")",
                "url=\(i.enclosureURL?.absoluteString ?? "-")",
                "length=\(i.enclosureLength.map(String.init) ?? "-")",
                "ed=\(i.edSignature ?? "-")",
                "min=\(i.minimumSystemVersion ?? "-")",
                "max=\(i.maximumSystemVersion ?? "-")",
                "deltaFrom=\(i.deltaFrom ?? "-")",
                "deltas=\(i.deltas.map { "\($0.fromBuild)|\($0.url.absoluteString)|\($0.size.map(String.init) ?? "-")|\($0.edSignature ?? "-")" }.joined(separator: ";"))",
                "channel=\(i.channel ?? "-")",
                "hw=\(i.hardwareRequirements.sorted().joined(separator: ","))",
                "minAuto=\(i.minimumAutoupdateVersion ?? "-")",
                "desc=\(i.descriptionHTML ?? "-")",
                "md=\(i.markdownDescription ?? "-")",
                "pubDate=\(i.pubDate ?? "-")",
                "notes=\(i.releaseNotesLink?.absoluteString ?? "-")",
            ].joined(separator: " ")
        }
    }

    /// One feed body, spelled with `prefix` for Sparkle's vocabulary.
    ///
    /// `rootAttributes` carries the namespace declarations, so the three shapes
    /// differ ONLY in how the namespace is bound — same elements, same
    /// attributes, same values, so a difference in the fingerprint can only be
    /// the binding.
    ///
    /// ⚠️ `attributePrefix` is separate from the element spelling on purpose.
    /// An unprefixed attribute is in NO namespace even under a default `xmlns`
    /// (XML Namespaces §6.2), so "Sparkle as the default namespace" cannot
    /// express `<enclosure sparkle:version>` unprefixed — a real feed in that
    /// shape must still bind a prefix for its attributes. Writing the fixture as
    /// if it could would be testing an XML document that cannot exist.
    private static func feed(elementPrefix: String, attributePrefix: String, rootAttributes: String) -> String {
        let e = elementPrefix.isEmpty ? "" : "\(elementPrefix):"
        let a = "\(attributePrefix):"
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" \(rootAttributes)>
          <channel>
            <title>Subject</title>
            <item>
              <title>2.0</title>
              <pubDate>Mon, 01 Sep 2026 10:00:00 +0000</pubDate>
              <\(e)shortVersionString>2.0</\(e)shortVersionString>
              <\(e)version>200</\(e)version>
              <\(e)minimumSystemVersion>14.0</\(e)minimumSystemVersion>
              <\(e)maximumSystemVersion>26.99</\(e)maximumSystemVersion>
              <\(e)channel>beta</\(e)channel>
              <\(e)hardwareRequirements>arm64</\(e)hardwareRequirements>
              <\(e)minimumAutoupdateVersion>150</\(e)minimumAutoupdateVersion>
              <\(e)releaseNotesLink>https://example.com/notes/2.0.html</\(e)releaseNotesLink>
              <\(e)markdownDescription>## Two point oh.</\(e)markdownDescription>
              <description><![CDATA[<p>Two point oh.</p>]]></description>
              <\(e)deltas>
                <enclosure url="https://example.com/Subject200-199.delta"
                           \(a)deltaFrom="199" length="1024" \(a)edSignature="deltasig"/>
              </\(e)deltas>
              <enclosure url="https://example.com/Subject-2.0.dmg" length="4096"
                         \(a)version="200" \(a)shortVersionString="2.0" \(a)edSignature="sig"/>
            </item>
          </channel>
        </rss>
        """
    }

    /// The shape 40 of this repo's 40 sparkle-using bodies are written in.
    private static var conventional: String {
        feed(elementPrefix: "sparkle", attributePrefix: "sparkle",
             rootAttributes: #"xmlns:sparkle="\#(sparkleURI)""#)
    }

    private static func parse(_ xml: String) -> [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data(xml.utf8), preferredLanguages: ["en-US"])
    }

    /// The reference reading. Asserted against literal values rather than
    /// against another parse, so the three "…ParsesLikeTheConventionalOne" cases
    /// cannot all agree on nothing: if the baseline silently went empty, this
    /// goes red first and names why.
    @Test func theConventionalSpellingReadsEveryField() throws {
        let items = Self.parse(Self.conventional)
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.shortVersionString == "2.0")
        #expect(item.version == "200")
        #expect(item.minimumSystemVersion == "14.0")
        #expect(item.maximumSystemVersion == "26.99")
        #expect(item.channel == "beta")
        #expect(item.hardwareRequirements == ["arm64"])
        #expect(item.minimumAutoupdateVersion == "150")
        #expect(item.releaseNotesLink?.absoluteString == "https://example.com/notes/2.0.html")
        #expect(item.descriptionHTML == "<p>Two point oh.</p>")
        #expect(item.markdownDescription == "## Two point oh.")
        #expect(item.pubDate == "Mon, 01 Sep 2026 10:00:00 +0000")
        #expect(item.edSignature == "sig")
        #expect(item.enclosureLength == 4096)
        #expect(item.enclosureURL?.absoluteString == "https://example.com/Subject-2.0.dmg")
        // The delta enclosure must not have hijacked the item's download.
        #expect(item.deltaFrom == nil)
        #expect(item.deltas.count == 1)
        #expect(item.deltas.first?.fromBuild == "199")
        #expect(item.deltas.first?.edSignature == "deltasig")
    }

    /// (1) The namespace bound to a prefix that is not `sparkle`.
    @Test func altPrefixParsesLikeTheConventionalOne() {
        let alt = Self.feed(elementPrefix: "s", attributePrefix: "s",
                            rootAttributes: #"xmlns:s="\#(Self.sparkleURI)""#)
        #expect(Self.fingerprint(Self.parse(alt)) == Self.fingerprint(Self.parse(Self.conventional)))
    }

    /// (2) Sparkle as the DEFAULT namespace: elements unprefixed. RSS's own
    /// `<item>`, `<enclosure>`, `<description>`, `<pubDate>` and `<channel>`
    /// land in Sparkle's namespace too, which is the case that makes matching
    /// RSS on local name regardless of namespace load-bearing rather than lazy.
    @Test func defaultNamespaceParsesLikeTheConventionalOne() {
        let defaulted = Self.feed(
            elementPrefix: "", attributePrefix: "sp",
            rootAttributes: #"xmlns="\#(Self.sparkleURI)" xmlns:sp="\#(Self.sparkleURI)""#)
        #expect(Self.fingerprint(Self.parse(defaulted)) == Self.fingerprint(Self.parse(Self.conventional)))
    }

    /// (3) No namespace declared at all — the literal prefix, and the shape the
    /// fallback exists for.
    @Test func anUndeclaredPrefixStillParses() {
        let undeclared = Self.feed(elementPrefix: "sparkle", attributePrefix: "sparkle",
                                   rootAttributes: "")
        #expect(Self.fingerprint(Self.parse(undeclared)) == Self.fingerprint(Self.parse(Self.conventional)))
    }

    /// The same fallback, for the likelier accident: the vendor DID declare a
    /// namespace and got the URI wrong. This parses today; it must keep parsing,
    /// or the fix trades one silent total loss for another.
    @Test func aTypoedNamespaceURIStillParses() {
        let typo = Self.feed(
            elementPrefix: "sparkle", attributePrefix: "sparkle",
            rootAttributes: #"xmlns:sparkle="http://andymatuschak.org/xml-namespaces/sparkle""#)
        #expect(Self.fingerprint(Self.parse(typo)) == Self.fingerprint(Self.parse(Self.conventional)))
    }

    /// An unprefixed `version` on `<enclosure>` is in no namespace, so it is not
    /// Sparkle's — even in a document whose default namespace IS Sparkle's. The
    /// item's version must come from the `<sparkle:version>` CHILD, and the bare
    /// attribute must be ignored rather than overwrite it.
    @Test func anUnprefixedEnclosureAttributeIsNotSparkles() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns="\(Self.sparkleURI)">
          <channel><item>
            <version>200</version>
            <enclosure url="https://example.com/Subject-2.0.dmg" length="1" version="999"/>
          </item></channel>
        </rss>
        """
        #expect(Self.parse(xml).first?.version == "200")
    }

    /// Somebody else's vocabulary must not be read as RSS just because it picked
    /// the same local names.
    ///
    /// This is the trap namespace processing opens rather than closes: once
    /// `elementName` is the BARE local name, a switch on it alone matches
    /// `description` / `item` / `enclosure` in EVERY namespace. Both halves here
    /// were observed on the first draft of this change — `<dc:description>`
    /// became the release notes, and a nested `<x:item>` reset `current` and made
    /// the genuine release vanish entirely (parsed: one item, no version at all).
    @Test func aForeignVocabularyIsNotReadAsRSS() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="\(Self.sparkleURI)"
             xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:x="https://example.com/x">
          <channel><item>
            <dc:description>FOREIGN</dc:description>
            <description>REAL</description>
            <x:item><x:note>junk</x:note></x:item>
            <sparkle:version>200</sparkle:version>
            <enclosure url="https://example.com/a.dmg" length="1" sparkle:version="200"/>
          </item></channel>
        </rss>
        """
        let items = Self.parse(xml)
        #expect(items.count == 1)
        #expect(items.first?.version == "200")
        #expect(items.first?.descriptionHTML == "REAL")
    }

    /// The other direction, and the reason the RSS gate is "no prefix" rather
    /// than "no namespace, or Sparkle's": a feed whose DEFAULT namespace is
    /// somebody else's (RSS 1.0's URI here) parses today, and a namespace-URI
    /// gate would have stopped matching every element in it.
    @Test func aForeignDefaultNamespaceStillParses() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns="http://purl.org/rss/1.0/" xmlns:sparkle="\(Self.sparkleURI)">
          <channel><item>
            <description>REAL</description>
            <sparkle:version>200</sparkle:version>
            <enclosure url="https://example.com/a.dmg" length="1" sparkle:version="200"/>
          </item></channel>
        </rss>
        """
        #expect(Self.parse(xml).map { "\($0.version ?? "-")/\($0.descriptionHTML ?? "-")" } == ["200/REAL"])
    }

    /// Elements and attributes must resolve the SAME way round: the properly
    /// bound prefix wins over the literal `sparkle:` one. A feed that bound
    /// `sparkle` to a foreign vocabulary and Sparkle's real URI to `s` would
    /// otherwise take one half of the item from each vendor.
    @Test func aBoundPrefixBeatsTheLiteralOneOnAttributesToo() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="https://example.com/not-sparkle" xmlns:s="\(Self.sparkleURI)">
          <channel><item>
            <enclosure url="https://example.com/a.dmg" length="1"
                       sparkle:version="foreign" s:version="200"/>
          </item></channel>
        </rss>
        """
        #expect(Self.parse(xml).first?.version == "200")
    }

    /// A foreign `<x:deltas>` must not open the delta region — and, more to the
    /// point, must not open one that never closes.
    ///
    /// This is what separates mutation 7 from mutation 6. Matching `<deltas>` on
    /// the bare local name looks symmetric, but only the START tag is mutated:
    /// `didEndElement` still asks `sparkleLocalName`, which correctly answers nil
    /// for `x:deltas`. So `deltasDepth` goes up and never comes back down, and
    /// every later `<enclosure>` in the feed — including the real download — is
    /// filed as a delta patch. The item ends up with no URL at all.
    @Test func aForeignDeltasBlockDoesNotSwallowTheRealEnclosure() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="\(Self.sparkleURI)" xmlns:x="https://example.com/x">
          <channel><item>
            <x:deltas>
              <enclosure url="https://example.com/p.delta" length="1" sparkle:deltaFrom="199"/>
            </x:deltas>
            <enclosure url="https://example.com/a.dmg" length="4096" sparkle:version="200"/>
          </item></channel>
        </rss>
        """
        let item = Self.parse(xml).first
        #expect(item?.enclosureURL?.absoluteString == "https://example.com/a.dmg")
        #expect(item?.version == "200")
    }

    /// Two vocabularies claiming the same element name: who wins is decided by
    /// DOCUMENT ORDER, not by which prefix is properly bound.
    ///
    /// Elements are independent `didEndElement` calls with no memory of each
    /// other, so the attribute rule (bound prefix beats the literal one, see
    /// `aBoundPrefixBeatsTheLiteralOneOnAttributesToo`) has no element analogue —
    /// saying the parser "resolves both the same way round" would be false. The
    /// direction is not even uniform between fields, which is why this pins both:
    /// `maximumSystemVersion` assigns unconditionally so the LAST spelling wins,
    /// while `version` carries an `== nil` guard so the FIRST one does.
    ///
    /// Pre-existing behaviour that namespace support merely makes reachable — no
    /// observed feed carries two vocabularies claiming one Sparkle element name.
    /// Pinned so that if anyone ever makes it uniform, they do it deliberately.
    @Test func aFeedCarryingBothSpellingsOfAnElementIsOrderDecided() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="https://example.com/not-sparkle" xmlns:s="\(Self.sparkleURI)">
          <channel><item>
            <s:maximumSystemVersion>26.0</s:maximumSystemVersion>
            <sparkle:maximumSystemVersion>99.0</sparkle:maximumSystemVersion>
            <s:version>200</s:version>
            <sparkle:version>999</sparkle:version>
            <enclosure url="https://example.com/a.dmg" length="1"/>
          </item></channel>
        </rss>
        """
        let item = Self.parse(xml).first
        #expect(item?.maximumSystemVersion == "99.0")  // last wins: unconditional assign
        #expect(item?.version == "200")                // first wins: `== nil` guard
    }

    /// A prefix declared ON the very element that uses it must already be bound
    /// when that element's attributes are read.
    ///
    /// `didStartMappingPrefix` fires just BEFORE the start tag it belongs to, so
    /// this works — but nothing else in this suite would notice if the ordering
    /// were the other way round, because every other fixture declares its prefixes
    /// on an ancestor.
    @Test func aPrefixDeclaredOnTheElementItselfIsAlreadyBound() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0">
          <channel><item>
            <enclosure xmlns:s="\(Self.sparkleURI)"
                       url="https://example.com/a.dmg" length="1" s:version="200"/>
          </item></channel>
        </rss>
        """
        #expect(Self.parse(xml).first?.version == "200")
    }

    /// A prefix REBOUND on an inner element must go back to its outer binding
    /// when that element closes — which is why the bindings are a stack per
    /// prefix and not one URI per prefix.
    ///
    /// Item 2 rebinds `s` to somebody else's vocabulary, so its `s:version`
    /// attribute is not Sparkle's and the item is left with only the version its
    /// `<s:version>`-free body gives it. Item 3 is back under the outer binding
    /// and must read normally: forgetting the outer binding on `</item>` is the
    /// bug this catches, and it shows up on the LAST item rather than the one
    /// that did the rebinding.
    @Test func aPrefixReboundOnAnInnerElementIsRestoredAfterIt() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:s="\(Self.sparkleURI)">
          <channel>
            <item><enclosure url="https://example.com/1.dmg" length="1" s:version="100"/></item>
            <item xmlns:s="https://example.com/not-sparkle">
              <enclosure url="https://example.com/2.dmg" length="1" s:version="200"/>
            </item>
            <item><enclosure url="https://example.com/3.dmg" length="1" s:version="300"/></item>
          </channel>
        </rss>
        """
        #expect(Self.parse(xml).map { $0.version ?? "-" } == ["100", "-", "300"])
    }

    /// `markdownDescription` is the one element in both vocabularies, and the
    /// two spellings must keep sharing one variant list — otherwise a feed
    /// mixing them lets whichever spelling came first win outright instead of
    /// letting the reader's language decide.
    @Test func bothMarkdownSpellingsShareOneVariantList() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="\(Self.sparkleURI)">
          <channel><item>
            <sparkle:version>200</sparkle:version>
            <sparkle:markdownDescription xml:lang="de">Zwei</sparkle:markdownDescription>
            <markdownDescription xml:lang="en">Two</markdownDescription>
            <enclosure url="https://example.com/Subject-2.0.dmg" length="1" sparkle:version="200"/>
          </item></channel>
        </rss>
        """
        #expect(Self.parse(xml).first?.markdownDescription == "Two")
    }
}
