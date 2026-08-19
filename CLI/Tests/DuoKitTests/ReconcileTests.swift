import Testing
import Foundation
@testable import DuoKit

/// The reconcile step decides who gets notified and how often. Its failure mode
/// isn't a crash — it's a tracker so noisy that the one real breakage in it goes
/// unread. Every rule here is a volume control, and every one is pinned.
@Suite struct ReconcileTests {

    private func finding(
        _ id: String = "vendor:com.example.app:stable",
        status: FindingStatus, version: String? = nil,
        failureKind: String? = nil, warnings: [String] = []
    ) -> Finding {
        Finding(
            recipeID: id, registry: .vendor, bundleID: "com.example.app", channel: "stable",
            status: status, version: version, failureKind: failureKind,
            failureDetail: failureKind.map { "detail for \($0)" },
            warnings: warnings, endpointHost: "example.invalid", pattern: "([0-9.]+)")
    }

    private func entry(
        issue: Int? = nil, streak: Int = 0, signature: String? = nil,
        closedAt: Date? = nil, sweepsSinceComment: Int = 0, commentedDaysAgo: Double? = nil,
        lastGood: String? = nil,
        infra: Int = 0, infraDays: Double? = nil
    ) -> Baseline.Entry {
        var e = Baseline.Entry()
        e.issueNumber = issue
        e.consecutiveActionable = streak
        e.lastSignature = signature
        e.closedAt = closedAt
        e.sweepsSinceComment = sweepsSinceComment
        e.lastCommentedAt = commentedDaysAgo.map { Date(timeIntervalSinceNow: -$0 * 86_400) }
        e.lastGoodVersion = lastGood
        e.consecutiveInfra = infra
        // The gate is wall-clock now, so the age of the run matters, not just how
        // many sweeps saw it. Default to one day per sweep — the old cadence —
        // unless a test needs the two to disagree.
        if infra > 0 {
            e.infraSince = Date(timeIntervalSinceNow: -(infraDays ?? Double(infra)) * 86_400)
        }
        return e
    }

    // MARK: - what never files

    /// The single most important rule. A sweep that opens issues for dropped
    /// connections gets muted within a week, and then it catches nothing. Note
    /// `reportable: true` here — the actionable streak must not smuggle an infra
    /// finding past this gate.
    @Test func infrastructureTroubleNeverFilesAnything() {
        for status in [FindingStatus.infra, .skipped] {
            let action = Reconcile.decide(
                finding(status: status), entry: entry(), reportable: true)
            #expect(!action.isWrite, "\(status.rawValue) must never write to GitHub")
        }
    }

    /// …with exactly one exception, and it is the reason the exception exists: a
    /// host that answers on no sweep for the better part of a week has been
    /// retired, not congested. Before this, a vendor deleting a DNS record was
    /// the one kind of total breakage the sweep could never see.
    @Test func anEndpointUnreachableForAWeekIsReported() {
        let action = Reconcile.decide(
            finding(status: .infra, failureKind: "transport"),
            entry: entry(infra: 6, infraDays: 6), reportable: false)
        guard case .create(let title, let body) = action else {
            Issue.record("expected an issue to be created, got \(action)")
            return
        }
        #expect(title.contains("unreachable"))
        #expect(title.contains("example.invalid"))
        // The fix is never in the regex, so the body must not send anyone there.
        #expect(!title.contains("Recipe broken"))
        #expect(body.contains("dig +short example.invalid"))
    }

    /// `skipped` never files no matter how long it persists: credential-bearing
    /// recipes are skipped on every single sweep by design, and reporting those
    /// as dead hosts would file an issue for each one within a week.
    @Test func skippedNeverFilesHoweverLongItPersists() {
        let action = Reconcile.decide(
            finding(status: .skipped), entry: entry(infra: 40, infraDays: 40),
            reportable: true)
        #expect(!action.isWrite)
    }

    /// Below the threshold it stays silent, and says why.
    @Test func aBriefOutageIsCountedButNotFiled() {
        let action = Reconcile.decide(
            finding(status: .infra, failureKind: "transport"),
            entry: entry(infra: 4, infraDays: 4), reportable: true)
        #expect(!action.isWrite)
        if case .none(let reason) = action {
            #expect(reason.contains("4 days of 5 days"))
        } else {
            Issue.record("expected no action")
        }
    }

