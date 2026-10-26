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
        /// The app's on-screen windows at a tick (0 is before the quit request).
        /// By default a save sheet comes up on its window once asked: a quit
        /// still pending past the grace is a prompt unless a case says otherwise.
        var windows: (Int) -> Set<StagedRelaunch.OnScreenWindow> = {
            $0 < 1 ? [StagedRelaunchTests.window] : [StagedRelaunchTests.window, StagedRelaunchTests.sheet]
        }

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
                sparkleInstallerPIDs: { _ in [] }),
            onScreenWindows: { w.windows(w.now) })
    }

    /// Windows by number; `alert` is an app-modal one (`isModalPanel`).
    fileprivate static let window = StagedRelaunch.OnScreenWindow(id: 101, isModalPanel: false)
    fileprivate static let sheet = StagedRelaunch.OnScreenWindow(id: 102, isModalPanel: false)
    private static let alert = StagedRelaunch.OnScreenWindow(id: 103, isModalPanel: true)

    private func run(_ w: World, _ staged: StagedSelfUpdate?) async -> StagedRelaunch.Ending {
        await StagedRelaunch.quitAndAwait(
            app, staged: staged, old: old, wasFrontmost: false, system: system(w))
    }

    /// The quit is this route's point of no return (`InstallCommit`): a caller
    /// cancelled before it quits nothing, and the ending says the app never quit.
    /// Mutation: drop the commit → terminated, red.
    @Test func aCancelledCallerQuitsNothing() async {
        let w = World(disk: old, new: new)
        let system = system(w)
        let (app, old, staged) = (app, old, staged(.shipIt))
        let task = Task { () async -> StagedRelaunch.Ending in
            withUnsafeCurrentTask { $0?.cancel() }
            return await StagedRelaunch.quitAndAwait(
                app, staged: staged, old: old, wasFrontmost: false, system: system)
        }
        let ending = await task.value
        #expect(!w.terminated)
        #expect(!ending.everQuit)
        #expect(w.launches.isEmpty)
    }

    /// Cancelled after the quit: the wait goes on to the swap as if nothing
    /// happened. Its ticks never see the cancel — the live tick is a `try?`
    /// sleep, which on a cancelled task returns at once and spins the loop.
    /// Mutation: drop the commit → a tick sees the cancel, red.
    @Test func aCancelAfterTheQuitIsNotSeen() async {
        let w = World(disk: old, new: new)
        w.landsAt = 10
        let quit = InstallCommitTests.Signal()
        let release = InstallCommitTests.Signal()
        let sawCancel = InstallCommitTests.Flag()
        var system = system(w)
        system.terminate = { w.terminated = true; quit.fire() }
        system.tick = {
            await release.wait()
            if Task.isCancelled { sawCancel.set() }
            w.advance()
        }
        let (app, old, staged, frozen) = (app, old, staged(.shipIt), system)
        let task = Task { () async -> StagedRelaunch.Ending in
            await StagedRelaunch.quitAndAwait(
                app, staged: staged, old: old, wasFrontmost: false, system: frozen)
        }
        await quit.wait()
        task.cancel()
        release.fire()
        let ending = await task.value
        #expect(ending.outcome == .applied)
        #expect(!sawCancel.value)
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
        #expect(ending.holdup == .windowUp)
        #expect(w.now == StagedRelaunch.quitGraceTicks + 1)
        #expect(w.launches.isEmpty)
    }

    /// Witsy 3.5.1, 2026-10-26: asked to quit, it stayed up in the menu bar with
    /// no window on screen before or after. Still `.wontQuit` (at the slow-quit
    /// bound), but the ending says nothing was on screen, so no line sends the
    /// user looking for a save prompt. Mutation: sample `.windowUp` regardless
    /// (the old "likely a save prompt") → red.
    @Test func anAppThatStaysUpWithNothingOnScreenSaysSo() async {
        let w = World(disk: old, new: new)
        w.windows = { _ in [] }
        w.quitsAt = nil
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .wontQuit)
        #expect(ending.holdup == .nothingOnScreen)
        #expect(w.launches.isEmpty)
    }

    /// The mini 2026-10-18: ChatGPT closed its window ~0.4 s after the request and
    /// exited at ~5.8 s, just past the grace. Its windows being gone means it is
    /// exiting, so the wait goes on and the swap is seen to land. Mutation: drop
    /// the `showsNoPrompt` branch → `.wontQuit` at the grace, red.
    @Test func anAppThatClosedItsWindowsIsWaitedForPastTheGrace() async {
        let w = World(disk: old, new: new)
        w.windows = { $0 < 2 ? [Self.window] : [] }
        w.quitsAt = 29
        w.landsAt = 31
        w.updaterRelaunches = false
        let ending = await run(w, staged(.sparkle))
        #expect(ending.outcome == .applied)
        #expect(ending.everQuit)
        #expect(w.launches.count == 1 && w.launches.allSatisfy { $0 >= 31 }, "reopened after the landing, by the fallback")
    }

    /// Tropy 1.17.2, 2026-10-22: an Electron app whose ShipIt had 1.17.3 staged
    /// kept its window on screen and exited 27.9 s after the request (about
    /// 40 s in another round), with no prompt. `duo restart` called it a save
    /// prompt at ~5 s, and nothing reopened it after ShipIt swapped. The same
    /// window still up is no prompt: the wait goes on, the swap lands, and the
    /// fallback reopens it. Mutation: back to "windows gone" (`closedItsWindows`)
    /// → `.wontQuit` at the grace; or `slowQuitTicks` back to 150 → `.wontQuit`
    /// at 150; red either way.
    @Test func theSameWindowStillOnScreenIsWaitedFor() async {
        let w = World(disk: old, new: new)
        w.windows = { _ in [Self.window] }
        w.quitsAt = 200
        w.landsAt = 202
        w.updaterRelaunches = false
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .applied)
        #expect(ending.everQuit)
        #expect(w.launches.count == 1 && w.launches.allSatisfy { $0 >= 202 }, "reopened after the landing, by the fallback")
    }

    /// A window that was not on screen at the request — a save sheet — is a
    /// prompt: the same 5 s bail as before, however soon the app would have
    /// exited.
    @Test func aNewWindowOnScreenEndsAtTheGrace() async {
        let w = World(disk: old, new: new)
        w.windows = { $0 < 1 ? [Self.window] : [Self.window, Self.sheet] }
        w.quitsAt = 29
        let ending = await run(w, staged(.sparkle))
        #expect(ending.outcome == .wontQuit)
        #expect(w.now == StagedRelaunch.quitGraceTicks + 1)
    }

    /// PicGo 3.0.2's own "Find new version" dialog, already up when asked, held
    /// its quit. An app-modal alert on screen is a prompt even if it was there
    /// before the request. Mutation: drop the `isModalPanel` test from
    /// `showsNoPrompt` → waited on to `slowQuitTicks`, red.
    @Test func anAlertAlreadyUpAtTheRequestEndsAtTheGrace() async {
        let w = World(disk: old, new: new)
        w.windows = { _ in [Self.window, Self.alert] }
        w.quitsAt = nil
        let ending = await run(w, staged(.sparkle))
        #expect(ending.outcome == .wontQuit)
        #expect(w.now == StagedRelaunch.quitGraceTicks + 1)
    }

    /// Nothing on screen when asked (hidden, minimized, another Space) and
    /// nothing since: no prompt, so a slow exit is waited for.
    @Test func nothingOnScreenAtTheRequestIsWaitedFor() async {
        let w = World(disk: old, new: new)
        w.windows = { _ in [] }
        w.quitsAt = 29
        w.landsAt = 31
        w.updaterRelaunches = false
        let ending = await run(w, staged(.sparkle))
        #expect(ending.outcome == .applied)
        #expect(w.launches.count == 1 && w.launches.allSatisfy { $0 >= 31 })
    }

    /// A hidden app's save sheet un-hides its window next to the sheet (test
    /// app, 2026-10-22): both new on screen, so a prompt at the grace.
    @Test func aHiddenAppsPromptEndsAtTheGrace() async {
        let w = World(disk: old, new: new)
        w.windows = { $0 < 1 ? [] : [Self.window, Self.sheet] }
        w.quitsAt = 29
        let ending = await run(w, staged(.sparkle))
        #expect(ending.outcome == .wontQuit)
        #expect(w.now == StagedRelaunch.quitGraceTicks + 1)
    }

    /// Windows closed, then a prompt comes up on screen: bail on that tick, not
    /// at `slowQuitTicks`.
    @Test func aPromptAfterTheWindowsClosedEndsTheWaitAtOnce() async {
        let w = World(disk: old, new: new)
        w.windows = { $0 < 2 ? [Self.window] : ($0 < 40 ? [] : [Self.window, Self.sheet]) }
        w.quitsAt = nil
        let ending = await run(w, staged(.sparkle))
        #expect(ending.outcome == .wontQuit)
        #expect(w.now == 40)
    }

    /// Windows gone but the process never exits: the extension is bounded.
    @Test func aWindowlessAppThatNeverExitsEndsAtTheSlowQuitBound() async {
        let w = World(disk: old, new: new)
        w.windows = { $0 < 2 ? [Self.window] : [] }
        w.quitsAt = nil
        let ending = await run(w, staged(.sparkle))
        #expect(ending.outcome == .wontQuit)
        #expect(ending.holdup == .nothingOnScreen)
        #expect(w.now == StagedRelaunch.slowQuitTicks + 1)
        #expect(w.launches.isEmpty)
    }

    /// `duo restart`'s Ctrl-C still ends the wait while the windows-gone
    /// extension is running. Mutation: drop `!quitPatience.stopWaiting()` from
    /// that branch → the wait runs on to `slowQuitTicks`, red.
    @Test func aStopEndsTheWindowsGoneExtension() async {
        let w = World(disk: old, new: new)
        w.windows = { $0 < 2 ? [Self.window] : [] }
        w.quitsAt = nil
        let ending = await StagedRelaunch.quitAndAwait(
            app, staged: staged(.sparkle), old: old, wasFrontmost: false,
            quitPatience: StagedRelaunch.QuitPatience(
                ticks: StagedRelaunch.slowQuitTicks * 2, stopWaiting: { w.now >= 40 }),
            system: system(w))
        #expect(ending.outcome == .wontQuit)
        #expect(w.now == 40)
    }

    @Test func showsNoPromptOnlyWithoutNewWindowsOrAlerts() {
        #expect(StagedRelaunch.showsNoPrompt(atQuit: [Self.window], now: []))
        #expect(StagedRelaunch.showsNoPrompt(atQuit: [], now: []))
        #expect(StagedRelaunch.showsNoPrompt(atQuit: [Self.window], now: [Self.window]))
        #expect(!StagedRelaunch.showsNoPrompt(atQuit: [Self.window], now: [Self.sheet]))
        #expect(!StagedRelaunch.showsNoPrompt(atQuit: [], now: [Self.window]))
        #expect(!StagedRelaunch.showsNoPrompt(atQuit: [Self.alert], now: [Self.alert]))
    }

    /// Any window of its own on screen is "a window is up"; none is "nothing
    /// on screen". Mutation: `windows.isEmpty` inverted, or a constant → red.
    @Test func quitHoldupReadsWhatIsOnScreen() {
        #expect(StagedRelaunch.QuitHoldup(windows: []) == .nothingOnScreen)
        #expect(StagedRelaunch.QuitHoldup(windows: [Self.window]) == .windowUp)
        #expect(StagedRelaunch.QuitHoldup(windows: [Self.alert]) == .windowUp)
    }

    /// The other endings carry no holdup.
    @Test func onlyAWontQuitEndingCarriesAHoldup() async {
        let w = World(disk: old, new: new)
        w.landsAt = 3
        let ending = await run(w, staged(.shipIt))
        #expect(ending.outcome == .applied)
        #expect(ending.holdup == nil)
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

    private final class Calls: @unchecked Sendable {
        var count = 0
        var holdups: [StagedRelaunch.QuitHoldup] = []
    }

    private func runPatient(_ w: World, _ calls: Calls) async -> StagedRelaunch.Ending {
        await StagedRelaunch.quitAndAwait(
            app, staged: staged(.shipIt), old: old, wasFrontmost: false,
            quitPatience: .handoff(onSlowQuit: { calls.count += 1; calls.holdups.append($0) }), system: system(w))
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
        #expect(ending.holdup == .windowUp)
        #expect(w.now == Int(StagedRelaunch.quitHandoffMaxAge * 5) + 1)
        #expect(w.launches.isEmpty)
        #expect(calls.count == 1)
        #expect(calls.holdups == [.windowUp])
    }

    /// The menu-bar shape in a terminal: nothing on screen, so the slow-quit
    /// line is said at `slowQuitTicks` (not the grace) and is told nothing is
    /// on screen. Mutation: pass `.windowUp` to `onSlowQuit` regardless → red.
    @Test func aWindowlessHoldTellsTheSlowQuitLineSo() async {
        let w = World(disk: old, new: new)
        w.windows = { _ in [] }
        w.quitsAt = nil
        let calls = Calls()
        let ending = await runPatient(w, calls)
        #expect(ending.outcome == .wontQuit)
        #expect(ending.holdup == .nothingOnScreen)
        #expect(calls.holdups == [.nothingOnScreen])
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

    // MARK: - stopWaiting (`duo restart`'s Ctrl-C)

    /// A stop asked for while the app has not quit, past the slow-quit point,
    /// ends the wait on that tick, as an exhausted patience would: `.wontQuit`,
    /// nothing launched — not after the 10-minute hand-off. Mutation: ignore
    /// `stopWaiting` → the wait runs to `quitHandoffMaxAge * 5` ticks, red.
    @Test func aStopBeforeTheQuitEndsTheWaitAsWontQuit() async {
        let w = World(disk: old, new: new)
        w.quitsAt = nil
        let ending = await StagedRelaunch.quitAndAwait(
            app, staged: staged(.shipIt), old: old, wasFrontmost: false,
            quitPatience: .handoff(onSlowQuit: { _ in }, stopWaiting: { w.now >= 50 }), system: system(w))
        #expect(ending.outcome == .wontQuit)
        #expect(ending.everQuit == false)
        #expect(w.now == 50)
        #expect(w.launches.isEmpty)
    }

    /// Once the app has quit, a stop is not consulted: the swap wait runs out and
    /// the reopen comes after the landing. The landing is past `quitGraceTicks`,
    /// where a stop would first be honoured. Mutation: consult `stopWaiting`
    /// after the quit too → the wait ends at `quitGraceTicks`, before the
    /// landing, and the fallback reopens the app mid-swap, red.
    @Test func aStopAfterTheQuitIsIgnored() async {
        let w = World(disk: old, new: new)
        w.quitsAt = 1
        w.landsAt = 40
        w.updaterRelaunches = false
        let ending = await StagedRelaunch.quitAndAwait(
            app, staged: staged(.shipIt), old: old, wasFrontmost: false,
            quitPatience: .handoff(onSlowQuit: { _ in }, stopWaiting: { w.now >= 2 }), system: system(w))
        #expect(ending.outcome == .applied)
        #expect(w.landedAt == 40)
        #expect(w.launches == [40])
    }

    /// A stop asked for before the quit request (during the rollback copy) and
    /// an app that quits normally a few ticks later: the stop is not honoured
    /// before `quitGraceTicks`, so the quit is seen, the swap is waited for, and
    /// the app — whose updater does not reopen it — is reopened after the
    /// landing. Mutation: drop the `quitGraceTicks` floor → `.wontQuit` on the
    /// first tick, while the app is still shutting down, and no reopen, red.
    @Test func aStopBeforeTheSlowQuitPointLetsANormalQuitRunOut() async {
        let w = World(disk: old, new: new)
        w.quitsAt = 3
        w.landsAt = 10
        w.updaterRelaunches = false
        let calls = Calls()
        let ending = await StagedRelaunch.quitAndAwait(
            app, staged: staged(.shipIt), old: old, wasFrontmost: false,
            quitPatience: .handoff(onSlowQuit: { calls.count += 1; calls.holdups.append($0) }, stopWaiting: { true }),
            system: system(w))
        #expect(ending.outcome == .applied)
        #expect(ending.everQuit)
        #expect(w.landedAt == 10)
        #expect(w.launches == [10], "reopened once, after the swap landed")
        #expect(calls.count == 0)
    }

    /// The same early stop, but the app is still up at `quitGraceTicks`: the
    /// wait ends there as `.wontQuit` — what `.grace` does — and the slow-quit
    /// line, which offers a longer wait, is not printed. Mutations: drop
    /// `stopWaiting` → the wait runs the whole hand-off window, red; check the
    /// slow-quit line before the stop → `calls.count == 1`, red.
    @Test func aStopBeforeTheSlowQuitPointEndsAStuckQuitThere() async {
        let w = World(disk: old, new: new)
        w.quitsAt = nil
        let calls = Calls()
        let ending = await StagedRelaunch.quitAndAwait(
            app, staged: staged(.shipIt), old: old, wasFrontmost: false,
            quitPatience: .handoff(onSlowQuit: { calls.count += 1; calls.holdups.append($0) }, stopWaiting: { true }),
            system: system(w))
        #expect(ending.outcome == .wontQuit)
        #expect(ending.everQuit == false)
        #expect(w.now == StagedRelaunch.quitGraceTicks + 1)
        #expect(w.launches.isEmpty)
        #expect(calls.count == 0)
    }
}
