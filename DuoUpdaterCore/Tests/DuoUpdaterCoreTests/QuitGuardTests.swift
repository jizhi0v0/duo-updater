import Testing
@testable import DuoUpdaterCore

@Suite("QuitGuard")
struct QuitGuardTests {
    /// The four-character codes as the SDK's AERegistry.h spells them, built
    /// here from their letters rather than copied from `QuitGuard` — a typo in
    /// one of its constants has to show up as a failure, not be repeated.
    private static func code(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    // MARK: - Nothing in flight: today's behaviour, unchanged

    /// Whatever asked — the menu, the system, a signal — an idle app quits at
    /// once. A guard that held up an idle quit would make the app feel stuck.
    @Test("idle quits now, whatever the reason", arguments: [
        QuitGuard.Reason.user, .sessionEnding, .signal,
    ])
    func idleQuitsNow(reason: QuitGuard.Reason) {
        #expect(QuitGuard.decide(QuitGuard.Work(), reason: reason) == .quitNow)
    }

    // MARK: - Something in flight

    /// The user asked: ask them back, naming what is running.
    @Test("user quit mid-install asks, with the names")
    func userQuitAsks() {
        let work = QuitGuard.Work(names: ["Firefox", "ripgrep"])
        #expect(QuitGuard.decide(work, reason: .user) == .ask(["Firefox", "ripgrep"]))
    }

    /// Logout, restart, shutdown: nobody is there to answer a dialog, and one
    /// left up is what makes macOS report that the app cancelled the logout.
    @Test("session ending mid-install waits without asking")
    func sessionEndingWaits() {
        let work = QuitGuard.Work(names: ["Firefox"])
        #expect(QuitGuard.decide(work, reason: .sessionEnding) == .waitSilently)
    }

    /// `kill <pid>` has no one to ask either.
    @Test("SIGTERM mid-install waits without asking")
    func signalWaits() {
        let work = QuitGuard.Work(names: ["Firefox"])
        #expect(QuitGuard.decide(work, reason: .signal) == .waitSilently)
    }

    /// The gap inside a batch — one row finished, the next not yet claimed —
    /// has nothing to name, but the batch is still running. It must not read
    /// as idle, or a quit there walks straight into the next row's install.
    @Test("a nameless batch is still in flight")
    func batchWithoutNamesIsBusy() {
        let gap = QuitGuard.Work(names: [], unnamed: true)
        #expect(gap.isEmpty == false)
        #expect(QuitGuard.decide(gap, reason: .user) == .ask([]))
        #expect(QuitGuard.decide(gap, reason: .signal) == .waitSilently)
    }

    /// The same app can be in flight twice over (its row installing and its
    /// relaunch pending); the dialog names it once, in first-seen order.
    @Test("names are de-duplicated, order kept")
    func namesDeduplicated() {
        let work = QuitGuard.Work(names: ["Zed", "Arc", "Zed", "Arc", "Bear"])
        #expect(work.displayNames == ["Zed", "Arc", "Bear"])
        #expect(QuitGuard.decide(work, reason: .user) == .ask(["Zed", "Arc", "Bear"]))
    }

    // MARK: - Reading the quit Apple event's reason

    /// No quit event at all: `terminate(_:)` called from our own code — the
    /// menu's Quit button, the Diagnostics relaunch. That is the user.
    @Test("no Apple event is the user")
    func noEventIsUser() {
        #expect(QuitGuard.reason(quitEventReason: nil, isQuitEvent: false) == .user)
    }

    /// A quit event without a reason: Activity Monitor's Quit, `osascript -e
    /// 'quit app …'`. Someone chose to quit this app; they can answer.
    @Test("a quit event without a reason is the user")
    func quitEventWithoutReasonIsUser() {
        #expect(QuitGuard.reason(quitEventReason: nil, isQuitEvent: true) == .user)
    }

    /// Each reason AERegistry.h lists for `kAEQuitReason`, plus the logout and
    /// dialog variants beside them, means the session is ending.
    @Test("system quit reasons are a session ending", arguments: [
        "quia", "shut", "rest", "rlgo", "logo", "rrst", "rsdn",
    ])
    func systemReasons(reason: String) {
        #expect(QuitGuard.reason(quitEventReason: Self.code(reason), isQuitEvent: true)
            == .sessionEnding)
    }

