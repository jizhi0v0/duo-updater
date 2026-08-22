import Testing
@testable import DuoUpdaterCore

struct RestartStandoffTests {

    /// The overwhelming common case: nobody else is holding an installer open.
    @Test func nothingStagedProceeds() {
        #expect(RestartStandoff.decide(
            stagedVersion: nil, onDiskVersion: "1.2.3") == .proceed)
    }

    /// TablePlus, 2026-08-22: Sparkle had 26.9.11 unpacked and an `Autoupdate`
    /// parked, and 26.9.11 was also what we were installing. Whoever writes
    /// second writes the same thing, so there is nothing to hold back for.
    @Test func aStagedBuildMatchingDiskProceeds() {
        #expect(RestartStandoff.decide(
            stagedVersion: "26.9.11", onDiskVersion: "26.9.11") == .proceed)
    }

    /// Regression, ChatGPT 2026-08-22: we installed 26.818.41705, Sparkle had
    /// 26.818.41509 staged since 14:53, and our restart handed it the quit it was
    /// waiting for. Note the staged build is OLDER — a check phrased as "is an
    /// update pending" would have found nothing to worry about here.
    @Test func anOlderStagedBuildHoldsBack() {
        #expect(RestartStandoff.decide(
            stagedVersion: "26.818.41509", onDiskVersion: "26.818.41705")
            == .holdBack(stagedVersion: "26.818.41509"))
    }

    /// The other direction is no safer: quitting would still replace what we just
    /// installed with something we did not choose.
    @Test func aNewerStagedBuildHoldsBack() {
        #expect(RestartStandoff.decide(
            stagedVersion: "2.0.0", onDiskVersion: "1.0.0")
            == .holdBack(stagedVersion: "2.0.0"))
    }

    /// "We could not read the bundle" is not "the versions agree".
    @Test func anUnreadableDiskVersionHoldsBack() {
        #expect(RestartStandoff.decide(
            stagedVersion: "1.0.0", onDiskVersion: nil)
            == .holdBack(stagedVersion: "1.0.0"))
    }
}
