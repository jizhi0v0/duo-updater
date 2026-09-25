import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

private func app(
    _ name: String, _ bundleID: String?, _ path: String, version: String = "1.0"
) -> InstalledApp {
    InstalledApp(
        name: name, bundleID: bundleID, shortVersion: version, buildVersion: "1",
        path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
}

private let installed = [
    app("Cursor", "com.todesktop.230313mzl4w4u92", "/Applications/Cursor.app"),
    app("HBuilderX", "com.dcloud.HBuilderX", "/Applications/HBuilderX.app"),
    app("HBuilderX-Alpha", "com.dcloud.HBuilderX", "/Applications/HBuilderX-Alpha.app"),
    app("Code", "com.microsoft.VSCode", "/Applications/Code.app"),
    // Two Xcodes: same name, same bundle id, same marketing version — only the
    // build and the path separate them. This is the case the listing has to serve.
    app("Xcode", "com.apple.dt.Xcode", "/Applications/Xcode-27b1.app",
        version: "27.0 (27A5194q)"),
    app("Xcode", "com.apple.dt.Xcode", "/Applications/Xcode-beta.app",
        version: "27.0 (27A5237l)"),
]

@Suite struct InventorySelectionTests {

    @Test func noArgumentsMeansEverything() throws {
        let selected = try Inventory.select(installed, matching: []).get()
        #expect(selected.count == installed.count)
    }

    @Test func anExactPathWins() throws {
        let selected = try Inventory.select(
            installed, matching: ["/Applications/HBuilderX-Alpha.app"]).get()
        #expect(selected.map(\.name) == ["HBuilderX-Alpha"])
    }

    /// A shared bundle id is not ambiguity — Thunderbird stable/esr and the
    /// Android Studio channels legitimately share one, and naming it means all
    /// of them.
    @Test func aSharedBundleIDSelectsEveryCopy() throws {
        let selected = try Inventory.select(installed, matching: ["com.dcloud.HBuilderX"]).get()
        #expect(Set(selected.map(\.name)) == ["HBuilderX", "HBuilderX-Alpha"])
    }

    @Test func anUnambiguousNamePrefixResolves() throws {
        #expect(try Inventory.select(installed, matching: ["curs"]).get().map(\.name) == ["Cursor"])
    }

    /// The important one: `duo install HBuilderX` must not pick a copy for you.
    @Test func anAmbiguousPrefixIsRefusedAndNamesTheCandidates() {
        let result = Inventory.select(installed, matching: ["HBuilderX"])
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("/Applications/HBuilderX.app"))
        #expect(failure.description.contains("/Applications/HBuilderX-Alpha.app"))
    }

    /// Two installs of the same app: the listing has to say something that tells
    /// them apart, and the advice has to be advice the user can act on — "name one
    /// exactly" matches both again.
    @Test func candidatesSharingANameAreSeparatedByVersionAndPath() {
        let result = Inventory.select(installed, matching: ["Xcode"])
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("Xcode 27.0 (27A5194q) — /Applications/Xcode-27b1.app"))
        #expect(failure.description.contains("Xcode 27.0 (27A5237l) — /Applications/Xcode-beta.app"))
        #expect(failure.description.contains("pass the path"))
        #expect(!failure.description.contains("Name one exactly"))
    }

    /// Different names, so naming one exactly IS the fix — the hint must not tell
    /// everyone to type a path.
    @Test func candidatesWithDistinctNamesAreToldToNameOne() {
        let result = Inventory.select(installed, matching: ["HBuilderX"])
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("Name one exactly"))
    }

    @Test func anUnknownNameIsAnError() {
        #expect(throws: Inventory.SelectionFailure.self) {
            try Inventory.select(installed, matching: ["nope"]).get()
        }
    }

    @Test func theSameAppNamedTwoWaysIsSelectedOnce() throws {
        let selected = try Inventory.select(
            installed, matching: ["/Applications/Cursor.app", "Cursor"]).get()
        #expect(selected.count == 1)
    }
}

