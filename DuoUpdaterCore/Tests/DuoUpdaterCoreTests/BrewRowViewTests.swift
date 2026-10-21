import Foundation
import Testing
@testable import DuoUpdaterCore

/// `BrewRowSnapshot`: what the Homebrew rows draw — the popover's Homebrew
/// row, the workbench Brew group's Upgrade All, and a formula's sidebar row
/// and detail header — each case asserting every surface from one snapshot.
///
/// The expectations are the ladders the views and `AppListModel` ran at
/// 373f3d08 (`brewHalf`, `brewBulkUpgrade`, `BrewFormulaSidebarRow`,
/// `FormulaDetailPane.headerAction`, `BrewUpgradeCancelButton`,
/// `brewBulkProgressText`, `formulaProgressLine`, `isUpgrading`), written out
/// again here, not read off the new code. One rung differs on purpose: the
/// header's accepted Cancel (`intendedHeaderCancel`).
@Suite struct BrewRowViewTests {

    typealias Snapshot = BrewRowSnapshot
    typealias Group = InstallRowSmoothing<String>.GroupCancel

    static let all = "brew-upgrade-all"
    static let jq = "brew-formula:jq"

    /// A run's Cancel as the smoothing hands it over: a pending one is
    /// `.available` and in `cancelPending`.
    enum Cancel: CaseIterable, Sendable {
        case available, pending, cancelling, committing, tooLate, none
        var state: InstallCancelState? {
            switch self {
            case .available, .pending: .available
            case .cancelling: .cancelling
            case .committing: .committing
            case .tooLate: .tooLate
            case .none: nil
            }
        }
    }

    /// One run: its phase, and its Cancel while claimed.
    struct RunCase: Sendable, CustomStringConvertible {
        var phase: CLIRunPhase
        var cancel: Cancel
        var description: String { phase == .idle ? "idle" : "\(phase)/\(cancel)" }

        /// Idle has no Cancel: the app's builder reads none for an idle run.
        static let all: [RunCase] = [RunCase(phase: .idle, cancel: .none)]
            + [CLIRunPhase.queued, .running].flatMap { phase in Cancel.allCases.map { RunCase(phase: phase, cancel: $0) } }

        func run(_ id: String) -> Snapshot.Run {
            Snapshot.Run(id: id, phase: phase, cancel: cancel.state, cancelPending: cancel == .pending)
        }
    }

    struct Case: CustomTestStringConvertible, Sendable {
        var upgradeAll: RunCase
        /// jq's own upgrade.
        var jq: RunCase
        /// jq is outdated.
        var hasUpdate: Bool
        /// brew has written jq's phase word.
        var note: Bool
        /// jq's last upgrade failed.
        var error: Bool
        /// Upgrade All has its count: 1 of 3 poured.
        var counted: Bool
        var testDescription: String {
            "all \(upgradeAll) jq \(jq) \(hasUpdate ? "outdated" : "current") \(note ? "note" : "-") \(error ? "error" : "-") \(counted ? "counted" : "-")"
        }
    }

    static let cases: [Case] = RunCase.all.flatMap { upgradeAll in
        RunCase.all.flatMap { jq in
            [false, true].flatMap { hasUpdate in
                [false, true].flatMap { note in
                    [false, true].flatMap { error in
                        [false, true].map { counted in
                            Case(upgradeAll: upgradeAll, jq: jq, hasUpdate: hasUpdate, note: note, error: error, counted: counted)
                        }
                    }
                }
            }
        }
    }

    static func snapshot(_ c: Case) -> Snapshot {
        let jq = Snapshot.Formula(
            name: "jq", hasUpdate: c.hasUpdate, run: c.jq.run(Self.jq),
            // Only while its own upgrade runs: cleared with it.
            note: c.note && c.jq.phase != .idle ? "Downloading…" : nil,
            error: c.error ? "Error: jq" : nil)
        return Snapshot(
            upgradeAll: c.upgradeAll.run(Self.all),
            upgradeAllDone: c.counted ? 1 : 0, upgradeAllTotal: c.counted ? 3 : 0,
            formulae: [jq], outdated: c.hasUpdate ? 1 : 0)
    }

    // MARK: - The ladders at 373f3d08

    /// The smoothed Cancels as `brewCancelRows` held them.
    static func rows(_ c: Case) -> InstallRowSmoothing<String>.Output {
        var rows = InstallRowSmoothing<String>.Output()
        for (id, run) in [(Self.all, c.upgradeAll), (Self.jq, c.jq)] where run.phase != .idle {
            rows.cancels[id] = run.cancel.state
            if run.cancel == .pending { rows.cancelPending.insert(id) }
        }
        return rows
    }

