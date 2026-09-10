import Testing
import Foundation
@testable import DuoUpdaterCore

/// The decision table of `TestFlightRefresh`, with every effect injected so no
/// case launches anything or waits on a real clock.
///
/// What the cases are *for* is the measurement behind each branch: a refresh runs
/// in an instance **we** start and end, because reaching the user's own instance
/// would mean activating it and activation takes the foreground; and the wait has
/// to end on the store actually changing rather than on a guess about how long a
/// sync takes.
struct TestFlightRefreshTests {

    /// Records what the effects were asked to do, so a case can assert on the
    /// things that did NOT happen — which is most of this type's contract.
    private final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var launches: [URL] = []
        private(set) var terminated: [pid_t] = []
        private(set) var sleeps = 0
        func launched(_ url: URL) {
            lock.lock(); defer { lock.unlock() }
            launches.append(url)
        }
        func terminatedInstance(_ pid: pid_t) {
            lock.lock(); defer { lock.unlock() }
            terminated.append(pid)
        }
        func slept() {
            lock.lock(); defer { lock.unlock() }
            sleeps += 1
        }
    }

    private static let bundle = URL(fileURLWithPath: "/Applications/TestFlight.app")

    /// A stamp source that changes after `changesAfter` reads, standing in for the
    /// store being rewritten partway through the wait.
    private final class Stamp: @unchecked Sendable {
        private let lock = NSLock()
        private var reads = 0
        /// Read numbers at which the store is rewritten. Production is not one
        /// change but a burst then a pause: measured +0.3s, +1s, +2s, +2s, **+7s**.
        private let changesAt: Set<Int>
        init(changesAt: Set<Int> = []) { self.changesAt = changesAt }
        func read() -> Date? {
            lock.lock(); defer { lock.unlock() }
            reads += 1
            let bumps = changesAt.filter { $0 <= reads }.count
            return Date(timeIntervalSince1970: Double(bumps))
        }
    }

    /// A distinctive pid so a case can tell "the one we were handed" from "some
    /// pid": the whole point of terminating by pid is that it is *ours* and not the
    /// user's instance.
    private static let spawnedPID: pid_t = 4242

    private static func refresher(
        installed: Bool = true,
        launchSucceeds: Bool = true,
        stamp: Stamp = Stamp(),
        spy: Spy
    ) -> TestFlightRefresh {
        TestFlightRefresh(
            locate: { installed ? bundle : nil },
            spawn: { url in
                spy.launched(url)
                return launchSucceeds ? spawnedPID : nil
            },
            terminate: { spy.terminatedInstance($0) },
            storeStamp: { stamp.read() },
            sleep: { _ in spy.slept() })
    }

    /// Mutation: return `.launchFailed` (or `.notInstalled`) unconditionally when
    /// the bundle is missing — the point is that a Mac without TestFlight is not a
    /// failure to report as one, and nothing is launched.
    @Test func aMacWithoutTestFlightSaysSoAndLaunchesNothing() async {
        let spy = Spy()
        let outcome = await Self.refresher(installed: false, spy: spy).run()
        #expect(outcome == .notInstalled)
        #expect(spy.launches.isEmpty)
    }

    /// Mutation: ignore `launch`'s return value (`_ = await launch(bundle)`) — the
    /// wait then runs to the deadline and this returns `.noChange`,
    /// reporting a wait we never earned.
    @Test func aRefusedLaunchIsNotAWait() async {
        let spy = Spy()
        let outcome = await Self.refresher(launchSucceeds: false, spy: spy).run()
        #expect(outcome == .launchFailed)
        #expect(spy.sleeps == 0)
    }

    /// **The first write is not the sync.** The fixture is the measured shape: a
    /// burst of writes right after launch (reads 2 and 3 here) and then the one
    /// that matters several seconds later (read 15 ≈ +7s), with quiet after it.
    ///
    /// Two mutations, both run and both red here:
    ///   * return on the first change (`if now != seen { return .refreshed(…) }`) —
    ///     the shape this file shipped with first. The answer becomes 1s, before the
    ///     network round trip; the live CLI printed "refreshed … 0.5s", which is how
    ///     it was caught.
    ///   * shorten `settleInterval` back to 3s — the wait ends inside the pause
    ///     between the launch burst and the sync write, and reports 1s again.
    @Test func theWaitOutlastsTheLaunchBurstAndEndsOnTheLastWrite() async {
        let spy = Spy()
        let refresher = Self.refresher(stamp: Stamp(changesAt: [2, 3, 15]), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(30))
        guard case .refreshed(let after) = outcome else {
            Issue.record("expected a refresh, got \(outcome)")
            return
        }
        // The pre-launch reading consumes read 1, so read 15 lands on poll 14:
        // 14 × 500ms = 7s. That is the write reported — not the 1s one that came
        // first.
        #expect(after == .seconds(7))
        #expect(spy.launches == [Self.bundle])
    }

    /// A store still moving at the deadline is reported — something did happen and
    /// saying nothing would be worse — but it is NOT called a refresh. The sync may
    /// still be in flight, and the caller reads the store on the next line.
    ///
    /// Mutation: drop the post-loop `if let lastChange { … }` — this becomes
    /// `.noChange` and fails. Change it back to `.refreshed(after:)` —
    /// the `guard case` fails and names what came back.
    @Test func aStoreStillMovingAtTheDeadlineIsNotCalledARefresh() async {
        let spy = Spy()
        // Changes on every poll, so it never settles.
        let refresher = Self.refresher(stamp: Stamp(changesAt: Set(1...20)), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(2), settle: .seconds(3))
        guard case .changedWithoutSettling(let lastChange) = outcome else {
            Issue.record("expected an unsettled change, got \(outcome)")
            return
        }
        #expect(lastChange == .seconds(2))
    }

    /// Replay of the failure this case exists for, 2026-09-10. A cold launch wrote
    /// the store early, went quiet for far longer than `settle`, and the real sync
    /// landed **after** the deadline. The old code returned `.refreshed(after: 4s)`
    /// on the strength of that early write, and the check in the same process then
    /// printed build 1311 as up to date while 1312 was on its way to disk.
    ///
    /// The shape is what matters: an early write, a long silence, and a deadline
    /// that arrives first. Reporting a refresh here is reporting a version number
    /// the user has not got yet.
    ///
    /// Mutation: return `.refreshed(after: lastChange)` from the post-loop branch —
    /// this fails, because a store that never settled cannot be called refreshed no
    /// matter how early the first write was.
    @Test func anEarlyWriteFollowedBySilenceIsNotASync() async {
        let spy = Spy()
        // One write on the 8th poll, then nothing: with a deadline shorter than
        // settle, the loop can never satisfy the settle rule.
        let refresher = Self.refresher(stamp: Stamp(changesAt: [8]), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(5), settle: .seconds(6))
        guard case .changedWithoutSettling(let lastChange) = outcome else {
            Issue.record("expected an unsettled change, got \(outcome)")
            return
        }
        // Read 8 lands on the 7th poll: `run` reads the stamp once *before* the
        // loop, so loop iteration k is read k+1. 7 × 500ms.
        #expect(lastChange == .milliseconds(3500))
    }

    /// A launch that changes nothing is NOT reported as a refresh. The store has no
    /// "last synced" of its own, so "already current" and "the sync did not happen"
    /// are indistinguishable from here, and the honest answer names neither.
    ///
    /// Mutation: return `.refreshed` at the end of the loop — this fails.
    @Test func anInstanceThatChangesNothingIsNotCalledARefresh() async {
        let spy = Spy()
        let refresher = Self.refresher(stamp: Stamp(), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(2))
        #expect(outcome == .noChange)
        // 2s deadline at 500ms per poll.
        #expect(spy.sleeps == 4)
    }

    /// The instance we start is ours to end, and the pid we end is the pid we were
    /// handed — never a bundle-wide quit, which would take the user's own instance
    /// with it. That is not hypothetical: a harness that computed the pid wrongly
    /// killed the wrong one on 2026-09-10.
    ///
    /// Mutation: drop the `defer { terminate(pid) }` — `terminated` is empty and
    /// this fails. Terminate some other pid — the equality fails and names it.
    @Test func theInstanceWeStartedIsTheInstanceWeEnd() async {
        let spy = Spy()
        let refresher = Self.refresher(stamp: Stamp(changesAt: [2]), spy: spy)
        _ = await refresher.run(deadline: .seconds(5), settle: .seconds(1))
        #expect(spy.terminated == [Self.spawnedPID])
    }

    /// ...on the paths that do not end in a settled refresh either. A wait that
    /// runs out of time still leaves a process behind if nothing ends it, and that
    /// process is one the user never started.
    ///
    /// Mutation: move the termination to just before the `.refreshed` return
    /// instead of a `defer` — this fails while the settled case above still
    /// passes, which is exactly the asymmetry a single happy-path case would miss.
    @Test func anInstanceIsEndedEvenWhenTheStoreNeverSettles() async {
        let spy = Spy()
        // Changes on every poll, so the settle rule is never satisfied.
        let refresher = Self.refresher(stamp: Stamp(changesAt: Set(1...20)), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(2), settle: .seconds(3))
        #expect(spy.terminated == [Self.spawnedPID])
        guard case .changedWithoutSettling = outcome else {
            Issue.record("expected an unsettled change, got \(outcome)")
            return
        }
    }

    /// A spawn that never produced a process must not be followed by a termination:
    /// there is no pid, and inventing one is how a refresh that failed to start ends
    /// up killing something else.
    ///
    /// Mutation: replace the `guard let pid = await spawn(bundle) else { … }` with
    /// a fallback (`await spawn(bundle) ?? -1`) so the `defer` fires on the failure
    /// path too — this fails, naming the pid that was ended for a process that was
    /// never started.
    @Test func aFailedSpawnEndsNothing() async {
        let spy = Spy()
        let refresher = Self.refresher(launchSucceeds: false, spy: spy)
        let outcome = await refresher.run(deadline: .seconds(2))
        #expect(outcome == .launchFailed)
        #expect(spy.terminated.isEmpty)
    }

    /// The production wiring asks for a *separate* instance, hidden, and not
    /// activated. Each of the three carries something: without a separate instance
    /// a running TestFlight ignores the request entirely; without `hides` it puts a
    /// real window on screen; without `activates: false` it takes the foreground.
    ///
    /// Read out of the source because the alternative is launching TestFlight in a
    /// unit test.
    ///
    /// Mutation: flip any of the three in `AppRestarter.launchSeparateInstance` —
    /// the matching expectation fails and names which.
    @Test func theProductionLaunchIsASeparateHiddenInstance() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/DuoUpdaterCore/Install/AppRestarter.swift"),
            encoding: .utf8)
        let body = try #require(source.range(of: "launchSeparateInstance").map {
            String(source[$0.lowerBound...].prefix(1800))
        })
        #expect(body.contains("config.createsNewApplicationInstance = true"))
        #expect(body.contains("config.hides = true"))
        #expect(body.contains("config.activates = false"))
    }
}

