import Testing
import Foundation
@testable import DuoUpdaterCore

/// A vendor track that is between releases, which is not a broken recipe.
@Suite
struct DormantTrackTests {

    private static var beta: VendorProbeRecipe {
        VendorProbeRegistry.recipes.first {
            $0.bundleID == CapCutChannel.bundleID && $0.channel == .beta
        }!
    }

    @Test("The vendor's own empty beta number is what marks the track closed")
    func closedTrackIsRecognisedFromTheVendorsOwnField() {
        // Measured 2026-09-04: 9.4.0 shipped to stable, no beta replaced it, and
        // `lastest_beta_number` went from "4" to "". `lastest_url` then carries
        // the stable artifact, the beta pattern correctly refuses it, and without
        // this the row went red with a Retry that could not work.
        #expect(Self.beta.matchesTrackClosed(##"…,"lastest_beta_number":"","lastest_url":"…"##))
        // While a beta is open the same body says so, and nothing is suppressed.
        #expect(!Self.beta.matchesTrackClosed(##"…,"lastest_beta_number":"4","lastest_url":"…"##))
    }

    @Test("An empty string elsewhere in 436 KB does not close the track")
    func theSignalIsAnchoredToItsKey() {
        // The body is ~436 KB of unrelated settings; an unanchored `""` would
        // match in a thousand places and silence a genuinely broken recipe.
        #expect(!Self.beta.matchesTrackClosed(##"{"some_other_key":"","beta_number":"4"}"##))
    }

    @Test("Only the beta track declares this, and stable never does")
    func stableCarriesNoDormancySignal() {
        // Stable has no closed state to declare: `lastest_stable_url` is always
        // populated. Declaring one there would let a real stable outage pass as
        // "nothing published", which is the failure this whole mechanism is
        // shaped to avoid on the other side.
        let stable = VendorProbeRegistry.recipes.first {
            $0.bundleID == CapCutChannel.bundleID && $0.channel == .stable
        }!
        #expect(stable.trackClosedPattern == nil)
        #expect(Self.beta.trackClosedPattern != nil)
    }

    @Test("A closed track is not applicable, not a failure")
    func closedTrackClassifiesAsNotApplicable() {
        // `.notApplicable` makes the source return nil rather than throw, so the
        // row does not go red and the failed-check banner does not count it.
        // Every other failure stays a failure.
        #expect(ProbeFailure.notApplicable("x").classification == .notApplicable)
        #expect(ProbeFailure.versionPatternNoMatch(sampleBytes: 1).classification == .recipe)
    }
}
