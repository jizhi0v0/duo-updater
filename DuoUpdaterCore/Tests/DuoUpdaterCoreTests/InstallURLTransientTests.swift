import Testing
import Foundation
@testable import DuoUpdaterCore

/// `td.telegram.org` answers the HEAD that resolves Telegram's download with a
/// 502 in bursts — confirmed by interleaving URLSession and curl against the same
/// URL in the same seconds, both 502, so it is the vendor rather than our client.
/// The probe reported that as `installURLUnresolved`, which means "the one-click
/// is dead, go fix the recipe", and two of those in a row file an issue. These
/// pin the rule that keeps a vendor's bad minute from being blamed on a recipe.
struct InstallURLTransientTests {

    @Test func fiveHundredsAndTooManyRequestsAreTheVendorsProblem() {
        for code in [500, 502, 503, 504, 429] {
            #expect(VendorProbeSource.isTransientStatus(code), "\(code) should be transient")
        }
    }

    @Test func clientErrorsAreOurProblemAndMustNotBeRetried() {
        // A 404 means the URL in the recipe is wrong. Retrying cannot fix that,
        // and reporting it as transient would hide a genuinely dead install spec.
        for code in [400, 401, 403, 404, 410] {
            #expect(!VendorProbeSource.isTransientStatus(code), "\(code) should not be transient")
        }
    }

    @Test func theTwoWarningsAreDistinct() {
        // They accuse different people, so they must not collapse into one kind:
        // one is actionable, the other is deliberately not.
        #expect(ProbeWarning.installURLTransient(status: 502).kind == "installURLTransient")
        #expect(ProbeWarning.installURLUnresolved.kind == "installURLUnresolved")
        #expect(ProbeWarning.installURLTransient(status: 502)
            != ProbeWarning.installURLUnresolved)
    }

    @Test func theStatusIsCarriedSoAReportCanSayWhichOne() {
        #expect(ProbeWarning.installURLTransient(status: 502)
            != ProbeWarning.installURLTransient(status: 503))
        #expect(ProbeWarning.installURLTransient(status: nil)
            .kind == ProbeWarning.installURLTransient(status: 502).kind,
            "the kind is the wire format and must not vary with the status")
    }
}