// MARK: - After the attempt: what the menu's refresh does with the outcome

extension TestFlightRefreshTests {

    /// Which outcomes mean a read taken before the attempt is now stale. The row
    /// that matters is `changedWithoutSettling`: the store moved, so rows answered
    /// from the pre-sync read are the out-of-date ones. Mutation: answer `false`
    /// for it — then a sync that ran long leaves every TestFlight row on the build
    /// the store held before the sync.
    @Test(arguments: [
        (TestFlightRefresh.Outcome.refreshed(after: .seconds(4)), true),
        (.changedWithoutSettling(lastChange: .seconds(40)), true),
        (.noChange, false),
        (.notInstalled, false),
        (.launchFailed, false),
    ])
    func onlyAMovedStoreCallsForASecondRead(outcome: TestFlightRefresh.Outcome, changed: Bool) {
        #expect(outcome.storeChanged == changed)
    }

    /// A re-checked row replaces its counterpart in place; the rest of the round
    /// is untouched and keeps its order. Mutations, each red here: append
    /// `resynced` instead of replacing (the list grows and the stale row stays);
    /// return `checked` unchanged (the synced verdict is lost); match on bundle id
    /// instead of `id` (the second copy of the beta inherits a verdict about the
    /// first).
    @Test func aResyncedRowReplacesItsCounterpartInPlace() {
        let other = Self.row("ZZFixture-Other", bundleID: "com.example.other", .upToDate)
        let beta = Self.row("ZZFixture-Beta", bundleID: "com.example.beta", .upToDate)
        let betaCopy = Self.row("ZZFixture-Beta Copy", bundleID: "com.example.beta", .upToDate)
        let synced = Self.row("ZZFixture-Beta", bundleID: "com.example.beta",
                              .updateAvailable(latest: "1.0 (70)"))

        let merged = TestFlightRefresh.merging([other, beta, betaCopy], resynced: [synced])

        #expect(merged.map(\.id) == [other.id, beta.id, betaCopy.id])
        #expect(Self.isUpToDate(merged[0]))
        if case .updateAvailable(let latest) = merged[1].status {
            #expect(latest == "1.0 (70)")
        } else {
            Issue.record("the synced verdict was not applied: \(merged[1].status)")
        }
        #expect(Self.isUpToDate(merged[2]), "a second copy of the beta took the first copy's verdict")
    }

