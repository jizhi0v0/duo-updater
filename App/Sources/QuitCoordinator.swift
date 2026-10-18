import AppKit
import DuoUpdaterCore

/// The app delegate, which exists for one hook: `applicationShouldTerminate`.
///
/// Before it there was no delegate at all, so every quit — the popover's Quit,
/// the Diagnostics relaunch, logout, `kill` — ended the process mid-install, and
/// a Homebrew child then died on its next stdout write with the user's app
/// already deleted (plans/update-cancellation.md §2.5). What a quit does now is
/// `QuitGuard`'s call; this file only feeds it and carries the answer out.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        QuitCoordinator.shared.catchSIGTERM()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        QuitCoordinator.shared.shouldTerminate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        QuitCoordinator.shared.willTerminate()
    }
}

/// Holds a quit back until nothing of ours is in flight.
///
/// ## The one constraint everything here is shaped by
///
/// Returning `.terminateLater` makes AppKit run the main run loop in
/// `NSModalPanelRunLoopMode` until `reply(toApplicationShouldTerminate:)`
/// (Apple, `NSApplication.terminate(_:)`). The installs we wait for finish on the
/// main actor, so they must keep running in that mode. Measured on macOS 27 with
/// a standalone NSApplication (2026-10-18, plans/update-cancellation.md §6): they
/// do — a MainActor `Task`, `DispatchQueue.main.async` and `MainActor.run` all ran
/// during the wait — PROVIDED `terminate(_:)` was not called from inside a block
/// the main dispatch queue is draining. Called from one (a `Task { @MainActor }`,
/// a `DispatchQueue.main` block, a main-queue `DispatchSource`), none of the three
/// ran for the whole wait: the main queue is serial and the block that called
/// `terminate` never returns while the modal loop runs. That is a deadlock: the
/// install waits for the main queue, the quit waits for the install.
///
/// So a `terminate` that did not come from an Apple event is bounced once:
/// cancelled, and re-issued from a run-loop block (`RunLoop.perform`), which runs
/// outside any dispatch drain — measured the same day, all three ran again. A
/// quit Apple event (logout, Activity Monitor's Quit) cannot be bounced — cancelling
/// it would cancel the logout — and is taken where it arrives, AppKit's event
/// dispatch rather than a main-queue block. UNVERIFIED: that a real logout's quit
/// event reaches us outside a main-queue drain; not observed.
@MainActor
final class QuitCoordinator {
    static let shared = QuitCoordinator()

    /// What is in flight right now. Set at launch next to the self-update idle
    /// probe (`MenuBarLabel`), since both read the same model.
    var workProbe: (@MainActor () -> QuitGuard.Work)?

    /// A `.terminateLater` is outstanding and the waiter will reply.
    private var waiting = false
    /// The next `shouldTerminate` is the re-issued half of a bounce.
    private var bounced = false
    /// The quit in progress came from SIGTERM, not the user.
    private var fromSignal = false
    /// Run once the quit is certain (`applicationWillTerminate`) — the
    /// Diagnostics relaunch's `open -n`.
    private var onTerminate: (@MainActor () -> Void)?
    /// Retained: a dispatch source that is released stops delivering.
    private var sigtermSource: DispatchSourceSignal?

    private init() {}

    /// Quit, and run `work` once the quit is certain (after any wait, never on
    /// "Don't Quit"). For the Diagnostics relaunch, whose fresh copy must not
    /// start while this one is still finishing installs — or at all, if the user
    /// decides to stay.
    func terminate(thenRun work: @escaping @MainActor () -> Void) {
        onTerminate = work
        NSApp.terminate(nil)
    }

