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

    /// Infrastructure trouble must be inert against the *actionable* streak in
    /// both directions: it can't push a recipe over the threshold, and it can't
    /// reset a real failure streak that is still running. Getting the second half
    /// wrong would make a genuinely broken recipe unreportable forever on a flaky
    /// network.
    @Test func infraOutcomesNeitherAccumulateNorResetTheActionableStreak() {
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

    /// …but it is no longer inert against everything. A host that answers on no
    /// sweep at all, night after night, has been retired, and before this counter
    /// existed that case changed no state and so was invisible forever — the
    /// exact silent degradation the sweep was built to end.
    @Test func unreachabilityAccumulatesOnItsOwnCounter() {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        let start = Date()
        for _ in 1...6 {
            _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
        }
        // Enough sweeps, but the run is minutes old: still the network.
        #expect(!baseline.isInfraReportable(id, now: start.addingTimeInterval(3_600)),
                "a few bad sweeps in an hour is still the network")

        // Same sweeps, now five days in.
        let later = start.addingTimeInterval(Baseline.infraWindow + 60)
        #expect(baseline.isInfraReportable(id, now: later))
        #expect(baseline.infraStreak(id) == 6)
        #expect(baseline.entries[id]?.infraSince != nil)
    }

    /// The gate is wall-clock, but wall-clock alone breaks in the one case where
    /// the *sweep* is what stopped: after a week of downtime the first sweep back
    /// records `infraSince`, and the second — minutes later — would otherwise
    /// satisfy an elapsed-time test against a timestamp that is already days old.
    /// Two observations must never retire a host.
    @Test func aLongGapBetweenSweepsDoesNotRetireAHostOnTwoObservations() {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        let start = Date()
        for _ in 1...2 {
            _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
        }
        let wayLater = start.addingTimeInterval(Baseline.infraWindow * 2)
        #expect(!baseline.isInfraReportable(id, now: wayLater),
                "two sweeps is not evidence, however old the first one is")

        _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
        #expect(baseline.isInfraReportable(id, now: wayLater),
                "the third observation clears the minimum")
    }

    /// The point of the change: the gate no longer moves when the sweep cadence
    /// does. The same five days of downtime reports either way, whether it was
    /// observed nightly or four times a day.
    @Test func theGateDoesNotMoveWithTheSweepCadence() {
        let start = Date()
        let later = start.addingTimeInterval(Baseline.infraWindow + 60)
        for sweepsOverTheWindow in [5, 20] {
            var baseline = Baseline()
            for _ in 1...sweepsOverTheWindow {
                _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
            }
            #expect(baseline.isInfraReportable("vendor:com.example.app:stable", now: later),
                    "\(sweepsOverTheWindow) sweeps across the same five days must report")
        }
    }

    /// Any answer at all — even a broken one — is proof the host is still there,
    /// so it clears the unreachable streak. Without this a recipe that failed to
    /// parse once every few nights would eventually be reported as a dead host.
    @Test func reachingTheHostAtAllClearsTheUnreachableStreak() {
        let id = "vendor:com.example.app:stable"
        for reachable in [FindingStatus.ok, .broken, .warn] {
            var baseline = Baseline()
            let start = Date()
            let later = start.addingTimeInterval(Baseline.infraWindow + 60)
            for _ in 1...6 {
                _ = baseline.reconcile(finding(status: .infra))
            }
            #expect(baseline.isInfraReportable(id, now: later))

            _ = baseline.reconcile(finding(status: reachable, version: "1.0.0",
                                           failureKind: "versionPatternNoMatch"))
            #expect(!baseline.isInfraReportable(id, now: later),
                    "\(reachable.rawValue) proves the host is up")
            #expect(baseline.infraStreak(id) == 0)
            #expect(baseline.entries[id]?.infraSince == nil)
        }
    }

    /// `skipped` means we never looked, which is not evidence of anything. A
    /// credential-bearing recipe is skipped on every single sweep, so counting
    /// those would report every one of them as a dead host within a week.
    @Test func skippedSweepsAreNotEvidenceOfADeadHost() {
        var baseline = Baseline()
        for _ in 1...60 {
            _ = baseline.reconcile(finding(status: .skipped))
        }
        #expect(baseline.infraStreak("vendor:com.example.app:stable") == 0)
        #expect(!baseline.isInfraReportable("vendor:com.example.app:stable",
                                            now: Date().addingTimeInterval(Baseline.infraWindow * 3)))
    }

    /// An unreachable sweep in the middle of a broken streak must not make the
    /// next broken sweep look like the failure "changed shape" — that comparison
    /// drives a comment, and a comment per network blip is the noise this whole
    /// design exists to avoid.
    @Test func anInfraSweepDoesNotDisturbTheActionableSignature() {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        let signature = baseline.entries[id]?.lastSignature
        _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
        #expect(baseline.entries[id]?.lastSignature == signature)
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
        let complaint = Verify.changelogLagComplaint(entry: "1.85", detected: "1.123.4")
        #expect(complaint?.contains("trails") == true)
    }

    /// Codex numbers builds and notes alike as `YY.MDD`, so the date lands in the
    /// slot the major.minor comparison uses and one publishing cycle looks like a
    /// whole release. 26.727 → 26.803 is seven days: their notes come out weekly.
    @Test func aDateNumberedChangelogIsJudgedInDaysNotReleases() {
        #expect(Verify.changelogLagComplaint(entry: "26.727", detected: "26.803.41515") == nil)
        #expect(Verify.changelogLagComplaint(entry: "25.1215", detected: "26.103") == nil)
        // Only a gap no publishing cadence explains still counts.
        let complaint = Verify.changelogLagComplaint(entry: "26.115", detected: "26.803.41515")
        #expect(complaint?.contains("200 days") == true)
    }

    /// The date reading has to be sure of itself: a two-digit major with a
    /// three-digit minor is not a date when the minor is not a valid `MDD`.
    @Test func versionsThatOnlyLookLikeDatesAreNotReadAsDates() {
        #expect(Verify.buildDate("26.803") != nil)
        #expect(Verify.buildDate("26.1215") != nil)
        #expect(Verify.buildDate("26.099") == nil)     // month 0
        #expect(Verify.buildDate("26.1332") == nil)    // month 13
        #expect(Verify.buildDate("26.845") == nil)     // day 45
        #expect(Verify.buildDate("2026.2") == nil)     // JetBrains major.minor
        #expect(Verify.buildDate("3.6.4") == nil)
    }
}
