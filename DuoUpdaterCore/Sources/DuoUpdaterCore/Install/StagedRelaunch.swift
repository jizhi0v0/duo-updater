import CoreGraphics
import Foundation

/// Apply a build the app's own updater has staged (the ShipIt "Relaunch to
/// update" state): quit the app, wait for its updater to swap the bundle, and
/// bring it back only when that is safe.
///
/// **Why this lives in Core.** It was the body of `AppListModel.relaunchStagedUpdate`,
/// so `duo restart` could only reach `AppRestarter.restart` — and that is the
/// wrong order for a swap-on-quit updater. Measured on GitKraken 12.5.0 with
/// 12.6.0 staged, 2026-10-16: `duo restart` quit and reopened it at once, and
/// ShipIt logged "Aborting update attempt because there are 1 running instances
/// of the target app" (`SQRLInstallerErrorDomain` -9) a second after "Beginning
/// installation". Both hosts now run this one wait; what stays with the caller is
/// its own state around it (the GUI's spinner, notes, quit hand-off and red
/// line; the CLI's printed lines). The rollback point taken before the quit is
/// shared too (`StagedRelaunchBackup.take`), and so is how long a quit held up
/// by a prompt may take (`QuitPatience`).
///
/// **Crucially different from `AppRestarter.restart`**: for a swap-on-quit
/// updater we must **not** reopen the app before the swap has landed. Those
/// swap the bundle after the quit, and a reopen from us races that. For ShipIt
/// it failed outright: an immediate reopen put the app back up and ShipIt — a
/// Squirrel.Mac build with the running-instances check — aborted with "App
/// Still Running Error" every time. Sparkle 2 waits only on the instance it
/// registered (`StagedUpdater`), so a reopen there would leave the old build
/// running while its swap goes ahead — read from Sparkle's source, not observed.
/// UNVERIFIED: what an older Squirrel build without the running-instances check
/// does on a reopen.
///
/// So this quits, polls disk to confirm the swap landed, and does not reopen
/// while waiting. The updater may relaunch the app itself, but not always (a
/// ShipIt staged with `launchAfterInstallation=false` does not), so when the
/// wait ends — landed or timed out — the app is reopened here if it is still
/// closed. Not after a reappearance: it was just seen running. Spotify is the
/// exception to that order: its updater applies on the next launch, so this
/// reopens it right after the quit (`StagedApplyTrigger.launch`).
public enum StagedRelaunch {

    /// The ~200 ms ticks of the wait.
    ///
    /// Swap-on-quit (ShipIt, Sparkle): with the app quit it swaps the bundle,
    /// then relaunches. Two phases with very different patience:
    ///  • Until it actually quits: short. If it's still up after a few seconds a
    ///    save prompt is blocking the quit — bail and leave it staged.
    ///  • Once quit: long. Replacing a whole app bundle takes a while, and a busy
    ///    or slow disk stretches it further — so be patient rather than dropping
    ///    the spinner mid-swap and looking stuck.
    ///
    /// Swap-on-launch (Spotify): same quit phase, then launch at once — waiting
    /// for disk first is exactly what spun the full 180 s on 2026-09-14 and only
    /// landed when the timeout's fallback reopened it. After the launch the
    /// swap took ~2 s; `postLaunchTicks` is a generous ceiling, not a guess at it.
    public static let quitGraceTicks = 25   // ~5s to actually quit (else a save prompt is up)
    public static let maxTicks = 900        // up to ~180s for a slow swap on a busy disk
    public static let postLaunchTicks = 150 // ~30s from our launch to the swap landing
    /// After our own launch (swap-on-launch), how long to let the updater's own
    /// open of the new build register before the fallback launches it.
    public static let settleTicks = 15
    /// How long, from the quit request, an app that shows no prompt may take to
    /// exit before the wait gives up anyway (~60 s).
    ///
    /// The grace above is a guess that "still up after 5 s" means a save prompt.
    /// It guesses wrong for an app that is simply slow to exit: ChatGPT on the
    /// loaded mini, 2026-10-18, exited 5.41–6.01 s after the request in 10 of 10
    /// rounds, its window gone after 0.35–0.55 s; Tropy 1.17.2, 2026-10-22,
    /// exited 27.9 s after the request by its own log (Electron, no prompt),
    /// and about 40 s by `pgrep` in another round. Past the grace, such an app
    /// is given this long instead (`showsNoPrompt`). The signal only ever
    /// lengthens the wait, by at most this much, and the wait still ends the
    /// same way: if it misreads a prompt as a slow quit, the cost is a later
    /// `.wontQuit`, never a different one.
    public static let slowQuitTicks = 300