    func shouldTerminate() -> NSApplication.TerminateReply {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isQuitEvent = event.map {
            $0.eventClass == AEEventClass(kCoreEventClass)
                && $0.eventID == AEEventID(kAEQuitApplication)
        } ?? false
        if waiting {
            // Already quitting as soon as the work is done. A second Quit adds
            // nothing; a logout arriving now is let through to the same wait —
            // cancelling its event would cancel the logout.
            Log.app.notice("quit: asked again while waiting (quit event: \(isQuitEvent, privacy: .public))")
            return isQuitEvent ? .terminateLater : .terminateCancel
        }
        let work = workProbe?() ?? QuitGuard.Work()
        // Idle: today's behaviour, from wherever — a plain terminate cannot
        // deadlock, it never enters the modal loop.
        guard !work.isEmpty else { return .terminateNow }
        if !isQuitEvent && !bounced {
            // See the type comment: we may be inside a main-queue drain.
            bounced = true
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated { _ = NSApp.terminate(nil) }
            }
            return .terminateCancel
        }
        bounced = false
        let quitReason: UInt32? = event.flatMap { event in
            let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))
                ?? event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))
            return reason.map { $0.enumCodeValue != 0 ? $0.enumCodeValue : $0.typeCodeValue }
        }
        let reason: QuitGuard.Reason = fromSignal
            ? .signal
            : QuitGuard.reason(quitEventReason: quitReason, isQuitEvent: isQuitEvent)
        let decision = QuitGuard.decide(work, reason: reason)
        Log.app.notice("quit: \(String(describing: reason), privacy: .public) with \(work.displayNames.joined(separator: ", "), privacy: .public)\(work.unnamed ? " (+ unnamed)" : "", privacy: .public) in flight → \(String(describing: decision), privacy: .public)")
        switch decision {
        case .quitNow:
            return .terminateNow
        case .waitSilently:
            waitThenReply()
            return .terminateLater
        case .ask(let names):
            guard askQuitWhenDone(names) else {
                Log.app.notice("quit: user chose Don't Quit")
                onTerminate = nil
                fromSignal = false
                return .terminateCancel
            }
            waitThenReply()
            return .terminateLater
        }
    }

    func willTerminate() {
        onTerminate?()
        onTerminate = nil
    }

    /// "X is installing." — Quit When Done (default) / Don't Quit. Run here, in the
    /// bounced call, so the main queue keeps draining under the alert's modal loop
    /// as it does under the wait's (see the type comment): the installs it names
    /// carry on while the user reads it.
    ///
    /// Cancel goes here when it lands: a third button that cancels what is
    /// still cancellable and waits only for the rest (`QuitGuard.Decision`).
    private func askQuitWhenDone(_ names: [String]) -> Bool {
        let alert = NSAlert()
        switch names.count {
        case 0: alert.messageText = String(localized: "Updates are installing.")
        case 1: alert.messageText = String(localized: "\(names[0]) is installing.")
        default:
            let list = ListFormatter.localizedString(byJoining: names)
            alert.messageText = String(localized: "\(list) are installing.")
        }
        alert.addButton(withTitle: String(localized: "Quit When Done"))
        alert.addButton(withTitle: String(localized: "Don’t Quit"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Poll until nothing is in flight, then let the quit through.
    ///
    /// Polled, not observed: the work spans several models (`AppListModel`,
    /// `CLIToolsModel`, `XcodeDownloadCenter`) and the probe is the one place that
    /// already lists them. Half a second is invisible next to an install. No
    /// timeout of our own: under logout macOS decides how long it waits; for the
    /// user's own quit, the work finishing is the point.
    private func waitThenReply() {
        waiting = true
        Task { @MainActor in
            while !(workProbe?() ?? QuitGuard.Work()).isEmpty {
                try? await Task.sleep(for: .milliseconds(500))
            }
            Log.app.notice("quit: nothing in flight any more — quitting")
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    /// Turn SIGTERM into the same terminate a logout takes: no dialog, wait for
    /// the work, quit.
    ///
    /// A no-op handler rather than `SIG_IGN`: an ignored signal stays ignored
    /// across exec, so any child launched without resetting its signals would
    /// ignore SIGTERM too — `ChildProcess` resets them (swift-subprocess passes
    /// `POSIX_SPAWN_SETSIGDEF` for every signal), but whether Foundation's
    /// `Process` does is not documented. A caught signal goes back to its default
    /// in the child (POSIX `execve`). The dispatch source sees the signal either
    /// way — measured with a no-op handler, 2026-10-18.
    func catchSIGTERM() {
        guard sigtermSource == nil else { return }
        signal(SIGTERM) { _ in }
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                Log.app.notice("quit: SIGTERM received")
                QuitCoordinator.shared.fromSignal = true
                // From a main-queue block — `shouldTerminate` bounces it.
                NSApp.terminate(nil)
            }
        }
        source.resume()
        sigtermSource = source
    }
}

extension AppListModel {
    /// Everything of ours a quit would cut off, named as the quit dialog says it.
    ///
    /// The self-update idle probe (`MenuBarLabel`) reads a wider condition —
    /// `canRefresh` also counts scans and checks, which a quit interrupts
    /// harmlessly — and nothing outside this model. This one adds what runs
    /// beside it: Homebrew, command-line tools, the Xcode download center.
    var quitGuardWork: QuitGuard.Work {
        var unnamed = isInstallingAll || cliTools.updatingAll
        var names: [String] = []
        func name(_ id: String) -> String? {
            guard let row = results.first(where: { $0.id == id }) else {
                unnamed = true
                return nil
            }
            return row.app.name
        }
        // Any stage, `.queued` and `.checking` included: a rollback also writes
        // `.installing` here, and the stage cannot tell a real install's opening
        // check from a recheck (see `bundleChanges`). A recheck makes the dialog
        // appear for a second or two; missing an install deletes an app.
        names += installing.keys.sorted().compactMap(name)
        names += relaunching.sorted().compactMap(name)
        if brewUpgrading || homebrewUpdating { names.append("Homebrew") }
        names += upgradingFormulae.sorted()
        // `awaitingCheck`: the update has run, only the re-check is left.
        names += cliTools.updating.subtracting(cliTools.awaitingCheck)
            .map(\.kind.displayName).sorted()
        let xcode = XcodeDownloadCenter.shared
        if let active = xcode.activeID {
            names.append(xcode.items.first { $0.id == active }
                .map { "Xcode \($0.displayVersion)" } ?? "Xcode")
        }
        return QuitGuard.Work(names: names, unnamed: unnamed)
    }
}
