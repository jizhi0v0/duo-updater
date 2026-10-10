import Testing
import DuoUpdaterCore

@testable import DuoKit

/// The changelog lag check against a beta probe that is resting on the
/// graduated stable between cycles (`Verify.probeRestsOffChannel`). Carbon Copy
/// Cloner's `?v=latestbeta` does exactly that, while `ccc7_rn_beta.html` stays on
/// the closed cycle's last prerelease. The pairs are the real ones: `7.1.7-b7`
/// graduated to `7.2` in September 2026, and `7.2.2-b4` was the open cycle on
/// 2026-10-10.
struct ChangelogLagOffChannelTests {
    private func recipe(_ channel: ReleaseChannel, _ version: String) throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.bombich.ccc", channel: channel, version: version))
    }

    @Test func aBetaPageIsNotJudgedAgainstTheStableTheBetaProbeRestsOn() throws {
        let beta = try recipe(.beta, "7.2.2-b4")
        // A minor-bump graduation: before the skip this warned every sweep.
        #expect(Verify.changelogLagWarning(beta, entry: "7.2.2-b4", detected: "7.3.0") == nil)
        #expect(Verify.changelogLagWarning(beta, entry: "7.1.7-b7", detected: "7.2") == nil)
        // Same-minor graduation, never warned.
        #expect(Verify.changelogLagWarning(beta, entry: "7.2.2-b4", detected: "7.2.2") == nil)
    }

    @Test func aBetaPageBehindABetaAnswerStillWarns() throws {
        let beta = try recipe(.beta, "7.3.0-b1")
        // The probe is on the beta train and the page is a cycle behind: stale.
        #expect(Verify.changelogLagWarning(beta, entry: "7.1.7-b7", detected: "7.3.0-b1") != nil)
    }

    @Test func aStableRecipeIsJudgedAsBefore() throws {
        let stable = try recipe(.stable, "7.2.1")
        #expect(Verify.probeRestsOffChannel(stable, entry: "7.0", detected: "7.2.1") == false)
        #expect(Verify.changelogLagWarning(stable, entry: "7.0", detected: "7.2.1") != nil)
    }
}