/// The scan's timeout is the only thing standing between `duo list/check/install/
/// restart/backups/doctor/ignore` and a read that never returns. It was written
/// for the `open()` behind macOS's app-data gate, which never returned on a
/// headless runner; see `BoundedScan` for why that is no longer the known cause.
///
/// ⚠️ Written as a real wedge — a scan that never returns — because the shape of
/// the bug was that the timeout PRINTED on time and the command hung anyway.
/// `withTaskGroup` does not return until every child finishes and `cancelAll()`
/// cannot touch a thread parked in a syscall, so racing the scan against a sleep
/// inside a group measures nothing. A fixture whose scan eventually returns would
/// pass against either implementation.
@Suite struct InventoryScanTimeoutTests {

    /// Asserted as an ORDERING: the call must come back while the scan is still
    /// blocked. It used to bound the call's wall clock (`elapsed < 20`), which in
    /// practice could only go red on a slow machine: the regression it was meant to catch waited
    /// for a release that only came after the call returned, so it hung before the
    /// bound was ever read. (`givingUpDoesNotWaitForTheAbandonedOperation` in
    /// `AppRestarterTests` is the same test for `firstToFinish`, and its bound failed
    /// on CI at 15.477s with the property intact.)
    ///
    /// The scan cannot finish until it is released, and the only release before
    /// the call returns is the hang guard, so `scanFinishedFirst` is decided by
    /// the order of those two events, not by how fast the machine is. The guard
    /// exists so a regression fails in 30s instead of hanging the suite; for it
    /// to turn a correct implementation red, this task's resumption would have to
    /// still be waiting 30s after the timeout fired.
    ///
    /// Mutation: put the body of `BoundedScan.result` back in a `withTaskGroup` that
    /// races the scan against a sleep — red after the 30s guard, "the timeout did not
    /// abandon the scan".
    @Test func aScanThatNeverReturnsIsAbandonedAtTheTimeout() async {
        let release = DispatchSemaphore(value: 0)
        let scanFinishedFirst = Flag()
        // A `Task`, not a Dispatch timer, on purpose. A Dispatch timer fires on
        // schedule while the cooperative pool is stalled, so a 30s stall would
        // release the scan before this task got to read the flag, and the test would
        // go red with the property intact. A `Task` guard waits on the same pool,
        // behind this task's resumption, which was enqueued ~30s earlier. The cost:
        // under the regression the scan parks a pool thread, so on a machine with
        // almost no pool threads the guard might not run and the mutation would hang
        // rather than fail (not measured; it went red in 32s on 14 cores).
        let hangGuard = Task {
            try? await Task.sleep(for: .seconds(30))
            release.signal()
        }

        let scanned = await Inventory.scanIfFinished(timeout: .milliseconds(200), detection: .off) { _ in
            release.wait()
            scanFinishedFirst.set()
            return []
        }
        let waitedForTheScan = scanFinishedFirst.isSet
        // Released here so the thread cannot outlive the test.
        release.signal()
        hangGuard.cancel()

        #expect(scanned == nil)
        #expect(!waitedForTheScan, "the timeout did not abandon the scan")
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    /// Every command needs "gave up" apart from "found nothing": the first must not
    /// be reported as an empty Mac (`AbandonedScanOutputTests`).
    ///
    /// Mutation: have `scanIfFinished(timeout:_:)` return `[]` on a timeout.
    @Test func anAbandonedScanIsNilNotEmpty() async {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let abandoned = await Inventory.scanIfFinished(timeout: .milliseconds(200), detection: .off) { _ in
            release.wait()
            return []
        }
        #expect(abandoned == nil)

        let empty = await Inventory.scanIfFinished(timeout: BoundedScan.timeout, detection: .off) { _ in [] }
        #expect(empty?.isEmpty == true)
    }

    /// …and the ordinary case still hands back what the scan found, rather than
    /// the empty list the timeout produces.
    @Test func aScanThatFinishesIsReturned() async {
        let scanned = await Inventory.scanIfFinished(timeout: BoundedScan.timeout, detection: .off) { _ in installed }
        #expect(scanned?.map(\.name) == installed.map(\.name))
    }

    /// The sweep's copy of this primitive read only `components.seconds`, which
    /// floors any sub-second bound to "do not wait at all". Both callers pass
    /// whole seconds, so nothing in production would ever have shown it — but the
    /// two copies meant the same argument did different things depending on which
    /// one you reached, and now there is only one.
    ///
    /// Asserted as arithmetic rather than as elapsed time on purpose: a wall-clock
    /// bound in a parallel suite on a 3-core runner is not a measurement.
    ///
    /// Mutation: drop the attoseconds term.
    @Test func aSubSecondBoundIsNotFlooredToZero() {
        #expect(BoundedScan.seconds(.milliseconds(200)) == 0.2)
        #expect(BoundedScan.seconds(.seconds(20)) == 20)
        #expect(BoundedScan.seconds(BoundedScan.timeout) == 20)
    }
}

@Suite struct CheckRowTests {