    /// One of the app's windows on screen (`onScreenWindows`).
    public struct OnScreenWindow: Hashable, Sendable {
        /// The window server's number for it, stable for the window's life.
        public let id: UInt32
        /// At the modal-panel level or above: an app-modal alert.
        public let isModalPanel: Bool

        public init(id: UInt32, isModalPanel: Bool) {
            self.id = id
            self.isModalPanel = isModalPanel
        }
    }

    /// Whether an app still running after the quit request shows nothing that
    /// could be holding the quit up: every window on screen now was already on
    /// screen when it was asked, and none is an app-modal alert.
    ///
    /// Measured with a test app, 2026-10-22: a slow quit (`.terminateLater`,
    /// answered after 6 s) kept its one window, same number, until it exited;
    /// every prompt arrived as a window with a new number — a save sheet at
    /// layer 0, a windowless `NSAlert.runModal` at layer 8 (the modal-panel
    /// level), and a save sheet on a hidden app un-hid its window, which came
    /// back on screen next to the sheet. An alert already up when asked is the
    /// layer-8 test: PicGo 3.0.2's own "Find new version" dialog held its quit
    /// (audit, PR #1574). UNVERIFIED: that dialog's layer — a sheet already up
    /// at the request is read as a slow quit, so it ends at `slowQuitTicks`.
    ///
    /// On-screen windows, not every window the server lists: AppKit keeps a
    /// closed window in `.optionAll` (offscreen), measured with a test app
    /// 2026-10-18, so closing windows reads as no prompt too. Also no prompt: a
    /// prompt drawn inside a window already up (a web view's own dialog), or
    /// raised on another Space. UNVERIFIED on a real app; either only moves
    /// the `.wontQuit` later, by at most `slowQuitTicks`, and a window that
    /// comes on screen ends the extension on that tick.
    public static func showsNoPrompt(atQuit: Set<OnScreenWindow>, now: Set<OnScreenWindow>) -> Bool {
        now.isSubset(of: atQuit) && !now.contains(where: \.isModalPanel)
    }

    /// What the app had on screen when a quit was given up on — for the line
    /// that says why it is still running. Only what is reported depends on it.
    ///
    /// "Likely a save prompt" was said for both, and is wrong for the second:
    /// Witsy 3.5.1, 2026-10-26, refused the quit (`general.keepRunning`, on by
    /// default) with no window and no prompt on screen, and the user was sent
    /// looking for a dialog that did not exist. Joplin, Lunatask (its own
    /// "update available" dialog) and Textream had one up.
    public enum QuitHoldup: Sendable, Equatable {
        /// A window of the app's own is on screen: a save or update prompt, a
        /// sign-in sheet — or just its main window, holding a prompt drawn
        /// inside it.
        case windowUp
        /// None of its own: it declined the quit with nothing to show, as an
        /// app that keeps running in the menu bar does. Also what a prompt on
        /// another Space, or a macOS prompt about the app (owned by a system
        /// process, FlowVision's TCC prompt on 2026-10-26), reads as — hence
        /// "may" in every line that says this.
        case nothingOnScreen

        /// From `onScreenWindows(pids:)`, which leaves out menu-bar extras.
        public init(windows: Set<OnScreenWindow>) {
            self = windows.isEmpty ? .nothingOnScreen : .windowUp
        }
    }

