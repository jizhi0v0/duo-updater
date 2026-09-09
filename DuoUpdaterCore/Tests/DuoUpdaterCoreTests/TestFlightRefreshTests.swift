import Testing
import Foundation
@testable import DuoUpdaterCore

/// The decision table of `TestFlightRefresh`, with every effect injected so no
/// case launches anything or waits on a real clock.
///
/// What the cases are *for* is the measurement behind each branch (#491): a
/// background launch refreshes the store only while TestFlight is **not** running,
/// and the wait has to end on the store actually changing rather than on a guess
/// about how long a sync takes.
struct TestFlightRefreshTests {

    /// Records what the effects were asked to do, so a case can assert on the
    /// things that did NOT happen — which is most of this type's contract.
    private final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var launches: [URL] = []
        private(set) var activations = 0
        private(set) var sleeps = 0
        func launched(_ url: URL) {
            lock.lock(); defer { lock.unlock() }
            launches.append(url)
        }
        func activated() {
            lock.lock(); defer { lock.unlock() }
            activations += 1
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

    private static func refresher(
        installed: Bool = true,
        running: Bool = false,
        launchSucceeds: Bool = true,
        activation: SilentActivation.Outcome = .activated(heldFor: .milliseconds(120)),
        stamp: Stamp = Stamp(),
        spy: Spy
    ) -> TestFlightRefresh {
        TestFlightRefresh(
            locate: { installed ? bundle : nil },
            isRunning: { running },
            launch: { url in spy.launched(url); return launchSucceeds },
            activate: { spy.activated(); return activation },
            storeStamp: { stamp.read() },
            sleep: { _ in spy.slept() })
    }

    /// Measured four times: with TestFlight already running, a background launch
    /// delivers the request and the store is still unchanged two minutes later. So
    /// the running case takes the activation route instead — and it must still
    /// launch nothing, or the caller is told a refresh happened having only started
    /// a second process.
    ///
    /// Mutation: swap the two branches of `if isRunning()`, or drop the check —
    /// `launches` becomes non-empty and this fails.
    @Test func aRunningTestFlightIsActivatedAndNeverLaunched() async {
        let spy = Spy()
        let refresher = Self.refresher(running: true, stamp: Stamp(changesAt: [3]), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(30))
        #expect(outcome == .refreshed(after: .seconds(1)))
        #expect(spy.launches.isEmpty)
        #expect(spy.activations == 1)
    }

    /// An activation that changed nothing is reported as its own case: "we nudged
    /// the running app and its data did not move" is a different sentence from
    /// "we started it from cold and its data did not move", and the CLI prints
    /// both.
    ///
    /// Mutation: return `.launchedWithoutChange` for both routes — this fails.
    @Test func anActivationThatChangesNothingIsNotCalledALaunch() async {
        let spy = Spy()
        let outcome = await Self.refresher(running: true, spy: spy).run(deadline: .seconds(2))
        #expect(outcome == .activatedWithoutChange)
        #expect(spy.launches.isEmpty)
    }

    /// A macOS without the SkyLight symbols cannot serve a running TestFlight, and
    /// says so rather than launching a second copy behind the user's back.
    ///
    /// Mutation: fall through to `launch(bundle)` on `.unavailable` — `launches`
    /// becomes non-empty and this fails.
    @Test func aRunningTestFlightIsNotLaunchedWhenActivationIsUnavailable() async {
        let spy = Spy()
        let outcome = await Self.refresher(running: true, activation: .unavailable, spy: spy).run()
        #expect(outcome == .activationUnavailable)
        #expect(spy.launches.isEmpty)
        #expect(spy.sleeps == 0)
    }

    /// A password field owning the keyboard is surfaced, not worked around.
    ///
    /// Mutation: map `.refusedSecureInput` onto `.activationUnavailable` — the
    /// user is then told this Mac cannot do it at all, which is false and would
    /// stop them retrying a second later. This fails.
    @Test func aSecureInputRefusalReachesTheCaller() async {
        let spy = Spy()
        let outcome = await Self.refresher(running: true, activation: .refusedSecureInput, spy: spy).run()
        #expect(outcome == .refusedSecureInput)
        #expect(spy.launches.isEmpty)
    }

    /// The user is looking at TestFlight right now. Nothing is launched, nothing is
    /// activated a second time, and the CLI says so rather than reporting a refresh
    /// that did not happen — measured: zero network connections in this state.
    ///
    /// Mutation: map `.alreadyActive` onto `.activatedWithoutChange` — the user is
    /// then told their data "did not change" when in fact nothing was ever asked.
    /// This fails.
    @Test func aFrontmostTestFlightIsReportedNotNudged() async {
        let spy = Spy()
        let outcome = await Self.refresher(running: true, activation: .alreadyActive, spy: spy).run()
        #expect(outcome == .alreadyFrontmost)
        #expect(spy.launches.isEmpty)
        #expect(spy.sleeps == 0)
    }

    /// TestFlight quitting between `isRunning()` and the activation is a race, not
    /// a failure: the cold route serves it.
    ///
    /// Mutation: return `.activationFailed` on `.notRunning` — a refresh that
    /// would have worked is reported as broken. This fails.
    @Test func anAppThatQuitsDuringTheRaceFallsBackToTheColdLaunch() async {
        let spy = Spy()
        let refresher = Self.refresher(
            running: true, activation: .notRunning, stamp: Stamp(changesAt: [3]), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(30))
        #expect(outcome == .refreshed(after: .seconds(1)))
        #expect(spy.launches == [Self.bundle])
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
    /// wait then runs to the deadline and this returns `.launchedWithoutChange`,
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

    /// The settle rule must not swallow the answer when the store keeps moving past
    /// the deadline: a refresh that did happen is still reported, with the last
    /// moment it was seen moving.
    ///
    /// Mutation: drop the post-loop `if let lastChange { return .refreshed(…) }` —
    /// this becomes `.launchedWithoutChange` and fails.
    @Test func aStoreStillMovingAtTheDeadlineIsStillARefresh() async {
        let spy = Spy()
        // Changes on every poll, so it never settles.
        let refresher = Self.refresher(stamp: Stamp(changesAt: Set(1...20)), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(2), settle: .seconds(3))
        guard case .refreshed(let after) = outcome else {
            Issue.record("expected a refresh, got \(outcome)")
            return
        }
        #expect(after == .seconds(2))
    }

    /// A launch that changes nothing is NOT reported as a refresh. The store has no
    /// "last synced" of its own, so "already current" and "the sync did not happen"
    /// are indistinguishable from here, and the honest answer names neither.
    ///
    /// Mutation: return `.refreshed` at the end of the loop — this fails.
    @Test func aLaunchThatChangesNothingIsNotCalledARefresh() async {
        let spy = Spy()
        let refresher = Self.refresher(stamp: Stamp(), spy: spy)
        let outcome = await refresher.run(deadline: .seconds(2))
        #expect(outcome == .launchedWithoutChange)
        // 2s deadline at 500ms per poll.
        #expect(spy.sleeps == 4)
    }

    /// The launch must be background AND hidden. Both halves were measured, and
    /// each covers a different way of getting in the user's way:
    ///
    ///   * `activates: false` — a foreground activation refreshes in 3s but takes
    ///     the screen, which is what #491 refuses to do from a background check.
    ///   * `hides: true` — without it the launch still puts a real window on screen
    ///     behind the user's work (measured 2026-09-09 with
    ///     `CGWindowListCopyWindowInfo`: layer 0, alpha 1, 1010×717, and visible in
    ///     Mission Control). With it: zero on-screen windows, same sync.
    ///
    /// Mutation: drop either argument — `AppRestarter.launchApp($0)` defaults to
    /// `activates: true` and `hides: false`, the compiler stays happy, and this case
    /// is the only thing that objects.
    @Test func theProductionLaunchIsBackgroundAndHidden() async {
        // The default closure is opaque, so this pins the intent where it is
        // written rather than the closure itself: `activates` must be false.
        let source = try? String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()          // DuoUpdaterCoreTests
                .deletingLastPathComponent()          // Tests
                .deletingLastPathComponent()          // DuoUpdaterCore
                .appendingPathComponent("Sources/DuoUpdaterCore/Sources/TestFlightRefresh.swift"),
            encoding: .utf8)
        let text = try! #require(source)
        #expect(text.contains("AppRestarter.launchApp($0, activates: false, hides: true)"))
    }
}
