import Foundation

/// Everything the Homebrew rows are drawn from — the popover's Homebrew row,
/// the workbench Brew group's Upgrade All, and each formula's sidebar row and
/// detail header — as plain values, so what each one draws is a pure function
/// of it (`popover`, `upgradeAllHeader`, `Formula.row(upgradeAll:)`), as the
/// command-line tools' rows are (`CLIRowSnapshot`).
///
/// Each of our brew runs has one phase (`CLIRunPhase`): idle, queued behind
/// another click's run (`CLIRunQueue`), or running from its turn on. Before,
/// "queued or running" was asked of the queue in four places, one per surface.
///
/// The Cancels are the rows' smoothed ones (`InstallRowSmoothing.Output`),
/// keyed by the runs' registry ids, never the raw ones.
public struct BrewRowSnapshot: Equatable, Sendable {
    public typealias GroupCancel = InstallRowSmoothing<String>.GroupCancel

    /// One brew run of ours: Upgrade All, or one formula's own upgrade.
    public struct Run: Equatable, Sendable {
        /// Its registry id, which its Cancel is keyed by.
        public var id: String
        /// Idle, queued or running. A brew run has no check of its own to
        /// wait on: its re-read is part of its run.
        public var phase: CLIRunPhase
        /// Its Cancel as the rows draw it (`Output.cancels`).
        public var cancel: InstallCancelState?
        /// Accepted, "Cancelling…" not shown yet (`Output.cancelPending`).
        public var cancelPending: Bool

        public init(id: String, phase: CLIRunPhase = .idle, cancel: InstallCancelState? = nil,
                    cancelPending: Bool = false) {
            self.id = id
            self.phase = phase
            self.cancel = cancel
            self.cancelPending = cancelPending
        }

        /// The same with **no defaults** — what the app builds its rows from
        /// (`CLIRowSnapshot.Tool.live`'s rule).
        public static func live(id: String, phase: CLIRunPhase, cancel: InstallCancelState?,
                                cancelPending: Bool) -> Run {
            Run(id: id, phase: phase, cancel: cancel, cancelPending: cancelPending)
        }

        /// Claimed: queued or running.
        var isClaimed: Bool { phase != .idle }

        /// Its turn has come.
        var hasTurn: Bool { phase != .idle && phase != .queued }

        /// Its own Cancel, beside its own progress: what `InstallCancelButton`
        /// draws, nil once it was accepted and its line says "Cancelling…".
        /// An idle run has none, whatever is left in `cancel`.
        public var ownCancel: GroupCancel? {
            guard isClaimed else { return nil }
            return BrewRowSnapshot.groupCancel(of: [self], running: [], floor: false)
        }

        /// Its own slot while claimed: its spinner and its Cancel, or the
        /// spinner alone.
        var runningSlot: CLIRowState<String> {
            ownCancel.map(CLIRowState.cancel) ?? .spinnerOnly
        }
    }

    /// One installed formula, with its own upgrade.
    public struct Formula: Equatable, Sendable {
        public var name: String
        /// Outdated: what Upgrade All upgrades, and what its Update is for.
        public var hasUpdate: Bool
        /// Its own upgrade (`BrewRowRuns.formulaJobID`), idle when it has none.
        public var run: Run
        /// brew's phase word for its own upgrade ("Downloading…"), or the
        /// line its turn wrote; nil before either.
        public var note: String?
        /// Its last failed upgrade, red on its row.
        public var error: String?

        public init(name: String, hasUpdate: Bool = true, run: Run, note: String? = nil, error: String? = nil) {
            self.name = name
            self.hasUpdate = hasUpdate
            self.run = run
            self.note = note
            self.error = error
        }

        /// The same with **no defaults** — see `Run.live`.
        public static func live(name: String, hasUpdate: Bool, run: Run, note: String?,
                                error: String?) -> Formula {
            Formula(name: name, hasUpdate: hasUpdate, run: run, note: note, error: error)
        }