    /// How long a quit we asked for may still be answered. The menu-bar app's
    /// quit hand-off stays armed this long after `.wontQuit`; `duo restart` in a
    /// terminal keeps waiting this long instead (`QuitPatience`). Generous enough
    /// to answer a quit dialog after stepping away; short enough that a quit
    /// hours later is clearly the user closing the app, not that answer.
    public static let quitHandoffMaxAge: TimeInterval = 10 * 60

    /// How long the wait gives the app to quit before ending as `.wontQuit`.
    public struct QuitPatience: Sendable {
        /// Ticks from the quit request. Never shorter than `quitGraceTicks`.
        public let ticks: Int
        /// Called once, at `quitGraceTicks`, if the app is still up then and
        /// `ticks` goes past it — the moment the menu-bar app would have given
        /// up, so a caller that waits on can say why — from what is on screen
        /// then (`QuitHoldup`).
        public let onSlowQuit: (@Sendable (QuitHoldup) -> Void)?
        /// Asked each tick while the app has not quit yet, from `quitGraceTicks`
        /// on, and only then: true ends the wait the way an exhausted patience
        /// does (`.wontQuit`, the staged build left to its own updater).
        /// `duo restart`'s Ctrl-C. A closure, not task cancellation, so it still
        /// works where the caller shields this wait from cancellation.
        ///
        /// Not before `quitGraceTicks`. The quit has been requested by then, and
        /// an app still listed in its first moments is usually just shutting
        /// down: ending there would call a normal quit a save prompt, and skip
        /// the swap wait and the reopen after it — an app whose updater does not
        /// reopen it would be left closed. `quitGraceTicks` is where `.grace`
        /// gives up and where `onSlowQuit` says the quit is held up, so a stop
        /// asked for earlier — during the rollback copy, say — is answered
        /// there: still up, it ends the wait before `onSlowQuit` would offer a
        /// longer one; gone, the swap wait runs. A stop asked for before then
        /// therefore gets exactly the `.grace` wait. After the quit it is never
        /// asked: the swap wait and the reopen always run out.
        public let stopWaiting: @Sendable () -> Bool

        public init(
            ticks: Int, onSlowQuit: (@Sendable (QuitHoldup) -> Void)? = nil,
            stopWaiting: @escaping @Sendable () -> Bool = { false }
        ) {
            self.ticks = max(ticks, StagedRelaunch.quitGraceTicks)
            self.onSlowQuit = onSlowQuit
            self.stopWaiting = stopWaiting
        }

        /// The menu-bar app's: ~5 s, then `.wontQuit` and its quit hand-off.
        public static let grace = QuitPatience(ticks: StagedRelaunch.quitGraceTicks)

        /// `duo restart` in a terminal. A one-shot process cannot arm the
        /// menu-bar app's terminate observer, so it stays and waits for the
        /// answer itself, for as long as that hand-off would have stayed armed.
        public static func handoff(
            onSlowQuit: @escaping @Sendable (QuitHoldup) -> Void,
            stopWaiting: @escaping @Sendable () -> Bool = { false }
        ) -> QuitPatience {
            QuitPatience(ticks: Int(quitHandoffMaxAge * 5), onSlowQuit: onSlowQuit, stopWaiting: stopWaiting)
        }
    }

    /// How the wait ended.
    public struct Ending: Sendable, Equatable {
        public let outcome: StagedRelaunchOutcome
        /// Whether the app was seen gone at some tick.
        public let everQuit: Bool
        /// Whether the fallback launch at the end was needed and failed — the
        /// app is left closed.
        public let reopenFailed: Bool
        /// For `.wontQuit`: what the app had on screen when the wait gave up.
        /// Nil otherwise, and when the wait never sent the quit.
        public let holdup: QuitHoldup?

        public init(
            outcome: StagedRelaunchOutcome, everQuit: Bool, reopenFailed: Bool, holdup: QuitHoldup? = nil
        ) {
            self.outcome = outcome
            self.everQuit = everQuit
            self.reopenFailed = reopenFailed
            self.holdup = holdup
        }
    }