    /// A reason code nobody documented is treated as the user, who can still
    /// say no — rather than as a logout, which would wait without a word.
    @Test("an unknown reason code is the user")
    func unknownReasonIsUser() {
        #expect(QuitGuard.reason(quitEventReason: Self.code("abcd"), isQuitEvent: true) == .user)
    }

    /// A reason attached to something that is not a quit event is not a quit
    /// reason.
    @Test("a reason on a non-quit event is ignored")
    func reasonOnOtherEventIgnored() {
        #expect(QuitGuard.reason(quitEventReason: Self.code("shut"), isQuitEvent: false) == .user)
    }

    // MARK: - Our own silent self-update

    /// Sparkle's installer quits us with a quit Apple event that carries no
    /// reason — the same shape as Activity Monitor's Quit. Nobody asked for it,
    /// so it must never put up the dialog (or activate the app): wait, then go.
    @Test("a self-update quit mid-work waits without asking")
    func selfUpdateWaits() {
        let work = QuitGuard.Work(names: ["ripgrep"])
        #expect(QuitGuard.decide(work, reason: .selfUpdate) == .waitSilently)
    }

    @Test("a self-update quit while idle quits now")
    func selfUpdateIdleQuitsNow() {
        #expect(QuitGuard.decide(QuitGuard.Work(), reason: .selfUpdate) == .quitNow)
    }

    /// While our self-update is installing, a reasonless quit event is Sparkle's,
    /// not the user's — and so is any other quit in that window.
    @Test("any quit during our self-update install is the self-update", arguments: [
        (UInt32?.none, true), (UInt32?.none, false),
    ])
    func selfUpdateReason(code: UInt32?, isQuitEvent: Bool) {
        #expect(QuitGuard.reason(quitEventReason: code, isQuitEvent: isQuitEvent,
                                 selfUpdateInstalling: true) == .selfUpdate)
        #expect(QuitGuard.reason(quitEventReason: code, isQuitEvent: isQuitEvent,
                                 selfUpdateInstalling: false) == .user)
    }

    // MARK: - What the self-update idle probe waits for

    /// The bug the review found: the self-update probe only read the list's own
    /// activity, so a Homebrew, CLI-tool or Xcode job alone looked idle, and the
    /// self-update quit walked into it. Each of them alone must block it.
    @Test("each job beside the list blocks the self-update on its own", arguments: [
        QuitGuard.work(rowNames: [], batchRunning: false, homebrewRunning: true,
                       formulae: [], cliTools: [], xcode: nil),
        QuitGuard.work(rowNames: [], batchRunning: false, homebrewRunning: false,
                       formulae: ["ripgrep"], cliTools: [], xcode: nil),
        QuitGuard.work(rowNames: [], batchRunning: false, homebrewRunning: false,
                       formulae: [], cliTools: ["Claude Code"], xcode: nil),
        QuitGuard.work(rowNames: [], batchRunning: false, homebrewRunning: false,
                       formulae: [], cliTools: [], xcode: "Xcode 27.1"),
        QuitGuard.work(rowNames: [nil], batchRunning: false, homebrewRunning: false,
                       formulae: [], cliTools: [], xcode: nil),
        QuitGuard.work(rowNames: [], batchRunning: true, homebrewRunning: false,
                       formulae: [], cliTools: [], xcode: nil),
    ])
    func sideJobsBlockSelfUpdate(work: QuitGuard.Work) {
        #expect(work.isEmpty == false)
        #expect(QuitGuard.selfUpdateMayInstall(listIdle: true, work: work) == false)
    }

    @Test("the self-update installs only when the list and the work are both idle")
    func selfUpdateNeedsBothIdle() {
        let none = QuitGuard.work(rowNames: [], batchRunning: false, homebrewRunning: false,
                                  formulae: [], cliTools: [], xcode: nil)
        #expect(none.isEmpty)
        #expect(QuitGuard.selfUpdateMayInstall(listIdle: true, work: none))
        #expect(QuitGuard.selfUpdateMayInstall(listIdle: false, work: none) == false)
    }

    /// Names in the order the dialog reads them; a row gone from the list is
    /// still busy, just nameless.
    @Test("gathered names keep their sources' order")
    func gatheredNames() {
        let work = QuitGuard.work(rowNames: ["Arc", nil], batchRunning: false,
                                  homebrewRunning: true, formulae: ["jq"],
                                  cliTools: ["uv"], xcode: "Xcode 27.1")
        #expect(work.names == ["Arc", "Homebrew", "jq", "uv", "Xcode 27.1"])
        #expect(work.unnamed)
    }
}