    /// A dead host has no shape to change, so it must not take the
    /// "failure changed shape" path — transport errors flap between "no route"
    /// and "TLS failed" for reasons that mean nothing, and each flap would be a
    /// comment. It goes through the ordinary every-Nth-sweep nudge instead.
    @Test func aStillDeadHostIsRateLimitedNotRecommentedOnEveryFlap() {
        let quiet = Reconcile.decide(
            finding(status: .infra, failureKind: "tlsFailure"),
            entry: entry(issue: 7, signature: "transport",
                         sweepsSinceComment: 1, commentedDaysAgo: 1,
                         infra: 8, infraDays: 8),
            reportable: true)
        #expect(!quiet.isWrite, "a changed transport error is not news")

        let nudge = Reconcile.decide(
            finding(status: .infra, failureKind: "tlsFailure"),
            entry: entry(issue: 7, signature: "transport",
                         sweepsSinceComment: 9, commentedDaysAgo: 8,
                         infra: 8, infraDays: 8),
            reportable: true)
        guard case .comment(let issue, let body) = nudge else {
            Issue.record("expected a nudge comment, got \(nudge)")
            return
        }
        #expect(issue == 7)
        #expect(body.contains("still unreachable"))
    }

    /// The healing path is shared: once the host answers again the finding is no
    /// longer `infra`, and the ordinary `ok` branch closes the issue.
    @Test func anEndpointThatComesBackClosesItsIssue() {
        let action = Reconcile.decide(
            finding(status: .ok, version: "1.7.9"),
            entry: entry(issue: 7, infra: 0), reportable: false)
        guard case .close(let issue, _) = action else {
            Issue.record("expected a close, got \(action)")
            return
        }
        #expect(issue == 7)
    }

    /// One bad sweep is information, not a verdict. Vendors have brief outages;
    /// issues are forever.
    @Test func aFirstBadSweepIsCountedButNotFiled() {
        let action = Reconcile.decide(
            finding(status: .broken, failureKind: "versionPatternNoMatch"),
            entry: entry(streak: 1), reportable: false)
        #expect(!action.isWrite)
        if case .none(let reason) = action {
            #expect(reason.contains("1/\(Baseline.actionableThreshold)"))
        } else {
            Issue.record("expected no action")
        }
    }

    // MARK: - opening

    @Test func aRecipeBrokenTwiceOpensOneIssue() throws {
        let action = Reconcile.decide(
            finding(status: .broken, failureKind: "versionPatternNoMatch"),
            entry: entry(streak: 2), reportable: true)
        guard case .create(let title, let body) = action else {
            Issue.record("expected an issue to be created, got \(action)")
            return
        }
        #expect(title.contains("com.example.app"))
        #expect(title.contains("Recipe broken"))
        // The marker is what lets an issue be re-associated with its recipe if
        // the baseline file is ever lost or rewritten.
        #expect(body.contains("<!-- duo-verify-id: vendor:com.example.app:stable -->"))
        // And the body has to tell you how to reproduce, or it's a bug report
        // with no repro steps.
        #expect(body.contains("duo verify --vendor --only com.example.app"))
    }

    /// A *degraded* recipe is worth an issue too, and this is not academic:
    /// `installURLUnresolved` is how both real one-click failures — Outlook and
    /// Signal Beta — were found, and neither ever produced a `broken`.
    @Test func aDegradedRecipeOpensAnIssueToo() {
        let action = Reconcile.decide(
            finding(status: .warn, version: "1.2.3", warnings: ["installURLUnresolved"]),
            entry: entry(streak: 2), reportable: true)
        guard case .create(let title, _) = action else {
            Issue.record("expected an issue, got \(action)")
            return
        }
        #expect(title.contains("Recipe degraded"))
    }

    // MARK: - not repeating yourself

    /// A job that comments every run is a notification saying nothing new. The
    /// issue is already open; silence is the correct output. Counted in days now,
    /// so the answer does not change when the sweep interval does.
    @Test func anUnchangedFailureStaysQuietBetweenNudges() {
        for daysAgo in [0.0, 0.25, 1, 3, 6.9] {
            let action = Reconcile.decide(
                finding(status: .broken, failureKind: "versionPatternNoMatch"),
                entry: entry(issue: 7, streak: 5, signature: "versionPatternNoMatch",
                             commentedDaysAgo: daysAgo),
                reportable: true)
            #expect(!action.isWrite, "should stay silent \(daysAgo) days after the last nudge")
        }
    }

