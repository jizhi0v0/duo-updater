import Foundation
import Testing

@testable import DuoKit

/// A sweep finding accuses a recipe. Some things it discovers accuse nobody —
/// they describe the machine doing the sweeping — and the difference matters,
/// because an accusation that repeats twice becomes a public GitHub comment.
///
/// The rollout-track note is the case: on a sweep box nobody signs into ChatGPT,
/// "this machine could not read its plan" is the permanent, correct state of a
/// perfectly healthy recipe. `installURLTransient` was split out of
/// `installURLUnresolved` for the same reason.
struct MachineNoteTests {

    private func finding(status: FindingStatus = .ok) -> Finding {
        Finding(
            recipeID: "vendor:com.example.app:stable", registry: .vendor,
            bundleID: "com.example.app", channel: "stable",
            status: status, version: "1.2.3",
            warnings: [], endpointHost: "example.invalid", pattern: "([0-9.]+)")
    }

    private let note = Finding.machineNotePrefix
        + "rolloutTrackDefaulted: no value at ~/.codex/auth.json, so this machine is"
        + " asking as `unknown` while the vendor is serving two tracks (2.0 vs 1.0)"

    /// The whole point of the split: a note is carried, and the finding stays ok.
    @Test func aNoteIsCarriedWithoutPromotingTheStatus() {
        let observed = finding().observing(note)
        #expect(observed.status == .ok)
        #expect(observed.warnings.contains(note))
    }

    /// And so it never accumulates a streak. Two sweeps is the threshold at which
    /// a real complaint becomes a public comment.
    @Test func aNoteNeverMakesARecipeReportable() {
        var baseline = Baseline()
        let observed = finding().observing(note)
        baseline.reconcile(observed)
        baseline.reconcile(observed)
        #expect(!baseline.isReportable(observed.recipeID))
        #expect(baseline.streak(observed.recipeID) == 0)
    }

    /// The contrast, so this is a real distinction rather than a spelling: the
    /// same text attached as a warning DOES promote and DOES accumulate. This is
    /// what the note would have done before the split.
    @Test func anOrdinaryWarningStillPromotesAndAccumulates() {
        var baseline = Baseline()
        let warned = finding().adding(warning: "something the recipe got wrong")
        #expect(warned.status == .warn)
        baseline.reconcile(warned)
        baseline.reconcile(warned)
        #expect(baseline.isReportable(warned.recipeID))
    }

    /// The note survives `Finding`'s redactor intact — it names a path, and a
    /// note nobody can read is the silence this was built to end.
    @Test func theNoteSurvivesRedaction() {
        let observed = finding().observing(note)
        #expect(observed.warnings.first?.contains("~/.codex/auth.json") == true)
        #expect(observed.warnings.first?.contains("rolloutTrackDefaulted") == true)
    }
}
