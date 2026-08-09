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
        closedAt: Date? = nil, sweepsSinceComment: Int = 0, lastGood: String? = nil
    ) -> Baseline.Entry {
        var e = Baseline.Entry()
        e.issueNumber = issue
        e.consecutiveActionable = streak
        e.lastSignature = signature
        e.closedAt = closedAt
        e.sweepsSinceComment = sweepsSinceComment
        e.lastGoodVersion = lastGood
        return e
    }

    // MARK: - what never files

    /// The single most important rule. A sweep that opens issues for dropped
    /// connections gets muted within a week, and then it catches nothing.
    @Test func infrastructureTroubleNeverFilesAnything() {
        for status in [FindingStatus.infra, .skipped] {
            let action = Reconcile.decide(
                finding(status: status), entry: entry(), reportable: true)
            #expect(!action.isWrite, "\(status.rawValue) must never write to GitHub")
        }
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

    /// A daily job that comments daily is a daily notification saying nothing
    /// new. The issue is already open; silence is the correct output.
    @Test func anUnchangedFailureStaysQuietBetweenNudges() {
        for sweeps in 0..<Reconcile.commentEverySweeps {
            let action = Reconcile.decide(
                finding(status: .broken, failureKind: "versionPatternNoMatch"),
                entry: entry(issue: 7, streak: 5, signature: "versionPatternNoMatch",
                             sweepsSinceComment: sweeps),
                reportable: true)
            #expect(!action.isWrite, "should stay silent at \(sweeps) sweeps since last comment")
        }
    }

    @Test func aLongRunningFailureGetsAnOccasionalNudge() {
        let action = Reconcile.decide(
            finding(status: .broken, failureKind: "versionPatternNoMatch"),
            entry: entry(issue: 7, streak: 9, signature: "versionPatternNoMatch",
                         sweepsSinceComment: Reconcile.commentEverySweeps),
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
