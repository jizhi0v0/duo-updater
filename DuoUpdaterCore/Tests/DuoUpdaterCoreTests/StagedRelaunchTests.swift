import Foundation
import Testing
@testable import DuoUpdaterCore

/// `StagedRelaunch.quitAndAwait` — the Relaunch wait shared by the menu-bar app
/// and `duo restart` — driven tick by tick against a fake app, disk and
/// installer. The rule every case guards: a swap-on-quit app is never reopened
/// before its swap lands (a ShipIt with the running-instances check aborts with
/// "App Still Running Error" — GitKraken, 2026-10-16).
@Suite struct StagedRelaunchTests {

    private let app = InstalledApp(
        name: "GitKraken", bundleID: "com.axosoft.gitkraken",
        shortVersion: "12.5.0", buildVersion: "12.5.0",
        path: URL(fileURLWithPath: "/ZZFixture/GitKraken.app"),
        isMASApp: false, sparkleFeedURL: nil)

    private let old = VersionSide(marketing: "12.5.0", build: "12.5.0")
    private let new = VersionSide(marketing: "12.6.0", build: "12.6.0")

    private func staged(_ updater: StagedUpdater?, on trigger: StagedApplyTrigger = .quit) -> StagedSelfUpdate {
        StagedSelfUpdate(version: "12.6.0", buildVersion: "12.6.0",
                         stagedBundlePath: URL(fileURLWithPath: "/ZZFixture/update.x/GitKraken.app"),
                         appliesOn: trigger, updater: updater)
    }

    /// The fake machine. `tick` advances the clock; everything else reads it.
    private final class World: @unchecked Sendable {
        var now = 0
        var terminated = false
        var running = true
        /// Ticks at which the app's own process list changes on its own.
        var quitsAt: Int? = 1
        var reappearsAt: Int?
        /// The swap lands at this tick (absolute), or this many ticks after our
        /// own launch for a swap-on-launch app.
        var landsAt: Int?
        var landsAfterOurLaunch: Int?
        /// Whether the updater reopens the app itself when it lands.
        var updaterRelaunches = true
        var disk: VersionSide
        let new: VersionSide
        var launches: [Int] = []
        var landedAt: Int?
        // Installer probe state.
        var job: ParkedInstallerProbe.LoadedJob?
        var jobGoneAt: Int?

        init(disk: VersionSide, new: VersionSide) { self.disk = disk; self.new = new }

        func advance() {
            now += 1
            if terminated, let q = quitsAt, now >= q, landedAt == nil, reappearsAt.map({ now < $0 }) ?? true {
                running = false
            }
            if let r = reappearsAt, now >= r, landedAt == nil { running = true }
            if landedAt == nil {
                let due = landsAt.map { now >= $0 } ?? false
                let dueAfterLaunch = landsAfterOurLaunch.flatMap { delay in
                    launches.first.map { now >= $0 + delay } } ?? false
                if (due && !running) || dueAfterLaunch {
                    disk = new
                    landedAt = now
                    if updaterRelaunches { running = true }
                }
            }
            if let g = jobGoneAt, now >= g { job = nil }
        }
    }

    private func system(_ w: World) -> StagedRelaunch.System {
        StagedRelaunch.System(
            tick: { w.advance() },
            isRunning: { w.running },
            terminate: { w.terminated = true },
            diskVersion: { w.disk },
            awaitBundleProcessesGone: {},
            relaunch: { _ in w.launches.append(w.now); w.running = true; return true },
            installer: ParkedInstallerProbe.System(
                isAlive: { _ in false },
                loadedJob: { _ in w.job },
                sparkleInstallerPIDs: { _ in [] }))
    }

    private func run(_ w: World, _ staged: StagedSelfUpdate?) async -> StagedRelaunch.Ending {
        await StagedRelaunch.quitAndAwait(
            app, staged: staged, old: old, wasFrontmost: false, system: system(w))
    }