    /// `BrewUpgradeCancelButton`: the row's Cancel unless "Cancelling…" is
    /// due; none without one.
    static func oldOwnButton(_ cancel: Cancel) -> Group? {
        switch cancel {
        case .available: Group(state: .available, pending: false, live: 1)
        case .pending: Group(state: .available, pending: true, live: 0)
        case .cancelling, .none: nil
        case .committing: Group(state: .committing, pending: false, live: 0)
        case .tooLate: Group(state: .tooLate, pending: false, live: 0)
        }
    }

    /// The one intended change: Upgrade All's accepted Cancel in the
    /// workbench header stays, greyed, "Cancelling…", as the tool groups'
    /// Update All does (#1498), instead of leaving the spinner alone.
    static func intendedHeaderCancel(_ cancel: Cancel) -> Group? {
        cancel == .cancelling ? Group(state: .cancelling, pending: false, live: 0) : oldOwnButton(cancel)
    }

    /// `brewBulkProgressText`.
    static func oldBulkText(_ c: Case) -> BrewProgressLine? {
        guard c.upgradeAll.phase != .idle else { return nil }
        if c.upgradeAll.phase == .queued { return .queued }
        if c.upgradeAll.cancel == .cancelling { return .cancelling }
        return c.counted ? .count(current: 2, total: 3) : nil
    }

    /// `formulaProgressLine("jq")`.
    static func oldFormulaLine(_ c: Case) -> BrewProgressLine? {
        if c.jq.phase != .idle, c.jq.cancel == .cancelling { return .cancelling }
        if c.note, c.jq.phase != .idle { return .note("Downloading…") }
        guard c.jq.phase != .idle else { return nil }
        return c.jq.phase == .queued ? .queued : .starting
    }

    /// `isUpgrading(jq)`.
    static func oldUpgrading(_ c: Case) -> Bool {
        c.jq.phase != .idle || (c.upgradeAll.phase == .running && c.hasUpdate)
    }