        /// Its own upgrade's line: "Cancelling…" once that is due, else
        /// brew's word, else "Queued" until its turn and "Starting…" from it
        /// on — the queue hands the turn over one main-actor hop before the
        /// run says so itself (`CLIRunQueue.advance`), and in that hop the
        /// popover row already named it: "Upgrading jq · Queued" (#1515).
        /// Nil without an upgrade of its own.
        var line: BrewProgressLine? {
            guard run.isClaimed else { return nil }
            if run.cancel == .cancelling { return .cancelling }
            if let note { return .note(note) }
            return run.phase == .queued ? .queued : .starting
        }

        /// Whether it is being upgraded: by its own upgrade, queued or not,
        /// or by an Upgrade All that has its turn, which upgrades every
        /// outdated formula. One answer for its row and its detail pane
        /// (2026-10-06: the pane offered Update while the row spun).
        func isUpgrading(upgradeAll: CLIRunPhase) -> Bool {
            run.isClaimed || (hasUpdate && upgradeAll != .idle && upgradeAll != .queued)
        }

        /// Its sidebar row and its detail header, given where Upgrade All is.
        /// Its own facts alone besides that, so a row is built and drawn from
        /// its formula only: idle, it reads neither its Cancel nor its note.
        public func row(upgradeAll: CLIRunPhase) -> BrewFormulaRow {
            let upgrading = isUpgrading(upgradeAll: upgradeAll)
            // One that only Upgrade All covers has no Cancel of its own.
            let slot: CLIRowState<String> = upgrading ? run.runningSlot : hasUpdate ? .update(admin: false) : .none
            let line = line
            let caption: BrewFormulaRow.Caption
            if let error {
                caption = .error(error)
            } else if upgrading, let line {
                caption = .progress(line)
            } else {
                caption = .status
            }
            return BrewFormulaRow(slot: slot, caption: caption, progress: upgrading ? line ?? .updating : nil)
        }
    }

    /// Upgrade All (`BrewRowRuns.upgradeAllJobID`).
    public var upgradeAll: Run
    /// How many of its targets it has poured, and how many it took at its
    /// turn; 0 of 0 until then.
    public var upgradeAllDone: Int
    public var upgradeAllTotal: Int
    /// Its last failure, red on the popover row.
    public var upgradeAllError: String?
    /// The formulae with an upgrade of their own claimed, for the popover
    /// row; any other listed formula changes nothing there.
    public var formulae: [Formula]
    /// Homebrew is installed: the popover's row is there.
    public var installed: Bool
    /// The first `brew outdated` has returned.
    public var checked: Bool
    /// Outdated formulae and app-less casks: what Upgrade All upgrades.
    public var outdated: Int
    /// Packages brew would not read.
    public var unchecked: Int
    /// Formulae and app-less casks Homebrew is phasing out.
    public var deprecated: Int

    public init(
        upgradeAll: Run = Run(id: "brew-upgrade-all"), upgradeAllDone: Int = 0, upgradeAllTotal: Int = 0,
        upgradeAllError: String? = nil, formulae: [Formula] = [], installed: Bool = true, checked: Bool = true,
        outdated: Int = 0, unchecked: Int = 0, deprecated: Int = 0
    ) {
        self.upgradeAll = upgradeAll
        self.upgradeAllDone = upgradeAllDone
        self.upgradeAllTotal = upgradeAllTotal
        self.upgradeAllError = upgradeAllError
        self.formulae = formulae
        self.installed = installed
        self.checked = checked
        self.outdated = outdated
        self.unchecked = unchecked
        self.deprecated = deprecated
    }

    /// The same with **no defaults** — see `Run.live`.
    public static func live(
        upgradeAll: Run, upgradeAllDone: Int, upgradeAllTotal: Int, upgradeAllError: String?,
        formulae: [Formula], installed: Bool, checked: Bool, outdated: Int, unchecked: Int, deprecated: Int
    ) -> BrewRowSnapshot {
        BrewRowSnapshot(upgradeAll: upgradeAll, upgradeAllDone: upgradeAllDone, upgradeAllTotal: upgradeAllTotal,
                        upgradeAllError: upgradeAllError, formulae: formulae, installed: installed,
                        checked: checked, outdated: outdated, unchecked: unchecked, deprecated: deprecated)
    }

