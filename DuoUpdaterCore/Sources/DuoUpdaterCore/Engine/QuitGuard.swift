import Foundation

/// What to do when DuoUpdater is asked to quit, given what is in flight and who
/// asked.
///
/// Why this exists: before it, every quit ended the process at once, installs or
/// not. A Homebrew child outlives us in its own process group, but its stdout is
/// a pipe we held, and its next progress line — `==> Moving App`, printed between
/// deleting the old app and moving the new one in — dies on EPIPE. Its rescue
/// restores the Caskroom and exits, and the app is simply gone from
/// /Applications (plans/update-cancellation.md §2.5). Waiting for the in-flight
/// work is the fix; cancelling it is a later step (see `Decision`).
///
/// The policy, as decided (§9 Q4):
///   • nothing in flight → quit now, exactly as before;
///   • the user asked → ask them: "Quit When Done" or "Don't Quit";
///   • logout / restart / shutdown, or SIGTERM → nobody to ask; wait, then quit.
///
/// Pure, so the GUI's app delegate and anything the CLI grows can share it.
public enum QuitGuard {

    /// Who asked for the quit.
    public enum Reason: Sendable, Equatable {
        /// Someone chose to quit this app: our Quit button, the Diagnostics
        /// relaunch, Activity Monitor's (non-forced) Quit, `quit app` in a script.
        case user
        /// The login session is ending: logout, restart, shutdown.
        case sessionEnding
        /// SIGTERM — `kill <pid>`, launchd stopping a job.
        case signal
        /// Our own silent self-update is installing. Sparkle's installer quits us
        /// with a quit Apple event that carries no reason (Sparkle 2.10.0,
        /// `InstallerProgressAppController.sendTerminationSignal` →
        /// `-[NSRunningApplication terminate]`) — indistinguishable by the event
        /// from Activity Monitor's Quit, so it is told apart by our own flag
        /// (`reason(…selfUpdateInstalling:)`). Nobody asked for this quit, so it
        /// must never raise the dialog or activate the app, and after "Don't
        /// Quit" Sparkle would only send it again a minute later.
        case selfUpdate
    }

    /// The answer.
    ///
    /// There is deliberately no "cancel the work, then quit" yet. When cancelling
    /// lands (§5, §6) it belongs here as one more case — e.g. a third button that
    /// cancels what is still before its commit point and waits only for the rest
    /// — so the delegate keeps one place that decides.
    public enum Decision: Sendable, Equatable {
        /// Nothing of ours is in flight: terminate as usual.
        case quitNow
        /// Ask the user, naming what is in flight (may be empty: see
        /// `Work.unnamed`).
        case ask([String])
        /// Wait for the work to finish without asking, then quit.
        case waitSilently
    }

    /// What is in flight, as the quit dialog names it.
    public struct Work: Sendable, Equatable {
        /// Display names of everything running: app rows installing or relaunching,
        /// formulae upgrading, command-line tools updating, an Xcode install.
        /// Duplicates allowed — `displayNames` folds them.
        public var names: [String]
        /// Something is in flight that has no name to show: a batch between one
        /// row finishing and the next being claimed, or a row whose result has
        /// gone from the list. Busy all the same.
        public var unnamed: Bool

        public init(names: [String] = [], unnamed: Bool = false) {
            self.names = names
            self.unnamed = unnamed
        }

        /// Nothing at all is in flight.
        public var isEmpty: Bool { names.isEmpty && !unnamed }

        /// `names` with repeats removed, first-seen order kept — the same app can be
        /// both installing and awaiting relaunch, and is named once.
        public var displayNames: [String] {
            var seen: Set<String> = []
            return names.filter { seen.insert($0).inserted }
        }
    }

    public static func decide(_ work: Work, reason: Reason) -> Decision {
        guard !work.isEmpty else { return .quitNow }
        switch reason {
        case .user: return .ask(work.displayNames)
        case .sessionEnding, .signal, .selfUpdate: return .waitSilently
        }
    }

    // MARK: - The quit Apple event's reason