    /// The system calls the wait makes, injectable for tests.
    public struct System: Sendable {
        /// One ~200 ms tick of the poll.
        public var tick: @Sendable () async -> Void
        /// Whether any instance of the app (by bundle path) runs.
        public var isRunning: @Sendable () -> Bool
        /// Quit every running instance, gracefully.
        public var terminate: @Sendable () -> Void
        /// The version pair on disk now.
        public var diskVersion: @Sendable () async -> VersionSide
        /// Before launching a swap-on-launch app: let its helpers exit.
        public var awaitBundleProcessesGone: @Sendable () async -> Void
        /// Bring the app back up, retried while its bundle may be mid-swap.
        public var relaunch: @Sendable (_ activates: Bool) async -> Bool
        /// What `ParkedInstallerProbe.isAlive` asks.
        public var installer: ParkedInstallerProbe.System
        /// The app's windows on screen now, every instance (`onScreenWindows(pids:)`).
        public var onScreenWindows: @Sendable () -> Set<OnScreenWindow>

        public init(
            tick: @escaping @Sendable () async -> Void,
            isRunning: @escaping @Sendable () -> Bool,
            terminate: @escaping @Sendable () -> Void,
            diskVersion: @escaping @Sendable () async -> VersionSide,
            awaitBundleProcessesGone: @escaping @Sendable () async -> Void,
            relaunch: @escaping @Sendable (_ activates: Bool) async -> Bool,
            installer: ParkedInstallerProbe.System,
            onScreenWindows: @escaping @Sendable () -> Set<OnScreenWindow> = { [] }
        ) {
            self.tick = tick
            self.isRunning = isRunning
            self.terminate = terminate
            self.diskVersion = diskVersion
            self.awaitBundleProcessesGone = awaitBundleProcessesGone
            self.relaunch = relaunch
            self.installer = installer
            self.onScreenWindows = onScreenWindows
        }

        public static func live(for app: InstalledApp) -> System {
            System(
                tick: { try? await Task.sleep(for: .milliseconds(200)) },  // cancel-ok: tick is called only by quitAndAwaitSwap, inside InstallCommit.run ("relaunch")
                isRunning: { !AppRestarter.runningInstances(of: app).isEmpty },
                terminate: { for instance in AppRestarter.runningInstances(of: app) { instance.terminate() } },
                diskVersion: {
                    let path = app.path
                    return await Task.detached(priority: .utility) { diskVersionSide(path) }.value
                },
                awaitBundleProcessesGone: { await AppRestarter.awaitBundleProcessesGone(app) },
                relaunch: { await AppRestarter.relaunchAfterSwap(app, activates: $0) },
                installer: .live,
                onScreenWindows: {
                    StagedRelaunch.onScreenWindows(pids: Set(AppRestarter.runningInstances(of: app).map(\.processIdentifier)))
                })
        }
    }