    // MARK: - Cancel

    /// The one Cancel aggregator over brew runs: the merged
    /// `InstallRowSmoothing.Output.groupCancel` over their smoothed Cancels.
    static func groupCancel(of runs: [Run], running: Set<String>, floor: Bool) -> GroupCancel? {
        var rows = InstallRowSmoothing<String>.Output()
        for run in runs {
            rows.cancels[run.id] = run.cancel
            if run.cancelPending { rows.cancelPending.insert(run.id) }
        }
        return rows.groupCancel(of: runs.map(\.id), running: running, floor: floor)
    }

    /// The runs the popover row stands for: Upgrade All, and each formula's
    /// own upgrade from the workbench (#1509: the row showed nothing for
    /// one). Not `brew update`: the row neither shows nor counts it.
    var claimed: [Run] {
        ([upgradeAll] + formulae.sorted { $0.name < $1.name }.map(\.run)).filter(\.isClaimed)
    }

    /// The formula whose own upgrade has its turn, if one does — one brew run
    /// goes at a time (`CLIRunQueue`).
    var runningFormula: Formula? {
        formulae.sorted { $0.name < $1.name }.first { $0.run.hasTurn }
    }

    /// The run the popover row's head names: Upgrade All once it has its
    /// turn, else the formula that has; nil while every one waits.
    var headRun: Run? {
        upgradeAll.hasTurn ? upgradeAll : runningFormula?.run
    }

    /// The popover row's one Cancel, over every run it stands for. When none
    /// a click stops is the head's, its help says it stops the queued ones.
    public var rowCancel: GroupCancel? {
        Self.groupCancel(of: claimed, running: headRun.map { [$0.id] } ?? [], floor: false)
    }

    /// Upgrade All's own Cancel in the workbench header. As the tool groups'
    /// Update All's (`CLIRowSnapshot.updateAllCancel`, #1498), an accepted one
    /// stays, greyed, saying "Cancelling…", rather than leaving a spinner
    /// with nothing beside it; one that is gone (its job ended, a click it no
    /// longer had) is still none.
    public var upgradeAllCancel: GroupCancel? {
        guard upgradeAll.isClaimed else { return nil }
        return Self.groupCancel(of: [upgradeAll], running: [], floor: upgradeAll.cancel != nil)
    }

    /// Upgrade All's progress: "Queued" until its turn, "Cancelling…" once
    /// that is due, then "Upgrading… (x/n)", counting the one being worked
    /// on; nil before it has a count, or when it does not run.
    public var upgradeAllProgress: BrewProgressLine? {
        guard upgradeAll.isClaimed else { return nil }
        if upgradeAll.phase == .queued { return .queued }
        if upgradeAll.cancel == .cancelling { return .cancelling }
        guard upgradeAllTotal > 0 else { return nil }
        return .count(current: min(upgradeAllDone + 1, upgradeAllTotal), total: upgradeAllTotal)
    }

    // MARK: - Surfaces

    /// The formula `name`'s sidebar row and detail header (`Formula.row`);
    /// nil when the snapshot does not list it.
    public func formulaRow(_ name: String) -> BrewFormulaRow? {
        formulae.first { $0.name == name }?.row(upgradeAll: upgradeAll.phase)
    }

    /// The workbench Brew group's Upgrade All. Only while anything is
    /// outdated; while it runs, its progress and Cancel over it.
    public var upgradeAllHeader: BrewUpgradeAllHeader {
        guard outdated > 0 else { return .hidden }
        guard upgradeAll.isClaimed else { return .update }
        return .running(cancel: upgradeAllCancel, progress: upgradeAllProgress)
    }

