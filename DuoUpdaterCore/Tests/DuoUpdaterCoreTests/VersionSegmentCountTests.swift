import Testing
import Foundation
@testable import DuoUpdaterCore

/// Zotero shipped `10.0` where every release before it had three segments, and
/// the recipe's pattern demanded exactly three. Nothing errored — the app simply
/// stopped appearing as updatable until a sweep noticed. These tests pin the two
/// halves of the rule that came out of auditing the rest of the registry.
struct VersionSegmentCountTests {

    private func recipe(_ bundleID: String) -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == bundleID }
    }

    private func extract(_ body: String, _ recipe: VendorProbeRecipe) -> String? {
        VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern)
    }

    // MARK: The widened patterns keep working, in both directions

    @Test func aDelimitedPatternAcceptsFewerSegmentsThanBefore() throws {
        // The Zotero shape: a major bump that drops a segment.
        let recipe = try #require(recipe("com.microsoft.VSCode"))
        #expect(extract(#"{"name":"1.133.0"}"#, recipe) == "1.133.0")
        #expect(extract(#"{"name":"2.0"}"#, recipe) == "2.0")
    }

    @Test func aDelimitedPatternAcceptsMoreSegmentsThanBefore() throws {
        // The other direction, which fails just as silently: a vendor adds a
        // segment and the closing delimiter no longer follows the capture.
        let recipe = try #require(recipe("com.microsoft.VSCode"))
        #expect(extract(#"{"name":"1.133.0.5"}"#, recipe) == "1.133.0.5")
    }

    @Test func wideningCannotDriftOntoANeighbouringNumber() throws {
        // Why only delimiter-bounded patterns were widened: the capture is pinned
        // on both sides, so a shorter number elsewhere in the document cannot win.
        let recipe = try #require(recipe("com.microsoft.VSCode"))
        let body = #"{"schema":"2.1","other":"9.9","name":"1.133.0","build":"7.7"}"#
        #expect(extract(body, recipe) == "1.133.0")
    }

    @Test func whatsAppNoLongerHardCodesItsMajorVersion() throws {
        // The filename carries a leading component the bundle does not report, so
        // it still has to be stripped — but which component it is was written as
        // the literal `2.`, which would stop matching the day WhatsApp ships 3.x.
        let recipe = try #require(recipe("net.whatsapp.WhatsApp"))
        #expect(extract("WhatsApp-2.26.33.15.dmg", recipe) == "26.33.15")
        #expect(extract("WhatsApp-3.26.33.15.dmg", recipe) == "26.33.15")
    }

    // MARK: The patterns deliberately left strict

    @Test func plexStaysAtThreeSegmentsBecauseItHasNoClosingDelimiter() throws {
        // Its feed value is `1.115.0.426-4e960a1d`. With nothing bounding the
        // capture on the right, the segment count IS the boundary: a fourth
        // segment would start reporting a build number the app never reports.
        let recipe = try #require(recipe("tv.plex.desktop"))
        let body = #"{"computer":{"MacOS":{"version":"1.115.0.426-4e960a1d"}}}"#
        #expect(extract(body, recipe) == "1.115.0")
    }

    @Test func sublimeTextKeepsItsMajorPinned() throws {
        // `Build 4NNN` looks like the same defect as WhatsApp's `2.` but is not:
        // the bundle id is version-pinned (`com.sublimetext.4`), and Sublime's
        // majors are the leading build digit. Widening it would offer a Sublime
        // Text 4 install the build number of a paid major upgrade. If Sublime 5
        // ever ships, this pattern stops matching and the sweep files an issue —
        // a detected failure, which is the better trade.
        let recipe = try #require(recipe("com.sublimetext.4"))
        let body = #"class="latest"><i>Version:</i> Build 4200"#
        #expect(extract(body, recipe) == "Build 4200")
        let five = #"class="latest"><i>Version:</i> Build 5001"#
        #expect(extract(five, recipe) == nil, "a Sublime 5 build must not be offered here")
    }
}