    private func row(hasUpdate: Bool, hidden: Bool) -> Check.Row {
        Check.Row(
            name: "Fixture", bundleID: "com.example.fixture", path: "/Applications/Fixture.app",
            installedVersion: "1.0", installedBuild: "1",
            latestVersion: "1.0", source: "Vendor", status: "up-to-date",
            hasUpdate: hasUpdate, hidden: hidden, route: nil)
    }

    /// An up-to-date app still reports a `latestVersion`, so counting on that
    /// made `duo check --all` claim every checked app was an update — and made
    /// it exit 1 unconditionally.
    @Test func beingCurrentIsNotAnUpdate() {
        #expect(!Check.isActionable(row(hasUpdate: false, hidden: false)))
        #expect(Check.isActionable(row(hasUpdate: true, hidden: false)))
    }

    @Test func aHiddenUpdateIsNothingToDo() {
        #expect(!Check.isActionable(row(hasUpdate: true, hidden: true)))
    }

    private func result(_ status: UpdateStatus) -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "Fixture", bundleID: "com.example.fixture", shortVersion: "1.0",
                buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Fixture.app"),
                isMASApp: false, sparkleFeedURL: nil),
            remote: nil, status: status)
    }

    /// A failed check is listed without `--all`; nothing else that is not an
    /// update is. Mutation: drop the `.error` case from `showsByDefault` → red.
    @Test func aFailedCheckIsShownByDefault() {
        #expect(Check.showsByDefault(result(.error("HTTP 403"))))
        #expect(!Check.showsByDefault(result(.upToDate)))
        #expect(!Check.showsByDefault(result(.unknown)))
    }

    /// Muse, 2026-09-25: the only row was a failure and the run printed
    /// "Everything is up to date." The failure has to be on its line and in the
    /// summary, and — being nothing the user can act on — must not flip the exit
    /// status. Mutations: drop the "check failed" suffix; drop the summary clause.
    @Test func aFailedRowSaysWhyAndIsCountedApart() {
        let failed = Check.Row(
            name: "Muse", bundleID: "com.meta.endo", path: "/Applications/Muse.app",
            installedVersion: "2.2", installedBuild: "1074644564",
            latestVersion: nil, source: nil, status: Check.describe(.error("HTTP 403")),
            hasUpdate: false, hidden: false, route: nil)
        var out: [String] = []
        let status = Check.finish(
            [failed], command: "check", json: false, scanAbandoned: false, testFlightGap: nil,
            out: { out.append($0) }, err: { _ in })
        #expect(out.first == "  Muse  2.2  — check failed: HTTP 403")
        #expect(out.last == "\n  0 updates available of 1 app shown; 1 could not be checked.")
        #expect(!out.contains { $0.contains("up to date") })
        #expect(status == 0)
        #expect(Check.failure(row(hasUpdate: false, hidden: false)) == nil)
    }
}
