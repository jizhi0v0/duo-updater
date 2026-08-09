import Testing
import Foundation
@testable import DuoKit

/// The baseline is the only part of the verifier that remembers anything, which
/// makes it the only part that can distinguish "broken" from "broken twice" and
/// "reads a version" from "reads a version that went backwards". Both of those
/// decisions gate whether a human gets paged, so both are pinned here.
@Suite struct BaselineTests {

    private func finding(
        _ id: String = "vendor:com.example.app:stable",
        status: FindingStatus, version: String? = nil, failureKind: String? = nil
    ) -> Finding {
        Finding(
            recipeID: id, registry: .vendor, bundleID: "com.example.app", channel: "stable",
            status: status, version: version, failureKind: failureKind,
            endpointHost: "example.invalid")
    }

    /// One bad sweep files nothing. Vendors have five-minute outages; issues are
    /// forever, and an issue tracker that cries wolf gets muted.
    @Test func aSingleFailureIsNotYetReportable() {
        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        #expect(baseline.streak("vendor:com.example.app:stable") == 1)
        #expect(!baseline.isReportable("vendor:com.example.app:stable"))

        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        #expect(baseline.isReportable("vendor:com.example.app:stable"))
    }

    /// Recovery clears the streak, so a recipe that heals stops being reported
    /// without anyone touching the state by hand.
    @Test func aSuccessfulSweepClearsTheFailureStreak() {
        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .broken, failureKind: "httpStatus404"))
        _ = baseline.reconcile(finding(status: .broken, failureKind: "httpStatus404"))
        #expect(baseline.isReportable("vendor:com.example.app:stable"))

        _ = baseline.reconcile(finding(status: .ok, version: "1.2.3"))
        #expect(baseline.streak("vendor:com.example.app:stable") == 0)
        #expect(!baseline.isReportable("vendor:com.example.app:stable"))
    }

    /// Infrastructure trouble must be inert in both directions: it can't push a
    /// recipe over the threshold, and it can't reset a real failure streak that
    /// is still running. Getting the second half wrong would make a genuinely
    /// broken recipe unreportable forever on a flaky network.
    @Test func infraOutcomesNeitherAccumulateNorResetTheStreak() {
        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .infra))
        _ = baseline.reconcile(finding(status: .infra))
        _ = baseline.reconcile(finding(status: .infra))
        #expect(baseline.streak("vendor:com.example.app:stable") == 0)

        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        _ = baseline.reconcile(finding(status: .infra))
        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        #expect(baseline.streak("vendor:com.example.app:stable") == 2)
    }

    /// A version going backwards is the fingerprint of a pattern that started
    /// matching a different, shorter thing on the page. Nothing else detects it:
    /// the answer is well-formed, the fetch succeeded, and in isolation it looks
    /// completely healthy.
    @Test func aVersionGoingBackwardsIsFlagged() {
        var baseline = Baseline()
        #expect(baseline.reconcile(finding(status: .ok, version: "4.7.9")) == nil)

        let complaint = baseline.reconcile(finding(status: .ok, version: "4.7"))
        #expect(complaint?.contains("BACKWARDS") == true)
        #expect(complaint?.contains("4.7.9") == true)
    }

    @Test func movingForwardOrStandingStillIsNotFlagged() {
        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .ok, version: "4.7.9"))
        #expect(baseline.reconcile(finding(status: .ok, version: "4.8.0")) == nil)
        #expect(baseline.reconcile(finding(status: .ok, version: "4.8.0")) == nil)
    }

    @Test func baselineRoundTripsThroughDisk() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-baseline-\(UUID().uuidString)/baseline.json")
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }

        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .ok, version: "1.0.0"))
        _ = baseline.reconcile(finding(status: .broken, failureKind: "httpStatus404"))
        baseline.entries["vendor:com.example.app:stable"]?.issueNumber = 42
        try baseline.save(to: path)

        let reloaded = Baseline.load(from: path)
        let entry = try #require(reloaded.entries["vendor:com.example.app:stable"])
        #expect(entry.lastGoodVersion == "1.0.0")
        #expect(entry.consecutiveActionable == 1)
        #expect(entry.issueNumber == 42)
    }

    /// A missing or corrupt baseline must degrade to "no history", never crash a
    /// scheduled run.
    @Test func aMissingBaselineIsEmptyRatherThanFatal() {
        let missing = Baseline.load(
            from: URL(fileURLWithPath: "/nonexistent/duo/baseline.json"))
        #expect(missing.entries.isEmpty)
    }
}

/// The noise filters. Every one of these exists because its absence produced a
/// false positive on a real sweep — an issue tracker full of correct behaviour
/// is worse than no tracker at all.
@Suite struct NoiseFilterTests {

    /// JetBrains keys release notes to the major version (`2026.2`) while the
    /// probe reads the build (`2026.2.0.1`); Toolbox publishes marketing versions
    /// against build-numbered installs. Comparing full strings flagged six
    /// recipes, five of which were working exactly as designed.
    @Test func ordinaryChangelogLagIsNotFlagged() {
        let ordinary = [
            ("2026.2", "2026.2.0.1"),           // IntelliJ: notes are per-major
            ("3.6.4", "3.6.4.86641"),           // Toolbox: marketing vs build
            ("262.132.29", "262.132.34"),       // Air: one patch behind
            ("0.2026.08.05.09.03", "0.2026.08.05.09.03.01"),
        ]
        for (entry, detected) in ordinary {
            #expect(
                Verify.changelogLagComplaint(entry: entry, detected: detected) == nil,
                "\(entry) vs \(detected) should be treated as normal lag")
        }
    }

    /// Recipes whose vendor doesn't number releases capture a headline into the
    /// version group on purpose. Comparing a sentence to a version number
    /// produces confident nonsense.
    @Test func changelogTitlesAreNotComparedAsVersions() {
        #expect(Verify.changelogLagComplaint(
            entry: "AI credit user limits and credit requests", detected: "126.7.10") == nil)
        #expect(Verify.changelogLagComplaint(
            entry: "Share context with Custom Agents", detected: "7.29.0") == nil)
    }

    /// …but a changelog a whole release behind still is.
    @Test func aChangelogAWholeReleaseBehindIsFlagged() {
        let complaint = Verify.changelogLagComplaint(entry: "26.727", detected: "26.803.41515")
        #expect(complaint?.contains("trails") == true)
    }
}