    /// A re-checked row the round does not hold is not added. Mutation: append
    /// unmatched rows — then the re-check could put an app in the list that the
    /// scan never found.
    @Test func aResyncedRowWithNoCounterpartIsDropped() {
        let beta = Self.row("ZZFixture-Beta", bundleID: "com.example.beta", .upToDate)
        let stranger = Self.row("ZZFixture-Stranger", bundleID: "com.example.stranger", .upToDate)
        #expect(TestFlightRefresh.merging([beta], resynced: [stranger]).map(\.id) == [beta.id])
    }

    /// Invented paths: `merging` keys on the path string and resolves nothing, so
    /// the host's disk cannot change these answers — named `ZZFixture-*` anyway, so
    /// they cannot be mistaken for a real app.
    private static func row(_ name: String, bundleID: String, _ status: UpdateStatus) -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: name, bundleID: bundleID,
                shortVersion: "1.0", buildVersion: "64",
                path: URL(fileURLWithPath: "/Applications/\(name).app"),
                isMASApp: false, isToolboxManaged: false,
                isTestFlightApp: true, sparkleFeedURL: nil,
                releaseChannel: .stable),
            remote: nil, status: status)
    }

    private static func isUpToDate(_ row: UpdateResult) -> Bool {
        if case .upToDate = row.status { return true }
        return false
    }
}