    /// Quit `app` and wait for its own updater to apply `staged`.
    ///
    /// The caller has already seen the app running and taken its rollback
    /// point (`StagedRelaunchBackup.take`) while the running build was still on
    /// disk.
    ///
    /// - Parameters:
    ///   - staged: the build being applied, or nil when its staging could not be
    ///     read (an armed Sparkle installer). Decides `.quit` vs `.launch`,
    ///     whether a reappearance ends the wait, and which installer is watched.
    ///   - old: what is installed now. The PAIR, not `shortVersion ?? buildVersion`.
    ///     That chain answers "1.0" for an app that ships every build under one
    ///     marketing version, and the landing test then compares "1.0" against
    ///     "1.0" forever — measured on Amp 2026-08-28, where this spun its full
    ///     900 ticks (189 s) and reported `applied=false` for a swap that had
    ///     already succeeded.
    ///   - wasFrontmost: sampled before the quit; whether a reopen activates.
    ///   - quitPatience: how long the app may take to quit. A quit after
    ///     `quitGraceTicks` still gets the swap wait it would have had from
    ///     there (`maxTicks - quitGraceTicks`).
    public static func quitAndAwait(
        _ app: InstalledApp, staged: StagedSelfUpdate?, old: VersionSide,
        wasFrontmost: Bool, quitPatience: QuitPatience = .grace, system: System
    ) async -> Ending {
        let buildIsDerived = AppScanner.buildVersionIsOverridden(bundleID: app.bundleID)
        // Spotify only swaps when its old build is opened again; ShipIt/Sparkle
        // swap on quit and must not be reopened early. See `StagedApplyTrigger`.
        let appliesOnLaunch = staged?.appliesOn == .launch
        // The installer parked on the quit, found while the app still runs so
        // its exit later means something. See `InstallerExitWatch`.
        let installerProbe = await ParkedInstallerProbe.find(
            for: app, staged: staged, system: system.installer)
        // From the quit on, the wait runs to its end (`InstallCommit`): a quit
        // with no reopen behind it would leave the user without the app, and the
        // live `tick` is a `try?` sleep that a cancel would turn into a spin. A
        // caller cancelled before this point has quit nothing — classified as
        // an app that never quit, which is what happened.
        let ending = try? await InstallCommit.run("relaunch") {
            await quitAndAwaitSwap(
                app, staged: staged, old: old, wasFrontmost: wasFrontmost,
                quitPatience: quitPatience, system: system, buildIsDerived: buildIsDerived,
                appliesOnLaunch: appliesOnLaunch, installerProbe: installerProbe)
        }
        return ending ?? Ending(
            outcome: StagedRelaunchOutcome.classify(
                landed: false, everQuit: false, reappearedWithoutLanding: false),
            everQuit: false, reopenFailed: false)
    }

