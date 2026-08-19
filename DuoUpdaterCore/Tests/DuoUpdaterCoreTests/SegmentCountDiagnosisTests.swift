import Testing
import Foundation
@testable import DuoUpdaterCore

/// Zotero shipped `10.0` where every release before it had three segments. The
/// pattern stopped matching, the probe reported a bare "no match", and the app
/// vanished from the update list with no error anywhere — it took a human
/// reading the page to work out what had changed.
///
/// 33 patterns in the registry still pin an exact segment count. Audited against
/// every live endpoint on 2026-08-19: for all but one (Plex, whose count IS
/// load-bearing and is deliberately strict) relaxing the count changes nothing
/// today, so widening them wholesale would be churn without evidence. Detecting
/// the day it stops being true is worth more, which is what this does.
struct SegmentCountDiagnosisTests {

    /// The real pattern that broke, against the real page shape that broke it.
    @Test func theZoteroFailureNowExplainsItself() {
        let brokenPattern = #""standaloneVersions"\s*:\s*\{\s*"mac"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#
        let body = #"{"standaloneVersions":{"mac":"10.0","win32":"10.0"},"oldVersions":{"macOS":{"version":"7.0.32"}}}"#

        // Red: this is exactly what the sweep saw on the day it broke.
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: brokenPattern) == nil)

        // Green: and this is what it would have said instead.
        #expect(VendorProbeRecipe.versionIfSegmentCountRelaxed(
            from: body, pattern: brokenPattern) == "10.0")
    }

    /// The other direction fails just as silently: a vendor ADDING a segment,
    /// where a delimiter-bounded pattern stops matching entirely.
    @Test func anAddedSegmentIsDiagnosedToo() {
        let pattern = #""name"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#
        let body = #"{"name":"1.133.0.4"}"#
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pattern) == nil)
        #expect(VendorProbeRecipe.versionIfSegmentCountRelaxed(
            from: body, pattern: pattern) == "1.133.0.4")
    }

    /// It must not fire on a miss that has nothing to do with segment counts —
    /// a vendor renaming the key is a different problem with a different fix.
    @Test func anUnrelatedMissIsNotBlamedOnSegmentCounts() {
        let pattern = #""name"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#
        let body = #"{"productVersion":"1.133.0"}"#
        #expect(VendorProbeRecipe.versionIfSegmentCountRelaxed(
            from: body, pattern: pattern) == nil)
    }

    /// A pattern that pins no segment run at all is not applicable, and must be
    /// distinguishable from one that is applicable and found nothing.
    @Test func aPatternWithNoSegmentRunIsNotApplicable() {
        #expect(VendorProbeRecipe.segmentCountRelaxed(#"Build\s+([0-9]+)"#) == nil)
        #expect(VendorProbeRecipe.segmentCountRelaxed(
            #"([0-9]+\.[0-9]+\.[0-9]+)"#) != nil)
    }

    /// The diagnosis is advisory only — it must never become a version we act on,
    /// or Plex would start reporting a build number the app never reports.
    @Test func theRelaxedValueIsNeverUsedAsTheAnswer() throws {
        let plex = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "tv.plex.desktop" })
        let body = #"{"computer":{"MacOS":{"version":"1.115.0.426-4e960a1d"}}}"#
        // The strict pattern still matches, so the diagnosis never runs for Plex.
        #expect(VendorProbeRecipe.extractVersion(
            from: body, pattern: plex.versionPattern) == "1.115.0")
    }
}
