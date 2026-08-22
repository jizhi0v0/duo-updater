import Foundation
import Testing
@testable import DuoUpdaterCore

struct RestartStandoffTests {

    private func staged(_ short: String, _ build: String? = nil) -> StagedSelfUpdate {
        StagedSelfUpdate(
            version: short, buildVersion: build,
            stagedBundlePath: URL(fileURLWithPath: "/tmp/Staged.app"))
    }

    /// The overwhelming common case: nobody else is holding an installer open.
    @Test func nothingStagedProceeds() {
        #expect(RestartStandoff.decide(
            staged: nil, onDiskShortVersion: "1.2.3", onDiskBuildVersion: "45") == .proceed)
    }

    /// TablePlus, 2026-08-22: Sparkle had 26.9.11 (769) unpacked and an
    /// `Autoupdate` parked, and 26.9.11 (769) was also what we were installing.
    /// Whoever writes second writes the same thing.
    @Test func aStagedBuildMatchingDiskProceeds() {
        #expect(RestartStandoff.decide(
            staged: staged("26.9.11", "769"),
            onDiskShortVersion: "26.9.11", onDiskBuildVersion: "769") == .proceed)
    }

    /// Regression, ChatGPT 2026-08-22: we installed 26.818.41705, Sparkle had
    /// 26.818.41509 staged since 14:53, and our restart handed it the quit it was
    /// waiting for. Note the staged build is OLDER — a check phrased as "is an
    /// update pending" would have found nothing to worry about here.
    @Test func anOlderStagedBuildHoldsBack() {
        #expect(RestartStandoff.decide(
            staged: staged("26.818.41509", "6962"),
            onDiskShortVersion: "26.818.41705", onDiskBuildVersion: "6971")
            == .holdBack(stagedVersion: "26.818.41509"))
    }

    /// The other direction is no safer: quitting would still replace what we just
    /// installed with something we did not choose.
    @Test func aNewerStagedBuildHoldsBack() {
        #expect(RestartStandoff.decide(
            staged: staged("2.0.0", "200"),
            onDiskShortVersion: "1.0.0", onDiskBuildVersion: "100")
            == .holdBack(stagedVersion: "2.0.0"))
    }

    /// Regression for a hole the first version of this had, and which its tests
    /// could not have caught because every case they used differed in the
    /// marketing string. A vendor that keeps that string stable across builds —
    /// and this project already has the build-only bump on record — produces two
    /// genuinely different bundles whose short versions agree. Comparing only
    /// that string waves the restart through and the staged build lands over
    /// ours: the original failure in a different version scheme.
    @Test func aStagedBuildDifferingOnlyInBuildNumberHoldsBack() {
        #expect(RestartStandoff.decide(
            staged: staged("1.4.2", "5104"),
            onDiskShortVersion: "1.4.2", onDiskBuildVersion: "5120")
            == .holdBack(stagedVersion: "1.4.2"))
    }

    /// "We could not read the bundle" is not "the versions agree".
    @Test func anUnreadableDiskVersionHoldsBack() {
        #expect(RestartStandoff.decide(
            staged: staged("1.0.0", "100"),
            onDiskShortVersion: nil, onDiskBuildVersion: nil)
            == .holdBack(stagedVersion: "1.0.0"))
    }

    /// A field only one side carries proves nothing, so it is skipped rather than
    /// counted as a mismatch — but the fields both sides do carry still decide.
    @Test func fieldsOnlyOneSideCarriesAreSkipped() {
        #expect(RestartStandoff.decide(
            staged: staged("1.0.0", nil),
            onDiskShortVersion: "1.0.0", onDiskBuildVersion: "100") == .proceed)
        #expect(RestartStandoff.decide(
            staged: staged("1.0.0", "101"),
            onDiskShortVersion: "1.0.0", onDiskBuildVersion: nil) == .proceed)
        #expect(RestartStandoff.decide(
            staged: staged("1.0.1", nil),
            onDiskShortVersion: "1.0.0", onDiskBuildVersion: "100")
            == .holdBack(stagedVersion: "1.0.1"))
    }
}