    /// The GitKraken case: quit, ShipIt swaps and reopens it. We launch nothing.
    /// Mutation: reopen right after the quit (what `AppRestarter.restart` does)
    /// → a launch before `landedAt`, red.
    @Test func swapOnQuitIsNeverReopenedByUs() async {
        let w = World(disk: old, new: new)
        w.landsAt = 10
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .applied)
        #expect(w.terminated)
        #expect(w.landedAt == 10)
        #expect(w.launches.isEmpty, "ShipIt relaunched it; a launch from us would race the swap")
    }

    /// A ShipIt staged with `launchAfterInstallation=false`: lands, stays closed.
    /// The fallback reopens it — only after the landing.
    @Test func aSwapThatDoesNotRelaunchIsReopenedAfterItLands() async {
        let w = World(disk: old, new: new)
        w.landsAt = 10
        w.updaterRelaunches = false
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .applied)
        #expect(ending.reopenFailed == false)
        #expect(w.launches.count == 1)
        #expect(w.launches.allSatisfy { $0 >= 10 })
    }

    /// Spotify: nothing lands until the old build is opened again, so we launch
    /// right after the quit. Mutation: treat `.launch` as `.quit` → no launch,
    /// the full wait, then `.swapDidNotLand`-turned-fallback; the tick checks go red.
    @Test func swapOnLaunchIsLaunchedRightAfterTheQuit() async {
        let w = World(disk: old, new: new)
        w.quitsAt = 2
        w.landsAfterOurLaunch = 3
        let ending = await run(w, staged(.spotify, on: .launch))
        #expect(ending.outcome == .applied)
        #expect(w.launches.first == 2)
        #expect(w.landedAt == 5)
    }

    /// A save prompt keeps it up: give up after `quitGraceTicks`, launch nothing.
    @Test func anAppThatWontQuitEndsAfterTheGrace() async {
        let w = World(disk: old, new: new)
        w.quitsAt = nil
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .wontQuit)
        #expect(ending.everQuit == false)
        #expect(w.now == StagedRelaunch.quitGraceTicks + 1)
        #expect(w.launches.isEmpty)
    }

    /// ShipIt: back up on the old bundle means the swap was called off — stop
    /// ~`graceTicks` after, and don't reopen what is already running.
    @Test func aShipItReappearanceEndsTheWaitEarly() async {
        let w = World(disk: old, new: new)
        w.reappearsAt = 4
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .restartedWithoutUpdate)
        #expect(w.now == 4 + ReappearanceWatch.graceTicks)
        #expect(w.launches.isEmpty)
    }

    /// Sparkle swaps under a reopened instance, so a reappearance is not judged:
    /// the full wait runs.
    @Test func aSparkleReappearanceGetsTheFullWait() async {
        let w = World(disk: old, new: new)
        w.reappearsAt = 4
        let ending = await run(w, staged(.sparkle))
        #expect(ending.outcome == .swapDidNotLand)
        #expect(w.now == StagedRelaunch.maxTicks)
        #expect(w.launches.isEmpty, "it is running; nothing to bring back")
    }

    /// Never lands, app stays closed: the full ~180 s, then reopened anyway so
    /// the user is not left without it.
    @Test func aTimeoutReopensTheAppAndSaysSo() async {
        let w = World(disk: old, new: new)
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .swapDidNotLand)
        #expect(ending.everQuit)
        #expect(w.now == StagedRelaunch.maxTicks)
        #expect(w.launches == [StagedRelaunch.maxTicks])
    }

    /// The ShipIt job found before the quit goes away and disk never moved: stop
    /// after `InstallerExitWatch.graceTicks` instead of the full wait.
    @Test func anInstallerExitEndsTheWaitEarly() async {
        let w = World(disk: old, new: new)
        w.job = .init(pid: nil, lastExitStatus: 256)
        w.jobGoneAt = 3
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .swapDidNotLand)
        #expect(w.now == 3 + InstallerExitWatch.graceTicks)
        #expect(w.launches.count == 1, "the app is closed; the fallback brings it back")
    }

    /// A reopen that fails is reported, so the CLI can say the app is left closed.
    @Test func aFailedFallbackReopenIsReported() async {
        let w = World(disk: old, new: new)
        w.landsAt = 5
        w.updaterRelaunches = false
        var sys = system(w)
        sys.relaunch = { _ in false }
        let ending = await StagedRelaunch.quitAndAwait(
            app, staged: staged(.shipIt), old: old, wasFrontmost: false, system: sys)
        #expect(ending.outcome == .applied)
        #expect(ending.reopenFailed)
    }

    // MARK: - QuitPatience (`duo restart` in a terminal)

    private final class Calls: @unchecked Sendable { var count = 0 }

    private func runPatient(_ w: World, _ calls: Calls) async -> StagedRelaunch.Ending {
        await StagedRelaunch.quitAndAwait(
            app, staged: staged(.shipIt), old: old, wasFrontmost: false,
            quitPatience: .handoff(onSlowQuit: { calls.count += 1 }), system: system(w))
    }

    /// The save prompt is answered a minute in: the quit lands late, ShipIt
    /// (staged with launchAfterInstallation=false) swaps, and the app is reopened
    /// after the landing — what the menu-bar app's quit hand-off does. Mutation:
    /// bailing at `quitGraceTicks` regardless of the patience → `.wontQuit`, red.
    @Test func aLateQuitIsWaitedForAndReopenedAfterTheLanding() async {
        let w = World(disk: old, new: new)
        w.quitsAt = 300
        w.landsAt = 310
        w.updaterRelaunches = false
        let calls = Calls()
        let ending = await runPatient(w, calls)
        #expect(ending.outcome == .applied)
        #expect(ending.everQuit)
        #expect(w.launches == [310], "reopened once, after the swap landed")
        #expect(calls.count == 1, "the slow-quit line is printed once")
    }

    /// Never answered: `.wontQuit` once the hand-off window has passed, no launch.
    @Test func anUnansweredPromptEndsAfterTheHandoffWindow() async {
        let w = World(disk: old, new: new)
        w.quitsAt = nil
        let calls = Calls()
        let ending = await runPatient(w, calls)
        #expect(ending.outcome == .wontQuit)
        #expect(w.now == Int(StagedRelaunch.quitHandoffMaxAge * 5) + 1)
        #expect(w.launches.isEmpty)
        #expect(calls.count == 1)
    }

    /// A late quit still gets the swap wait it would have had from the grace on,
    /// not the remainder of `maxTicks` from the request. Mutation: dropping the
    /// `swapDeadline` move → the wait ends the tick after the quit, red.
    @Test func aLateQuitGetsTheFullSwapWait() async {
        let w = World(disk: old, new: new)
        w.quitsAt = 2000
        let ending = await runPatient(w, Calls())
        #expect(ending.outcome == .swapDidNotLand)
        // Seen gone at loop tick `quitsAt - 1`.
        #expect(w.now == 2000 - 1 + StagedRelaunch.maxTicks - StagedRelaunch.quitGraceTicks)
        #expect(w.launches.count == 1, "the timeout's fallback reopens it")
    }

    /// An app that quits within the grace is not told it was slow.
    @Test func aPromptQuitPrintsNothing() async {
        let w = World(disk: old, new: new)
        w.landsAt = 10
        let calls = Calls()
        let ending = await runPatient(w, calls)
        #expect(ending.outcome == .applied)
        #expect(calls.count == 0)
    }
}
