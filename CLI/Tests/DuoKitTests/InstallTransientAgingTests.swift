import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// Splitting a vendor 5xx on the installer URL out of `installURLUnresolved` was
/// right — it stopped a working recipe filing issues against itself. But "not
/// actionable" was implemented as "never actionable", which recreated the failure
/// this whole sweep exists to end: an installer URL that 5xxs forever reported
/// `.ok` on every run and could never be seen by anyone. These pin both halves.
/// What the sweep actually writes into `Finding.warnings`: `ProbeWarning`
/// publishes `kind: detail`, and the detail is the status when there is one.
/// Building the fixtures from the production value rather than from the bare
/// kind is the whole point — the aging counter was matched with an exact element
/// comparison, so every 5xx (the Telegram case this exists for) was counted as a
/// sweep that RESOLVED the URL, and the run could never age.
private let transientShapes = [
    ProbeWarning.installURLTransient(status: 502).display,
    // The one shape that IS the bare kind: the request failed outright, so there
    // is no status to name.
    ProbeWarning.installURLTransient(status: nil).display,
]

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

    /// ⚠️ Runs over the shapes the sweep really produces, including the one with
    /// a status. `installURLTransient: HTTP 502` is what `td.telegram.org`'s
    /// bursts write, and an exact-element match against the bare kind counted
    /// every one of them as a sweep that RESOLVED the URL — so the run reset on
    /// each sweep, `consecutiveInstallTransient` never left 1, and the endpoint
    /// this counter exists for could 502 forever without ever being reportable.
    @Test(arguments: transientShapes)
    func aResolvedInstallURLEndsTheRun(shape: String) {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        for _ in 1...5 { _ = baseline.reconcile(finding(warnings: [shape])) }
        #expect(baseline.entries[id]?.consecutiveInstallTransient == 5)
        #expect(baseline.entries[id]?.installTransientSince != nil)

        _ = baseline.reconcile(finding(warnings: []))
        #expect(baseline.entries[id]?.consecutiveInstallTransient == 0)
        #expect(baseline.entries[id]?.installTransientSince == nil,
                "one good resolution means it was transient after all")
    }

    /// The end-to-end shape of the bug, on the exact warning the field's own doc
    /// names: five sweeps of 502 past the window must be reportable.
    @Test func aStatusCarryingTransientAgesIntoAReport() {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        let warning = ProbeWarning.installURLTransient(status: 502).display
        #expect(warning == "installURLTransient: HTTP 502")
        for _ in 1...5 { _ = baseline.reconcile(finding(warnings: [warning])) }

        let entry = baseline.entries[id] ?? Baseline.Entry()
        #expect(entry.isInstallTransientReportable(
            now: Date().addingTimeInterval(Baseline.infraWindow + 60)))
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