    /// `quitAndAwait` from the quit on — its commit (`InstallCommit`).
    private static func quitAndAwaitSwap(
        _ app: InstalledApp, staged: StagedSelfUpdate?, old: VersionSide,
        wasFrontmost: Bool, quitPatience: QuitPatience, system: System,
        buildIsDerived: Bool, appliesOnLaunch: Bool, installerProbe: ParkedInstallerProbe?
    ) async -> Ending {
        var installerProbe = installerProbe
        Log.app.notice("relaunch-staged: quitting \(app.name, privacy: .public) (\(old.text(withBuild: true), privacy: .public)) — \(appliesOnLaunch ? "reopening it so its updater applies on launch" : "letting its own updater swap & relaunch (no reopen)", privacy: .public)\(installerProbe.map { ", watching installer \(String(describing: $0.target))" } ?? "", privacy: .public)")
        // Before the request: what it had on screen is the baseline for telling a
        // slow exit from a prompt (`showsNoPrompt`).
        let windowsAtQuit = system.onScreenWindows()
        system.terminate()

        // Wait for the updater. Success = on-disk version advances past `old`.
        // We deliberately do NOT reopen a swap-on-quit app while waiting —
        // that's what made ShipIt abort. See the tick constants above.
        var applied = false
        var everQuit = false
        var launchedAtTick: Int?
        // ShipIt only (`StagedUpdater.shipIt`): an app back up on the old bundle
        // has had its swap called off (a Squirrel.Mac build with the
        // running-instances check aborts with "App Still Running"; not every
        // bundled ShipIt has that check), so stop waiting ~1 s after
        // seeing that rather than at `maxTicks`. Sparkle swaps anyway and an
        // unreadable staging says nothing, so both get the full wait. Decided once,
        // from the staging as it stood before the quit, like `appliesOnLaunch`.
        // See `ReappearanceWatch`.
        var reappearance = ReappearanceWatch(for: staged)
        var reappearedWithoutLanding = false
        var installerExit = InstallerExitWatch(watching: installerProbe != nil)
        // `maxTicks` from the quit request, moved out by a quit later than
        // `quitGraceTicks` — which only a patience past the grace allows. Before
        // the quit the loop is bounded by the `.wontQuit` bail instead.
        var swapDeadline = maxTicks
        var slowQuitLogged = false
        var slowQuitNoted = false
        var holdup: QuitHoldup?
        var tick = -1
        while true {
            tick += 1
            guard tick < swapDeadline || !everQuit else { break }
            await system.tick()
            if RelaunchProgress.hasLanded(
                old: old, disk: await system.diskVersion(), buildIsDerived: buildIsDerived) {
                applied = true
                break
            }
            if let launchedAtTick {
                // Launched; the old build now quits by itself while its relauncher
                // swaps, so an empty instance list here is progress, not a failure
                // to relaunch. The fallback below covers one that never comes back.
                guard tick - launchedAtTick < postLaunchTicks else { break }
                continue
            }
            let runningNow = system.isRunning()
            if !runningNow {
                if !everQuit {
                    swapDeadline = max(maxTicks, tick + maxTicks - quitGraceTicks)
                }
                everQuit = true  // quit succeeded — now we're waiting on the swap
                if appliesOnLaunch {
                    await system.awaitBundleProcessesGone()
                    Log.app.notice("relaunch-staged: \(app.name, privacy: .public) quit — launching it to apply the staged build")
                    _ = await system.relaunch(wasFrontmost)
                    launchedAtTick = tick
                }
            } else if !everQuit && tick >= quitGraceTicks && tick < slowQuitTicks
                        && !quitPatience.stopWaiting()
                        && showsNoPrompt(atQuit: windowsAtQuit, now: system.onScreenWindows()) {
                // Nothing new on screen: exiting slowly, not held by a prompt. Keep
                // waiting; a window coming on screen ends this branch that tick, and
                // so does a stop (`duo restart`'s Ctrl-C), checked first.
                if !slowQuitLogged {
                    slowQuitLogged = true
                    Log.app.notice("relaunch-staged: \(app.name, privacy: .public) shows no prompt but is still exiting — waiting up to \(slowQuitTicks, privacy: .public) ticks for it")
                }
            } else if !everQuit && (tick >= quitPatience.ticks
                                    || (tick >= quitGraceTicks && quitPatience.stopWaiting())) {
                // Never quit → a save prompt (or similar) is keeping it up; the swap
                // can't start, so don't block the long window on it. The caller
                // decides what to arm for a quit that completes later.
                let held = QuitHoldup(windows: system.onScreenWindows())
                holdup = held
                Log.app.notice("relaunch-staged: \(app.name, privacy: .public) won't quit (\(String(describing: held), privacy: .public)) — leaving it staged")
                break
            } else if !everQuit && tick >= quitGraceTicks && !slowQuitNoted,
                      let onSlowQuit = quitPatience.onSlowQuit {
                slowQuitNoted = true
                let held = QuitHoldup(windows: system.onScreenWindows())
                Log.app.notice("relaunch-staged: \(app.name, privacy: .public) hasn't quit after the grace (\(String(describing: held), privacy: .public)) — waiting up to \(quitPatience.ticks, privacy: .public) ticks for it")
                onSlowQuit(held)
            }
            if reappearance.observe(tick: tick, running: runningNow, everQuit: everQuit) {
                Log.app.notice("relaunch-staged: \(app.name, privacy: .public) is running again on \(old.text(withBuild: true), privacy: .public) — its updater didn't swap; not waiting further")
                reappearedWithoutLanding = true
                break
            }
            // Asked only once the app is down: before that the watch does not
            // judge, and a ShipIt check can cost a `launchctl` run.
            var installerAlive = true
            if everQuit, var probe = installerProbe {
                installerAlive = await probe.isAlive(system: system.installer)
                installerProbe = probe
            }
            if installerExit.observe(tick: tick, installersAlive: installerAlive, everQuit: everQuit) {
                Log.app.notice("relaunch-staged: \(app.name, privacy: .public)'s installer exited and \(old.text(withBuild: true), privacy: .public) is still on disk — its updater didn't swap; not waiting further")
                break
            }
        }
        // Fallback: if ShipIt swapped but didn't relaunch (or never ran), bring the
        // app back so the user isn't left without it — in the background unless it
        // was the app in front when we quit it. `relaunch` retries, because this is
        // precisely where a launch fails: we may be racing a swap that's still
        // rewriting the bundle, and LaunchServices can't open one mid-write.
        if launchedAtTick != nil {
            // The disk read can see the swap a beat before the updater's own open
            // of the new build registers — don't race it into a second launch.
            for _ in 0..<settleTicks where !system.isRunning() {
                await system.tick()
            }
        }
        // Not after a reappearance: the app was just seen running, so there is
        // nothing to bring back, and if it is gone again in the instant since,
        // somebody closed it on purpose — a launch here would reopen it unasked.
        var reopenFailed = false
        if !reappearedWithoutLanding && !system.isRunning() {
            reopenFailed = !(await system.relaunch(wasFrontmost))
        }
        let outcome = StagedRelaunchOutcome.classify(
            landed: applied, everQuit: everQuit,
            reappearedWithoutLanding: reappearedWithoutLanding)
        Log.app.notice("relaunch-staged: \(app.name, privacy: .public) applied=\(applied, privacy: .public) outcome=\(String(describing: outcome), privacy: .public)")
        return Ending(
            outcome: outcome, everQuit: everQuit, reopenFailed: reopenFailed,
            holdup: outcome == .wontQuit ? holdup : nil)
    }