    @Test(arguments: cases) func everySurfaceFromOneSnapshot(_ c: Case) {
        let s = Self.snapshot(c)
        let upgrading = Self.oldUpgrading(c)
        let line = Self.oldFormulaLine(c)

        // Formula sidebar row and detail header.
        let row = s.formulaRow("jq")
        let slot: CLIRowState<String> = upgrading
            ? (c.jq.phase == .idle ? .spinnerOnly : Self.oldOwnButton(c.jq.cancel).map(CLIRowState.cancel) ?? .spinnerOnly)
            : c.hasUpdate ? .update(admin: false) : .none
        #expect(row?.slot == slot)
        if c.error {
            #expect(row?.caption == .error("Error: jq"))
        } else if upgrading, let line {
            #expect(row?.caption == .progress(line))
        } else {
            #expect(row?.caption == .status)
        }
        #expect(row?.progress == (upgrading ? line ?? .updating : nil))

        // Workbench Upgrade All.
        if !c.hasUpdate {
            #expect(s.upgradeAllHeader == .hidden)
        } else if c.upgradeAll.phase == .idle {
            #expect(s.upgradeAllHeader == .update)
        } else {
            #expect(s.upgradeAllHeader == .running(cancel: Self.intendedHeaderCancel(c.upgradeAll.cancel),
                                                   progress: Self.oldBulkText(c)))
        }

        // Popover.
        let claimed = [(Self.all, c.upgradeAll), (Self.jq, c.jq)].filter { $0.1.phase != .idle }
        guard !claimed.isEmpty else {
            #expect(s.popover?.isRunning == false)
            return
        }
        let head: String? = c.upgradeAll.phase == .running ? Self.all : c.jq.phase == .running ? Self.jq : nil
        let button = Self.rows(c).groupCancel(of: claimed.map(\.0), running: head.map { [$0] } ?? [])
        let lines: [BrewPopoverRow.Line]
        if c.upgradeAll.phase == .running {
            lines = [.progress(Self.oldBulkText(c) ?? .runningBrewUpgrade)]
        } else if c.jq.phase == .running {
            lines = [.upgrading("jq")] + (line.map { [.progress($0)] } ?? [])
        } else {
            lines = [.progress(.queued)]
        }
        #expect(s.popover == BrewPopoverRow(lines: lines, mark: .spinner,
                                            button: button.map(CLIRowState.cancel) ?? .none, isRunning: true))
    }

    // MARK: - Replays

    /// #1509: a formula's own upgrade started from the workbench — the
    /// popover row says so, and has its Cancel.
    @Test func aFormulaUpgradeFromTheWorkbenchHasItsCancelOnThePopover() {
        let s = Snapshot(formulae: [.init(name: "jq", run: .init(id: Self.jq, phase: .running, cancel: .available),
                                          note: "Downloading…")], outdated: 1)
        #expect(s.popover == BrewPopoverRow(
            lines: [.upgrading("jq"), .progress(.note("Downloading…"))], mark: .spinner,
            button: .cancel(Group(state: .available, pending: false, live: 1)), isRunning: true))
    }

    /// #1515 item 3: the queue hands jq its turn one main-actor hop before
    /// its run writes "Starting…" itself. In that hop the row already names
    /// it, and says "Starting…", not "Upgrading jq · Queued" — the row, its
    /// sidebar row and its detail header alike.
    @Test func theHopAfterItsTurnSaysStarting() {
        let s = Snapshot(formulae: [.init(name: "jq", run: .init(id: Self.jq, phase: .running, cancel: .available))],
                         outdated: 1)
        #expect(s.popover?.lines == [.upgrading("jq"), .progress(.starting)])
        #expect(s.formulaRow("jq")?.caption == .progress(.starting))
        #expect(s.formulaRow("jq")?.progress == .starting)

        let queued = Snapshot(formulae: [.init(name: "jq", run: .init(id: Self.jq, phase: .queued, cancel: .available))],
                              outdated: 1)
        #expect(queued.popover?.lines == [.progress(.queued)])
        #expect(queued.formulaRow("jq")?.caption == .progress(.queued))
    }

    /// The one intended change. Upgrade All's Cancel accepted, "Cancelling…"
    /// due: the workbench header keeps its Cancel, greyed, saying
    /// "Cancelling…", as the tool groups' Update All does — at 373f3d08
    /// `BrewUpgradeCancelButton` hid itself. The popover row, whose line says
    /// "Cancelling…", has none, as before.
    @Test func theHeaderGreysItsAcceptedCancelInsteadOfHidingIt() {
        let s = Snapshot(upgradeAll: .init(id: Self.all, phase: .running, cancel: .cancelling),
                         upgradeAllDone: 1, upgradeAllTotal: 3, outdated: 3)
        #expect(s.upgradeAllHeader == .running(cancel: Group(state: .cancelling, pending: false, live: 0),
                                               progress: .cancelling))
        #expect(s.popover == BrewPopoverRow(lines: [.progress(.cancelling)], mark: .spinner, button: .none,
                                            isRunning: true))
    }

    /// The header and the rows grey out together: they read the same
    /// smoothed Cancel, so a pending one is greyed on both at once, and one
    /// past brew's commit greys both. A formula Upgrade All covers has no
    /// Cancel of its own.
    @Test func theHeaderAndTheRowsGreyTogether() {
        for (cancel, pending) in [(InstallCancelState.available, true), (.committing, false)] {
            let s = Snapshot(upgradeAll: .init(id: Self.all, phase: .running, cancel: cancel, cancelPending: pending),
                             formulae: [.init(name: "jq", run: .init(id: Self.jq))], outdated: 1)
            let group = Group(state: cancel, pending: pending, live: 0)
            #expect(s.upgradeAllHeader == .running(cancel: group, progress: nil))
            #expect(s.popover?.button == .cancel(group))
            #expect(s.formulaRow("jq") == BrewFormulaRow(slot: .spinnerOnly, caption: .status, progress: .updating))
        }
    }

    /// "Upgrading jq · Installing…" with Upgrade All queued behind it: the
    /// row's live Cancel takes back only Upgrade All, and says so.
    @Test func aCancelOverOnlyTheQueuedSaysSo() {
        let s = Snapshot(upgradeAll: .init(id: Self.all, phase: .queued, cancel: .available),
                         formulae: [.init(name: "jq", run: .init(id: Self.jq, phase: .running, cancel: .committing),
                                          note: "Installing…")], outdated: 2)
        #expect(s.popover?.button == .cancel(Group(state: .available, pending: false, live: 1, queuedOnly: true)))
        #expect(s.upgradeAllHeader == .running(cancel: Group(state: .available, pending: false, live: 1),
                                               progress: .queued))
    }

    /// Through the smoothing, as the app hands the Cancels over: one formula
    /// upgrading, "Cancel update"; with Upgrade All past its start and two
    /// formulae, live while any can still be stopped; once the two a click
    /// stopped say "Cancelling…", greyed "Cancelling…" beside the one past
    /// its start — not "can't cancel now" (review, 2026-10-20, round 2) —
    /// and with only those two, none: their lines say it. (Moved from the
    /// app's `BrewRowRunsTests`.)
    @Test func theRowsCancelIsLiveWhileAnyRunCanBeStopped() {
        let t0 = ContinuousClock.now
        var smoothing = InstallRowSmoothing<String>()
        func snapshot(_ cancels: [String: InstallCancelState], at ms: Int, upgradeAll: Bool,
                      formulae names: [String]) -> Snapshot {
            let rows = smoothing.update(stages: [:], cancels: cancels, now: t0 + .milliseconds(ms))
            func run(_ id: String, _ phase: CLIRunPhase) -> Snapshot.Run {
                .init(id: id, phase: phase, cancel: rows.cancels[id], cancelPending: rows.cancelPending.contains(id))
            }
            return Snapshot(upgradeAll: run(Self.all, upgradeAll ? .running : .idle),
                            formulae: names.map { .init(name: $0, run: run("brew-formula:\($0)", .queued)) },
                            outdated: 3)
        }
        let go = "brew-formula:go"
        // `brew update`'s queued Cancel is not the row's.
        #expect(snapshot([go: .available, "brew-update": .available], at: 0, upgradeAll: false, formulae: ["go"])
            .rowCancel == Group(state: .available, pending: false, live: 1))
        #expect(snapshot([Self.all: .committing, go: .available, Self.jq: .available], at: 10,
                         upgradeAll: true, formulae: ["go", "jq"])
            .rowCancel == Group(state: .available, pending: false, live: 2, queuedOnly: true))
        let accepted: [String: InstallCancelState] = [Self.all: .committing, go: .cancelling, Self.jq: .cancelling]
        _ = snapshot(accepted, at: 20, upgradeAll: true, formulae: ["go", "jq"])
        #expect(snapshot(accepted, at: 400, upgradeAll: true, formulae: ["go", "jq"])
            .rowCancel == Group(state: .cancelling, pending: false, live: 0))
        #expect(snapshot(accepted, at: 410, upgradeAll: false, formulae: ["go", "jq"]).rowCancel == nil)
    }

    /// A Cancel that is gone while Upgrade All still runs — its job ended
    /// and a click found nothing — draws none on the header, as at 373f3d08:
    /// the greyed floor is for an accepted one only.
    @Test func aGoneCancelIsStillNone() {
        let s = Snapshot(upgradeAll: .init(id: Self.all, phase: .running), outdated: 1)
        #expect(s.upgradeAllHeader == .running(cancel: nil, progress: nil))
    }

    // MARK: - Scoped rows

    /// An idle formula's row reads neither its Cancel nor its note, so the
    /// app's per-formula builder leaves them out for an idle one without
    /// changing what is drawn — its row does not redraw with every line of
    /// another's upgrade.
    @Test(arguments: Cancel.allCases) func anIdleFormulaDrawsTheSameWithoutItsCancelAndNote(_ cancel: Cancel) {
        for (hasUpdate, upgradeAll) in [(true, CLIRunPhase.idle), (false, .idle), (true, .running), (true, .queued)] {
            let bare = Snapshot.Formula(name: "jq", hasUpdate: hasUpdate, run: .init(id: Self.jq))
            var stale = bare
            stale.run.cancel = cancel.state
            stale.run.cancelPending = cancel == .pending
            stale.note = "Downloading…"
            #expect(stale.row(upgradeAll: upgradeAll) == bare.row(upgradeAll: upgradeAll))
            #expect(Snapshot(formulae: [stale]).popover == Snapshot(formulae: [bare]).popover)
        }
    }

    /// A formula's row reads Upgrade All's phase alone, not its Cancel.
    @Test func aFormulaRowDoesNotReadUpgradeAllsCancel() {
        let formula = Snapshot.Formula(name: "jq", run: .init(id: Self.jq))
        let a = Snapshot(upgradeAll: .init(id: Self.all, phase: .running, cancel: .available), formulae: [formula])
        let b = Snapshot(upgradeAll: .init(id: Self.all, phase: .running, cancel: .cancelling), formulae: [formula])
        #expect(a.formulaRow("jq") == b.formulaRow("jq"))
    }

    // MARK: - The popover's other rungs

    struct PopoverCase: CustomTestStringConvertible, Sendable {
        var name: String
        var snapshot: Snapshot
        /// What `MenuContentView.brewHalf` drew at 373f3d08.
        var expected: BrewPopoverRow?
        var testDescription: String { name }
    }

    static let popoverCases: [PopoverCase] = [
        PopoverCase(name: "no Homebrew", snapshot: Snapshot(installed: false), expected: nil),
        PopoverCase(
            // Before the first verdict only.
            name: "first check",
            snapshot: Snapshot(checked: false),
            expected: BrewPopoverRow(lines: [.checking], mark: .spinner, button: .none, isRunning: false)),
        PopoverCase(
            // A count already up stays while the first check is not back.
            name: "outdated before the check",
            snapshot: Snapshot(checked: false, outdated: 2),
            expected: BrewPopoverRow(lines: [.updates(2)], mark: nil, button: .update(admin: false), isRunning: false)),
        PopoverCase(
            name: "updates, not checked, deprecated",
            snapshot: Snapshot(outdated: 2, unchecked: 1, deprecated: 3),
            expected: BrewPopoverRow(lines: [.updates(2), .notChecked(1), .deprecated(3)], mark: .unchecked,
                                     button: .update(admin: false), isRunning: false)),
        PopoverCase(
            // The last Upgrade All's failure in place of the count, with the Update.
            name: "upgrade error",
            snapshot: Snapshot(upgradeAllError: "Error: brew", outdated: 2, deprecated: 1),
            expected: BrewPopoverRow(lines: [.error("Error: brew"), .deprecated(1)], mark: nil,
                                     button: .update(admin: false), isRunning: false)),
        PopoverCase(
            // An error with nothing outdated is not said.
            name: "upgrade error, nothing outdated",
            snapshot: Snapshot(upgradeAllError: "Error: brew"),
            expected: BrewPopoverRow(lines: [.upToDate], mark: .seal, button: .none, isRunning: false)),
        PopoverCase(
            name: "not checked alone",
            snapshot: Snapshot(unchecked: 2, deprecated: 1),
            expected: BrewPopoverRow(lines: [.notChecked(2), .deprecated(1)], mark: .unchecked, button: .none,
                                     isRunning: false)),
        PopoverCase(
            name: "up to date, deprecated",
            snapshot: Snapshot(deprecated: 1),
            expected: BrewPopoverRow(lines: [.upToDate, .deprecated(1)], mark: .seal, button: .none, isRunning: false)),
        PopoverCase(
            // Upgrade All before it has its count.
            name: "Upgrade All, no count",
            snapshot: Snapshot(upgradeAll: .init(id: all, phase: .running, cancel: .available), outdated: 2),
            expected: BrewPopoverRow(lines: [.progress(.runningBrewUpgrade)], mark: .spinner,
                                     button: .cancel(Group(state: .available, pending: false, live: 1)), isRunning: true)),
        PopoverCase(
            // The count names the one being worked on, never past the total.
            name: "Upgrade All, last one",
            snapshot: Snapshot(upgradeAll: .init(id: all, phase: .running, cancel: .committing),
                               upgradeAllDone: 3, upgradeAllTotal: 3, outdated: 3),
            expected: BrewPopoverRow(lines: [.progress(.count(current: 3, total: 3))], mark: .spinner,
                                     button: .cancel(Group(state: .committing, pending: false, live: 0)), isRunning: true)),
        PopoverCase(
            // Two formulae of their own, one running: the running one is named,
            // whatever the order; one Cancel for both.
            name: "two formulae, the second running",
            snapshot: Snapshot(formulae: [
                .init(name: "zstd", run: .init(id: "brew-formula:zstd", phase: .queued, cancel: .available)),
                .init(name: "jq", run: .init(id: jq, phase: .running, cancel: .available), note: "Installing…"),
            ], outdated: 2),
            expected: BrewPopoverRow(lines: [.upgrading("jq"), .progress(.note("Installing…"))], mark: .spinner,
                                     button: .cancel(Group(state: .available, pending: false, live: 2)), isRunning: true)),
        PopoverCase(
            // A formula's own upgrade being cancelled: "Cancelling…", no Cancel.
            name: "formula cancelling",
            snapshot: Snapshot(formulae: [.init(name: "jq", run: .init(id: jq, phase: .running, cancel: .cancelling),
                                                note: "Downloading…")], outdated: 1),
            expected: BrewPopoverRow(lines: [.upgrading("jq"), .progress(.cancelling)], mark: .spinner,
                                     button: .none, isRunning: true)),
    ]

    @Test(arguments: popoverCases) func thePopoversOtherRungs(_ c: PopoverCase) {
        #expect(c.snapshot.popover == c.expected)
    }
}