    /// The popover's Homebrew row; nil without Homebrew.
    public var popover: BrewPopoverRow? {
        guard installed else { return nil }
        typealias Row = BrewPopoverRow
        let claimed = claimed
        if !claimed.isEmpty {
            // One Cancel where the Update button stood, for Upgrade All and
            // for a formula's own upgrade alike.
            let button = rowCancel.map(CLIRowState.cancel) ?? .none
            if upgradeAll.hasTurn {
                return Row(lines: [.progress(upgradeAllProgress ?? .runningBrewUpgrade)],
                           mark: .spinner, button: button, isRunning: true)
            }
            if let formula = runningFormula {
                return Row(lines: [.upgrading(formula.name)] + (formula.line.map { [.progress($0)] } ?? []),
                           mark: .spinner, button: button, isRunning: true)
            }
            // Every run it stands for waits its turn behind another click's.
            return Row(lines: [.progress(.queued)], mark: .spinner, button: button, isRunning: true)
        }
        // Before the first verdict only; a re-check keeps the last answer up.
        if outdated == 0 && !checked { return Row(lines: [.checking], mark: .spinner, button: .none, isRunning: false) }
        // Packages brew would not read stay said beside the updates: no count
        // here can include them. Deprecated ones are in neither count.
        let rest: [Row.Line] = (unchecked > 0 ? [.notChecked(unchecked)] : []) + (deprecated > 0 ? [.deprecated(deprecated)] : [])
        let uncheckedMark: Row.Mark? = unchecked > 0 ? .unchecked : nil
        if outdated > 0 {
            return Row(lines: [upgradeAllError.map(Row.Line.error) ?? .updates(outdated)] + rest,
                       mark: uncheckedMark, button: .update(admin: false), isRunning: false)
        }
        if unchecked > 0 { return Row(lines: rest, mark: uncheckedMark, button: .none, isRunning: false) }
        return Row(lines: [.upToDate] + rest, mark: .seal, button: .none, isRunning: false)
    }
}

/// A brew run's progress, as the Homebrew rows word it.
public enum BrewProgressLine: Equatable, Sendable {
    /// "Queued": waiting its turn.
    case queued
    /// "Starting…": its turn came, and brew has said nothing yet.
    case starting
    /// "Cancelling…".
    case cancelling
    /// brew's phase word ("Downloading…").
    case note(String)
    /// "Upgrading… (current/total)".
    case count(current: Int, total: Int)
    /// "Running brew upgrade…": Upgrade All before it has a count.
    case runningBrewUpgrade
    /// "Updating…": a formula Upgrade All covers, with no line of its own.
    case updating
}

/// A formula's sidebar row and detail header.
public struct BrewFormulaRow: Equatable, Sendable {
    public enum Caption: Equatable, Sendable {
        /// Its last failed upgrade, in red.
        case error(String)
        case progress(BrewProgressLine)
        /// What the formula says of itself: its versions, HEAD or lifecycle.
        case status
    }

    /// Its Update, or its spinner with its Cancel: the sidebar row's trailing
    /// slot and the detail header's action alike (`.update` there is the
    /// large "Update").
    public var slot: CLIRowState<String>
    public var caption: Caption
    /// The detail header's progress capsule; nil while it is not upgrading.
    public var progress: BrewProgressLine?
}

/// The workbench Brew group's Upgrade All.
public enum BrewUpgradeAllHeader: Equatable, Sendable {
    /// Nothing outdated.
    case hidden
    /// The button, never disabled: behind another run it waits its turn.
    case update
    /// Queued or running: the button's place kept, its progress, spinner and
    /// Cancel over it.
    case running(cancel: InstallRowSmoothing<String>.GroupCancel?, progress: BrewProgressLine?)
}

/// The popover's Homebrew row.
public struct BrewPopoverRow: Equatable, Sendable {
    /// One part of the row's second line, run together with " · ".
    public enum Line: Equatable, Sendable {
        case progress(BrewProgressLine)
        /// "Upgrading <formula>".
        case upgrading(String)
        case checking
        /// In red.
        case error(String)
        case updates(Int)
        case notChecked(Int)
        case deprecated(Int)
        case upToDate
    }

    /// `unchecked` is `BrewUncheckedMark`.
    public enum Mark: Equatable, Sendable { case spinner, seal, unchecked }

    public var lines: [Line]
    public var mark: Mark?
    /// Upgrade All, or the row's Cancel.
    public var button: CLIRowState<String>
    /// A brew run of ours is claimed: what the button slot's click guard is
    /// keyed on.
    public var isRunning: Bool
}
