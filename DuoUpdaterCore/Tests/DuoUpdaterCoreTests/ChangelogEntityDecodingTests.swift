import Testing
import Foundation
@testable import DuoUpdaterCore

/// `decodeHTMLEntities` used to iterate a `[String: String]` dictionary, so the
/// order the entities were substituted in changed with every process (Swift
/// randomises `Dictionary` iteration per launch via the hash seed). That made the
/// output of a double-escaped body — `&amp;lt;`, which a vendor writes when it
/// wants the reader to SEE `&lt;` — depend on whether `&amp;` happened to come
/// out of the dictionary before or after `&lt;`: one order left it escaped, the
/// other decoded it twice down to a literal `<`. `&#39;` was worse than random:
/// the numeric pass ran unconditionally AFTER the named one, so `&amp;#39;`
/// always decoded twice.
///
/// The decoder is now a single left-to-right pass over `&(#NNN|#xHH|name);`, which
/// is the semantics a standard HTML unescaper has: each entity in the INPUT is
/// decoded exactly once, and text a decode produces is never re-scanned. These
/// cases pin that, in both directions — an entity that must decode, and an
/// escaped entity that must survive.
@Suite struct ChangelogEntityDecodingTests {

    /// The case the dictionary order decided at random. `&amp;lt;br&amp;gt;` is a
    /// vendor showing the reader the literal text `<br>` escaped once; decoding it
    /// twice deletes the markup the sentence is about (the same failure
    /// `stripHTMLElements` exists to avoid).
    @Test func anEscapedEntityDecodesOnceAndStopsThere() {
        #expect(ChangelogExtractor.decodeHTMLEntities("&amp;lt;br&amp;gt;") == "&lt;br&gt;")
    }

    /// Numeric entities were decoded in a second pass that always ran after the
    /// named one, so this one was never a coin flip — it was always wrong.
    @Test func anEscapedNumericEntityIsNotDecodedTwice() {
        #expect(ChangelogExtractor.decodeHTMLEntities("&amp;#39;") == "&#39;")
        #expect(ChangelogExtractor.decodeHTMLEntities("&amp;#x27;") == "&#x27;")
    }

    /// The mirror image, and the reason "decode numerics first, `&amp;` last" is
    /// not a fix on its own: `&#38;` IS an ampersand, so with two ordered passes
    /// it would produce `&lt;` and the named pass behind it would eat that too.
    /// One pass can't, because it never re-reads what it wrote.
    @Test func anAmpersandSpelledNumericallyDoesNotCascade() {
        #expect(ChangelogExtractor.decodeHTMLEntities("&#38;lt;") == "&lt;")
    }

    /// Everything that is supposed to decode still does, in one pass.
    @Test func theOrdinaryEntitiesStillDecode() {
        #expect(ChangelogExtractor.decodeHTMLEntities(
            "a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos; &#39;f&#39;")
            == "a & b <c> \"d\" 'e' 'f'")
        #expect(ChangelogExtractor.decodeHTMLEntities(
            "&mdash;&ndash;&hellip;&rsquo;&lsquo;&ldquo;&rdquo;&times;")
            == "—–…’‘“”×")
        #expect(ChangelogExtractor.decodeHTMLEntities("&#x2019;s &#8212; done") == "’s — done")
    }

    /// An entity the table doesn't carry is left verbatim — the safe direction
    /// (visible noise beats invisible deletion), and unchanged from before.
    @Test func anUnknownEntityIsLeftAlone() {
        #expect(ChangelogExtractor.decodeHTMLEntities("&copy; 2026 &frac12;") == "&copy; 2026 &frac12;")
        #expect(ChangelogExtractor.decodeHTMLEntities("a & b") == "a & b")
        #expect(ChangelogExtractor.decodeHTMLEntities("&#xZZ; &#;") == "&#xZZ; &#;")
    }

    /// `escapedMarkup` recipes rely on running the decoder TWICE (an RSS
    /// `<description>` whose markup arrives escaped, with prose entities escaped
    /// twice). That still lands where it did: pass one turns `&amp;rsquo;` into
    /// `&rsquo;`, pass two into `’`.
    @Test func theSecondPassEscapedMarkupRecipesRelyOnStillLands() {
        let once = ChangelogExtractor.decodeHTMLEntities("&lt;p&gt;it&amp;rsquo;s&lt;/p&gt;")
        #expect(once == "<p>it&rsquo;s</p>")
        #expect(ChangelogExtractor.decodeHTMLEntities(once) == "<p>it’s</p>")
    }
}