    /// The whole point of the timestamp: the quiet period is the same length
    /// however many sweeps happen inside it.
    @Test func theNudgeIntervalDoesNotMoveWithTheSweepCadence() {
        for sweepsInside in [7, 28] {
            let action = Reconcile.decide(
                finding(status: .broken, failureKind: "versionPatternNoMatch"),
                entry: entry(issue: 7, streak: 5, signature: "versionPatternNoMatch",
                             sweepsSinceComment: sweepsInside, commentedDaysAgo: 3),
                reportable: true)
            #expect(!action.isWrite,
                    "three days is three days, whether that was \(sweepsInside) sweeps")
        }
    }

    @Test func aLongRunningFailureGetsAnOccasionalNudge() {
        let action = Reconcile.decide(
            finding(status: .broken, failureKind: "versionPatternNoMatch"),
            entry: entry(issue: 7, streak: 9, signature: "versionPatternNoMatch",
                         sweepsSinceComment: 9, commentedDaysAgo: 8),
            reportable: true)
        guard case .comment(let issue, _) = action else {
            Issue.record("expected a nudge, got \(action)")
            return
        }
        #expect(issue == 7)
    }

    /// A failure that changes shape is new information and shouldn't wait for the
    /// nudge cycle — "the regex stopped matching" becoming "the endpoint 404s"
    /// changes what the fix is.
    @Test func aFailureChangingShapeIsReportedImmediately() {
        let action = Reconcile.decide(
            finding(status: .broken, failureKind: "httpStatus404"),
            entry: entry(issue: 7, streak: 3, signature: "versionPatternNoMatch",
                         sweepsSinceComment: 1),
            reportable: true)
        guard case .comment(_, let body) = action else {
            Issue.record("expected an immediate comment, got \(action)")
            return
        }
        #expect(body.contains("changed shape"))
        #expect(body.contains("versionPatternNoMatch"))
        #expect(body.contains("httpStatus404"))
    }

    // MARK: - healing

    @Test func aHealedRecipeClosesItsIssue() {
        let action = Reconcile.decide(
            finding(status: .ok, version: "2.0.0"),
            entry: entry(issue: 7, streak: 0, lastGood: "1.9.0"), reportable: false)
        guard case .close(let issue, let comment) = action else {
            Issue.record("expected a close, got \(action)")
            return
        }
        #expect(issue == 7)
        #expect(comment.contains("2.0.0"))
    }

    @Test func aHealthyRecipeWithNoIssueDoesNothing() {
        let action = Reconcile.decide(
            finding(status: .ok, version: "2.0.0"), entry: entry(), reportable: false)
        #expect(!action.isWrite)
    }

    /// Breaking again soon after healing is the same episode; a second issue
    /// about it would split the history in two.
    @Test func aQuickRelapseReopensRatherThanDuplicating() {
        let closed = Date().addingTimeInterval(-3 * 86_400)
        let action = Reconcile.decide(
            finding(status: .broken, failureKind: "versionPatternNoMatch"),
            entry: entry(issue: 7, streak: 2, closedAt: closed), reportable: true)
        guard case .reopen(let issue, let comment) = action else {
            Issue.record("expected a reopen, got \(action)")
            return
        }
        #expect(issue == 7)
        #expect(comment.contains("Broke again"))
    }

    /// …but a relapse months later is a new episode, and reopening a stale issue
    /// would bury the new context under old discussion.
    @Test func aLateRelapseOpensAFreshIssue() {
        let closed = Date().addingTimeInterval(-60 * 86_400)
        let action = Reconcile.decide(
            finding(status: .broken, failureKind: "versionPatternNoMatch"),
            entry: entry(issue: 7, streak: 2, closedAt: closed), reportable: true)
        guard case .create = action else {
            Issue.record("expected a fresh issue, got \(action)")
            return
        }
    }

    // MARK: - the signature that drives all of the above

    /// Warning text embeds versions that change every sweep. If the signature
    /// changed with them, every sweep would look like "the failure changed
    /// shape" and comment immediately — the exact spam this is built to avoid.
    @Test func aWarningSignatureIsStableAcrossVersionChanges() {
        let monday = finding(
            status: .warn, version: "1.0.0",
            warnings: ["remote is BEHIND the installed copy (1.0.0 < 1.2.0) — the recipe may…"])
        let tuesday = finding(
            status: .warn, version: "1.0.1",
            warnings: ["remote is BEHIND the installed copy (1.0.1 < 1.2.1) — the recipe may…"])
        #expect(monday.signature == tuesday.signature)
    }

    @Test func differentProblemsHaveDifferentSignatures() {
        let a = finding(status: .broken, failureKind: "versionPatternNoMatch")
        let b = finding(status: .broken, failureKind: "httpStatus404")
        #expect(a.signature != b.signature)
    }
}
