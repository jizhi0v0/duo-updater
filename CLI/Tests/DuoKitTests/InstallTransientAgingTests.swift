import Testing
import Foundation
@testable import DuoKit

/// Splitting a vendor 5xx on the installer URL out of `installURLUnresolved` was
/// right — it stopped a working recipe filing issues against itself. But "not
/// actionable" was implemented as "never actionable", which recreated the failure
/// this whole sweep exists to end: an installer URL that 5xxs forever reported
/// `.ok` on every run and could never be seen by anyone. These pin both halves.
struct InstallTransientAgingTests {

    private let transientKind = "installURLTransient"

    private func entry(sweeps: Int, daysAgo: Double?, issue: Int? = nil) -> Baseline.Entry {
        var e = Baseline.Entry()
        e.consecutiveInstallTransient = sweeps
        e.installTransientSince = daysAgo.map { Date(timeIntervalSinceNow: -$0 * 86_400) }
        e.issueNumber = issue
        e.lastCommentedAt = issue.map { _ in Date(timeIntervalSinceNow: -30 * 86_400) }
        return e
    }

    private func finding(warnings: [String]) -> Finding {
        Finding(
            recipeID: "vendor:com.example.app:stable", registry: .vendor,
            bundleID: "com.example.app", channel: "stable",
            status: .ok, version: "1.2.3", failureKind: nil, failureDetail: nil,
            warnings: warnings, endpointHost: "example.invalid", pattern: "([0-9.]+)")
    }

    @Test func aBriefOutageStaysSilent() {
        // The Telegram case: bursts of 502 lasting minutes. Nothing should be filed.
        let action = Reconcile.decide(
            finding(warnings: [transientKind]),
            entry: entry(sweeps: 2, daysAgo: 0.5), reportable: false)
        #expect(!action.isWrite)
    }

    @Test func aPermanentlyFailingInstallURLIsEventuallyReported() {
        // The hole: before this, an endpoint could 5xx forever and stay `.ok`.
        let action = Reconcile.decide(
            finding(warnings: [transientKind]),
            entry: entry(sweeps: 20, daysAgo: 6), reportable: false)
        guard case .create(let title, let body) = action else {
            Issue.record("expected an issue, got \(action)"); return
        }
        #expect(title.contains("One-click broken"))
        // It must not read as a pattern problem — the pattern is fine.
        #expect(body.contains("Detection still works"))
    }

    @Test func timeAloneIsNotEnough() {
        // If the sweep itself stopped for a week, the first two runs back must not
        // retire an endpoint on a timestamp that is already old.
        let action = Reconcile.decide(
            finding(warnings: [transientKind]),
            entry: entry(sweeps: 2, daysAgo: 30), reportable: false)
        #expect(!action.isWrite)
    }

    @Test func sweepsAloneAreNotEnough() {
        let action = Reconcile.decide(
            finding(warnings: [transientKind]),
            entry: entry(sweeps: 50, daysAgo: 0.2), reportable: false)
        #expect(!action.isWrite)
    }

    @Test func aResolvedInstallURLEndsTheRun() {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        for _ in 1...5 { _ = baseline.reconcile(finding(warnings: [transientKind])) }
        #expect(baseline.entries[id]?.consecutiveInstallTransient == 5)
        #expect(baseline.entries[id]?.installTransientSince != nil)

        _ = baseline.reconcile(finding(warnings: []))
        #expect(baseline.entries[id]?.consecutiveInstallTransient == 0)
        #expect(baseline.entries[id]?.installTransientSince == nil,
                "one good resolution means it was transient after all")
    }

    @Test func theGateIsWallClockNotSweepCount() {
        var e = Baseline.Entry()
        e.consecutiveInstallTransient = Baseline.minInfraObservations
        let start = Date()
        e.installTransientSince = start
        #expect(!e.isInstallTransientReportable(now: start.addingTimeInterval(3_600)))
        #expect(e.isInstallTransientReportable(
            now: start.addingTimeInterval(Baseline.infraWindow + 60)))
    }
}