    /// `kAEQuitReason` values that mean the session is ending. AERegistry.h on
    /// `kAEQuitReason` ('why?'): "in a kAEQuitApplication event, this parameter if
    /// present is the reason the quit is being sent. The possible values are
    /// kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut". The logout and
    /// dialog variants declared next to them (`kAELogOut`, `kAEShowRestartDialog`,
    /// `kAEShowShutdownDialog`) are taken as the same thing; that macOS sends them
    /// as a quit reason is not documented and not observed.
    ///
    /// Spelled as integers so Core needs no CoreServices import; the tests rebuild
    /// each one from its four letters.
    static let sessionEndingReasons: Set<UInt32> = [
        0x7175_6961,  // 'quia' kAEQuitAll
        0x7368_7574,  // 'shut' kAEShutDown
        0x7265_7374,  // 'rest' kAERestart
        0x726C_676F,  // 'rlgo' kAEReallyLogOut
        0x6C6F_676F,  // 'logo' kAELogOut
        0x7272_7374,  // 'rrst' kAEShowRestartDialog
        0x7273_646E,  // 'rsdn' kAEShowShutdownDialog
    ]

    /// Classify a quit from the Apple event being handled when it arrived.
    ///
    /// - Parameters:
    ///   - quitEventReason: the event's `kAEQuitReason` code, if it carried one.
    ///   - isQuitEvent: the current Apple event is `kCoreEventClass`/`kAEQuitApplication`.
    ///     False — including no event at all — means `terminate(_:)` was called
    ///     from code: our Quit button, the relaunch, a script-less caller.
    ///
    /// An unrecognized reason counts as the user: the user can still say no to
    /// the dialog, while a wrong "session ending" would wait without a word.
    ///   - selfUpdateInstalling: our own self-update has been told to install and
    ///     relaunch. Wins over everything else: any quit in that window is either
    ///     Sparkle's or comes too late to be worth a question.
    public static func reason(
        quitEventReason: UInt32?, isQuitEvent: Bool, selfUpdateInstalling: Bool = false
    ) -> Reason {
        if selfUpdateInstalling { return .selfUpdate }
        guard isQuitEvent, let code = quitEventReason,
              sessionEndingReasons.contains(code) else { return .user }
        return .sessionEnding
    }

    // MARK: - Gathering the work, and the self-update's gate

    /// Build `Work` from what the app has in flight, in the order the dialog
    /// names it. Here rather than in the app so the one list both the quit guard
    /// and the self-update gate read is under test.
    ///
    /// - Parameters:
    ///   - rowNames: one entry per app row installing or relaunching; nil for a
    ///     row whose result has gone from the list (busy, nameless).
    ///   - batchRunning: an Update All, app or CLI tool, is running — covers the
    ///     moment between one row finishing and the next being claimed.
    ///   - homebrewRunning: `brew upgrade` of every formula, or `brew update`.
    ///   - formulae: formulae with a per-row `brew upgrade` in flight.
    ///   - cliTools: command-line tools whose update command is running.
    ///   - xcode: the Xcode download center's active item, if any.
    public static func work(
        rowNames: [String?], batchRunning: Bool, homebrewRunning: Bool,
        formulae: [String], cliTools: [String], xcode: String?
    ) -> Work {
        var names = rowNames.compactMap { $0 }
        if homebrewRunning { names.append("Homebrew") }
        names += formulae
        names += cliTools
        if let xcode { names.append(xcode) }
        return Work(names: names, unnamed: batchRunning || rowNames.contains(nil))
    }

    /// Whether the silent self-update may quit us now: the list is idle
    /// (`ListActivity.canRefresh`) AND nothing the quit guard counts is in
    /// flight. The list alone missed Homebrew, CLI tools and Xcode — the
    /// self-update then quit into them, and the guard put up a dialog nobody
    /// asked for.
    public static func selfUpdateMayInstall(listIdle: Bool, work: Work) -> Bool {
        listIdle && work.isEmpty
    }
}