    /// Windows on screen owned by `pids`, below the status-bar level: normal
    /// windows, panels, and alerts at the modal-panel level all count; menu-bar
    /// extras and pop-up menus do not. Either way a misreading only moves the
    /// `.wontQuit` later, by at most `slowQuitTicks`. No permission needed: the
    /// probe that measured ChatGPT ran as a fresh LaunchAgent binary with no
    /// Screen Recording grant and counted its window; only window titles are
    /// withheld without it. Window numbers are not: a probe submitted to
    /// launchd, 2026-10-22, with `CGPreflightScreenCaptureAccess()` false, read
    /// a number for 38 of 38 windows and a title for 1.
    public static func onScreenWindows(pids: Set<pid_t>) -> Set<OnScreenWindow> {
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let modalPanel = Int(CGWindowLevelForKey(.modalPanelWindow))
        return Set(list.compactMap {
            guard let owner = $0[kCGWindowOwnerPID as String] as? pid_t, pids.contains(owner),
                  let layer = $0[kCGWindowLayer as String] as? Int,
                  layer >= 0 && layer < Int(CGWindowLevelForKey(.statusWindow)),
                  let id = $0[kCGWindowNumber as String] as? UInt32
            else { return nil }
            return OnScreenWindow(id: id, isModalPanel: layer >= modalPanel)
        })
    }

    /// Every window the server lists for `pids` — on screen or not, at any
    /// layer. `OpenConfirmationHold`'s count: a process held at the first-open
    /// prompt owned none in `.optionAll` (measured 2026-10-22), and counting
    /// offscreen windows and every layer only ever makes "held" rarer. No
    /// permission needed, as for `onScreenWindows(pids:)`.
    public static func ownedWindowCount(pids: Set<pid_t>) -> Int {
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return 0 }
        return list.filter {
            guard let owner = $0[kCGWindowOwnerPID as String] as? pid_t else { return false }
            return pids.contains(owner)
        }.count
    }

    /// Both version fields read straight from the bundle's `Info.plist` — not
    /// `Bundle(path:)`, which memoises per path and would answer with the build
    /// the swap just replaced.
    public static func diskVersionSide(_ bundle: URL) -> VersionSide {
        let info = BundleLayout.infoPlistURL(for: bundle)
        guard let data = try? Data(contentsOf: info),
              let dict = (try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil)) as? [String: Any]
        else { return VersionSide() }
        return VersionSide(
            marketing: VersionSide.plistVersionField(dict["CFBundleShortVersionString"]),
            build: VersionSide.plistVersionField(dict["CFBundleVersion"]))
    }
}
