import Foundation

/// Where one copy's update is, as the command-line tools' rows draw it.
///
/// One value per copy instead of the app's parallel sets (`updating`, `queued`,
/// `awaitingCheck`), so a later change can keep it as the copy's state itself.
public enum CLIRunPhase: Sendable, Equatable {
    /// Nothing of DuoUpdater's runs for it.
    case idle
    /// Claimed, waiting its turn: behind another click's run, or in a lane
    /// of Update All's that has not reached it.
    case queued
    /// Its turn has come: what comes before its command, or the command.
    case running
    /// Its update has run; its tool's re-check has not landed.
    case awaitingCheck
    /// At its turn its offer was gone, and its tool is asked again before
    /// the click is given up: "Checking…", and nothing to cancel.
    case checkingAtTurn
}

/// Everything the command-line tools' rows are drawn from — the popover's
/// "Other tools" row, the workbench sidebar's rows and detail headers, and
/// the workbench's Update All — as plain values, so what each one draws is a
/// pure function of it (`popover`, `sidebar(_:)`, `detailHeader(_:)`,
/// `updateAllHeader`) and every surface answers "is it running?" and "what
/// does its Cancel say?" the same way.
///
/// The Cancels and the progress lines are the rows' smoothed ones
/// (`InstallRowSmoothing.Output`), never the install's raw states: a surface
/// reading the raw ones said "Cancelling…" ~300 ms before the row beside it.
public struct CLIRowSnapshot<Key: Hashable & Sendable>: Equatable, Sendable {
    public typealias GroupCancel = InstallRowSmoothing<Key>.GroupCancel

    /// One copy, in the order its rows are listed.
    public struct Tool: Equatable, Sendable {
        public var id: Key
        public var kind: CLIToolKind
        public var phase: CLIRunPhase
        /// Its Cancel as the row draws it (`InstallRowSmoothing.Output.cancels`).
        public var cancel: InstallCancelState?
        /// Accepted, "Cancelling…" not shown yet (`Output.cancelPending`).
        public var cancelPending: Bool
        /// Its progress line for the stage the row shows
        /// (`InstallRowLines.line(_:shown:)`); nil while it has none.
        public var line: String?
        /// The stage `line` is a line of (`InstallRowLines.stage(_:shown:)`):
        /// tells a command's output from a stage word.
        public var lineStage: InstallStage?
        public var state: CLIToolState
        /// `CLIToolStatus.oneClick != nil`: every gate passed, the GitHub
        /// pause's included.
        public var oneClick: Bool
        public var needsAdministrator: Bool
        public var withheld: CLIToolWithheld?
        /// The command to copy when DuoUpdater will not run it.
        public var manualCommand: String?
        public var hasLatestVersion: Bool
        /// Its row's red line: the last failed update, or why a click was not run.
        public var error: String?
        /// "Updated to X", while it is said.
        public var justUpdated: String?
        /// What the popover's row names it by in place of its kind, for a
        /// kind whose name says nothing (`.managed`): its manager's group
        /// ("mise tools", `ManagerDescriptor.displayName`) and its own name
        /// ("node", `CLIToolStatus.name`). Nil for every other kind.
        public var groupTitle: String?
        public var itemTitle: String?

        public init(
            id: Key, kind: CLIToolKind, phase: CLIRunPhase = .idle,
            cancel: InstallCancelState? = nil, cancelPending: Bool = false, line: String? = nil,
            lineStage: InstallStage? = nil, state: CLIToolState = .upToDate, oneClick: Bool = false, needsAdministrator: Bool = false,
            withheld: CLIToolWithheld? = nil, manualCommand: String? = nil, hasLatestVersion: Bool = true,
            error: String? = nil, justUpdated: String? = nil, groupTitle: String? = nil, itemTitle: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.phase = phase
            self.cancel = cancel
            self.cancelPending = cancelPending
            self.line = line
            self.lineStage = lineStage
            self.state = state
            self.oneClick = oneClick
            self.needsAdministrator = needsAdministrator
            self.withheld = withheld
            self.manualCommand = manualCommand
            self.hasLatestVersion = hasLatestVersion
            self.error = error
            self.justUpdated = justUpdated
            self.groupTitle = groupTitle
            self.itemTitle = itemTitle
        }

        /// The same with **no defaults** — what the app builds its rows from
        /// (`RowStateTables.live`'s rule): a fact left out there must not
        /// compile into a plausible row.
        public static func live(
            id: Key, kind: CLIToolKind, phase: CLIRunPhase,
            cancel: InstallCancelState?, cancelPending: Bool, line: String?, lineStage: InstallStage?,
            state: CLIToolState, oneClick: Bool, needsAdministrator: Bool,
            withheld: CLIToolWithheld?, manualCommand: String?, hasLatestVersion: Bool,
            error: String?, justUpdated: String?, groupTitle: String?, itemTitle: String?
        ) -> Tool {
            Tool(id: id, kind: kind, phase: phase, cancel: cancel, cancelPending: cancelPending, line: line,
                 lineStage: lineStage, state: state, oneClick: oneClick, needsAdministrator: needsAdministrator,
                 withheld: withheld, manualCommand: manualCommand, hasLatestVersion: hasLatestVersion,
                 error: error, justUpdated: justUpdated, groupTitle: groupTitle, itemTitle: itemTitle)
        }

        /// Its Cancel as every surface counts it. A live one on a copy whose
        /// job has ended — its update ran and waits on its check, or its turn
        /// is asking its tool again — stops nothing: there is no Cancel then
        /// (#1511: one kept live through the re-check went away when clicked).
        var countedCancel: InstallCancelState? {
            switch phase {
            case .awaitingCheck, .checkingAtTurn:
                return cancel == .available && !cancelPending ? nil : cancel
            case .idle, .queued, .running:
                return cancel
            }
        }

        /// Its progress as its rows word it: "Cancelling…" once that is due,
        /// else its line; nil while it has none.
        var progress: CLIProgressLine? {
            if cancel == .cancelling { return .cancelling }
            return line.map(CLIProgressLine.line)
        }

        /// Its progress as the popover's row words it: none while its line is
        /// its command running — "Starting…", "Running as root…" or an
        /// output line — the row's "Updating npm" says that. The wait for an
        /// administrator password asks something of whoever reads it, so it
        /// stays.
        var popoverProgress: CLIProgressLine? {
            guard progress != .cancelling, case .runningCommand = lineStage,
                  line != CLIToolAdministratorRun.waitingLine else { return progress }
            return nil
        }

        /// What its own Update slot holds while it runs: its spinner, with its
        /// Cancel unless it has none to show (accepted and said on its line).
        private var runningSlot: CLIRowState<Key> {
            CLIRowSnapshot(tools: [self]).groupCancel(of: [id], running: [], floor: false)
                .map(CLIRowState.cancel) ?? .spinnerOnly
        }

        /// Its row in the workbench sidebar: the trailing slot and the caption.
        /// Its own facts alone, so a row is built and drawn from its copy only
        /// (`CLIRowSnapshot.sidebar(_:)` is this). Idle, it reads neither its
        /// Cancel nor its line.
        public var sidebar: CLISidebarRow<Key> {
            let slot: CLIRowState<Key>
            if phase != .idle {
                slot = runningSlot
            } else if oneClick {
                slot = .update(admin: needsAdministrator)
            } else if let manualCommand {
                slot = .copy(manualCommand)
            } else {
                slot = .none
            }
            let caption: CLISidebarRow<Key>.Caption
            if let error {
                caption = .error(error)
            } else if phase != .idle {
                caption = .progress(progress ?? .updating)
            } else if let justUpdated {
                caption = .updated(version: justUpdated, restartSessions: kind == .claudeCode)
            } else {
                caption = .status
            }
            return CLISidebarRow(slot: slot, caption: caption)
        }

        /// Its detail pane's header action: "Update to X", or the update's
        /// progress capsule with its Cancel. Never a command to copy — the pane
        /// says that further down. Its own facts alone, as `sidebar`.
        public var detailHeader: CLIDetailHeader<Key> {
            if phase != .idle {
                return CLIDetailHeader(action: runningSlot, progress: progress ?? .updating)
            }
            if oneClick, hasLatestVersion {
                return CLIDetailHeader(action: .update(admin: needsAdministrator), progress: nil)
            }
            return CLIDetailHeader(action: .none, progress: nil)
        }
    }

    public var tools: [Tool]
    /// Copies an update has claimed that the last check no longer lists — a
    /// check during the update found them gone or moved. They still run, so
    /// they count for whether the row is running and for every Cancel, but
    /// no row names them.
    public var unlisted: [Tool]
    /// Whether the scan found any copy at all: the popover's row is there.
    public var hasSightings: Bool
    /// Whether the first check has returned.
    public var checked: Bool
    /// True for the whole of Update All.
    public var updatingAll: Bool
    /// Update All waits behind another click's run.
    public var updateAllWaiting: Bool
    /// The copies the running Update All still holds.
    public var batchIDs: Set<Key>
    /// Update All has anything on offer, running or not.
    public var updateAllOffered: Bool
    /// Update All has anything to start now.
    public var updateAllStartable: Bool

    /// Update All still has something to run: it waits its turn, or holds a
    /// copy. Every copy is claimed at its click and released only when its
    /// part is done, so with neither left `updatingAll` is just the moment
    /// before `endUpdateAll()` — drawn as ended: a frame drawn in it said
    /// "Queued" between the last "Checking…" and the idle row (2026-10-21).
    private var updateAllRuns: Bool { updatingAll && (updateAllWaiting || !batchIDs.isEmpty) }

    public init(
        tools: [Tool] = [], unlisted: [Tool] = [], hasSightings: Bool = true, checked: Bool = true,
        updatingAll: Bool = false, updateAllWaiting: Bool = false, batchIDs: Set<Key> = [],
        updateAllOffered: Bool = false, updateAllStartable: Bool = false
    ) {
        self.tools = tools
        self.unlisted = unlisted
        self.hasSightings = hasSightings
        self.checked = checked
        self.updatingAll = updatingAll
        self.updateAllWaiting = updateAllWaiting
        self.batchIDs = batchIDs
        self.updateAllOffered = updateAllOffered
        self.updateAllStartable = updateAllStartable
    }

    /// The same with **no defaults** — see `Tool.live`.
    public static func live(
        tools: [Tool], unlisted: [Tool], hasSightings: Bool, checked: Bool,
        updatingAll: Bool, updateAllWaiting: Bool, batchIDs: Set<Key>,
        updateAllOffered: Bool, updateAllStartable: Bool
    ) -> CLIRowSnapshot {
        CLIRowSnapshot(tools: tools, unlisted: unlisted, hasSightings: hasSightings, checked: checked,
                       updatingAll: updatingAll, updateAllWaiting: updateAllWaiting, batchIDs: batchIDs,
                       updateAllOffered: updateAllOffered, updateAllStartable: updateAllStartable)
    }

    public func tool(_ id: Key) -> Tool? { tools.first { $0.id == id } ?? unlisted.first { $0.id == id } }

    /// Every copy the snapshot knows, listed or not.
    private var everyCopy: [Tool] { tools + unlisted }

    /// The same snapshot over the copies `scope` names only: one tool group's
    /// popover sub-row, or a manager's own level in the workbench. Update All
    /// counts for it only while it holds a copy of `scope` — one started for
    /// another group is not this group's run. `offered` and `startable` are
    /// Update All's over `scope`, which only the model can say.
    public func scoped(to scope: Set<Key>, updateAllOffered offered: Bool, updateAllStartable startable: Bool) -> CLIRowSnapshot {
        let batch = batchIDs.intersection(scope)
        let tools = tools.filter { scope.contains($0.id) }
        // A batch waiting its turn holds every copy it claimed, so one that
        // holds none of `scope` waits for another group.
        let mine = updatingAll && !batch.isEmpty
        return CLIRowSnapshot(
            tools: tools, unlisted: unlisted.filter { scope.contains($0.id) }, hasSightings: !tools.isEmpty,
            checked: checked, updatingAll: mine, updateAllWaiting: mine && updateAllWaiting, batchIDs: batch,
            updateAllOffered: offered, updateAllStartable: startable)
    }

    // MARK: - Cancel

    /// The one Cancel aggregator: what a Cancel standing for the copies
    /// `scope` names draws (`InstallRowSmoothing.Output.groupCancel`), off the
    /// rows' smoothed Cancels. `running` is what its row's head names;
    /// `floor` keeps a greyed one where there would be none.
    public func groupCancel(of scope: Set<Key>, running: Set<Key>, floor: Bool) -> GroupCancel? {
        var rows = InstallRowSmoothing<Key>.Output()
        for tool in everyCopy where scope.contains(tool.id) {
            rows.cancels[tool.id] = tool.countedCancel
            if tool.cancelPending { rows.cancelPending.insert(tool.id) }
        }
        return rows.groupCancel(of: scope, running: running, floor: floor)
    }

    /// The popover row's Cancel: every copy the row says is updating, whichever
    /// click claimed it. The row's head names those not queued.
    public var rowCancel: GroupCancel? {
        let claimed = Set(everyCopy.lazy.filter { $0.phase != .idle }.map(\.id))
        let running = Set(everyCopy.lazy.filter { $0.phase != .idle && $0.phase != .queued }.map(\.id))
        return groupCancel(of: claimed, running: running, floor: false)
    }

    /// Update All's own Cancel in the workbench header, over the copies it
    /// still holds: never nil while it runs, so the header keeps its height
    /// (#1498). Nil when no Update All runs.
    public var updateAllCancel: GroupCancel? {
        guard updateAllRuns else { return nil }
        let group = groupCancel(of: batchIDs, running: [], floor: true)
        // Still waiting its turn, Update All itself leaves the queue on a click.
        if updateAllWaiting, let group, group.state != .available || group.pending {
            return GroupCancel(state: .available, pending: false, live: group.live)
        }
        return group
    }

    // MARK: - Surfaces

    /// The workbench sidebar's row of `id` (`Tool.sidebar`).
    public func sidebar(_ id: Key) -> CLISidebarRow<Key> {
        tool(id)?.sidebar ?? CLISidebarRow(slot: .none, caption: .status)
    }

    /// A detail pane's header action for `id` (`Tool.detailHeader`).
    public func detailHeader(_ id: Key) -> CLIDetailHeader<Key> {
        tool(id)?.detailHeader ?? CLIDetailHeader(action: .none, progress: nil)
    }

    /// The workbench's Update All for the tool groups.
    public var updateAllHeader: CLIUpdateAllHeader<Key> {
        if let cancel = updateAllCancel { return .running(cancel) }
        if updateAllOffered { return .update(startable: updateAllStartable) }
        return .hidden
    }

    /// The popover's "Other tools" row; nil when the scan found no copy.
    public var popover: CLIPopoverRow<Key>? {
        guard hasSightings else { return nil }
        typealias Row = CLIPopoverRow<Key>
        if updateAllRuns || everyCopy.contains(where: { $0.phase != .idle }) {
            let button = rowCancel.map(CLIRowState.cancel) ?? .none
            // A queued copy is not running.
            let claimed = tools.filter { $0.phase != .idle && $0.phase != .queued }
            if claimed.isEmpty {
                // Every copy claimed waits its turn behind another click's run.
                return Row(lines: [.queued], mark: .spinner, button: button, isRunning: true)
            }
            // `updateAll` runs several tools at once: then the row names none,
            // and the line is the first running copy's — one still running
            // its command before one waiting on its check. None while that
            // copy's command runs: "Updating npm" says it, and its output
            // showed for a frame after the head moved on to the next copy.
            let running = claimed.filter { $0.phase != .awaitingCheck }
            let named = running.isEmpty ? claimed : running
            let head = Self.updatingHead(named)
            let progress = named.first { $0.progress != nil }?.popoverProgress
            return Row(lines: [head] + (progress.map { [.progress($0)] } ?? []),
                       mark: .spinner, button: button, isRunning: true)
        }
        if !checked { return Row(lines: [.checking], mark: .spinner, button: .none, isRunning: false) }
        let outdated = tools.filter { $0.state == .updateAvailable }
        if !outdated.isEmpty {
            let button: CLIRowState<Key> = updateAllStartable ? .update(admin: false) : .none
            if let error = outdated.lazy.compactMap(\.error).first {
                return Row(lines: [.error(error)], mark: nil, button: button, isRunning: false)
            }
            // "Updates" are what the button updates; a held-back one is
            // counted apart.
            let held = outdated.filter { !$0.oneClick }
            let heldLine: [Row.Line] = held.isEmpty ? [] : [.heldBack(held.count)]
            let offered = outdated.filter(\.oneClick)
            if offered.isEmpty {
                // Nothing to click, so the row says why.
                guard let first = held.first(where: { $0.withheld != nil }), let withheld = first.withheld
                else { return Row(lines: heldLine, mark: nil, button: .none, isRunning: false) }
                return Row(lines: [.withheld(first.id, withheld)] + (held.count > 1 ? heldLine : []),
                           mark: nil, button: .none, isRunning: false)
            }
            let sudo = offered.filter(\.needsAdministrator).count
            return Row(lines: [.updates(offered.count)] + (sudo > 0 ? [.needSudo(sudo)] : []) + heldLine,
                       mark: nil, button: button, isRunning: false)
        }
        let unchecked = tools.filter { $0.state == .unknown }
        if !unchecked.isEmpty {
            // Not "up to date" while a copy went unanswered.
            if let first = unchecked.first(where: { $0.withheld != nil }), let withheld = first.withheld {
                return Row(lines: [.withheld(first.id, withheld)], mark: .question, button: .none, isRunning: false)
            }
            return Row(lines: [.notChecked(unchecked.count)], mark: .question, button: .none, isRunning: false)
        }
        // "3 updated" once several were: naming the first alone said "jq
        // updated to 1.8.2" after an update of mise tools' three (2026-10-24).
        let updatedCopies = tools.filter { $0.justUpdated != nil }
        if updatedCopies.count > 1 {
            // When it takes effect is said only while that is one answer.
            let kinds = Set(updatedCopies.map(\.kind))
            let effect: [Row.Line] = kinds.count == 1 ? kinds.map(Row.Line.takesEffect) : []
            return Row(lines: [.updatedCount(updatedCopies.count)] + effect, mark: .seal, button: .none, isRunning: false)
        }
        if let updated = updatedCopies.first, let version = updated.justUpdated {
            let line = updated.itemTitle.map { Row.Line.updatedItem($0, version: version) }
                ?? .updated(updated.kind, version: version)
            return Row(lines: [line, .takesEffect(updated.kind)],
                       mark: .seal, button: .none, isRunning: false)
        }
        return Row(lines: [.upToDate], mark: .seal, button: .none, isRunning: false)
    }

    /// "Updating npm" when every copy named is of one kind; "Updating mise
    /// tools" when they are one manager's items, since "Managed tools" names
    /// no manager; else "Updating command-line tools".
    static func updatingHead(_ named: [Tool]) -> CLIPopoverRow<Key>.Line {
        guard Set(named.map(\.kind)).count == 1, let first = named.first else { return .updating(nil) }
        guard first.kind == .managed else { return .updating(first.kind) }
        let groups = Set(named.map(\.groupTitle))
        guard groups.count == 1, let group = first.groupTitle else { return .updating(nil) }
        return .updatingGroup(group)
    }
}

/// What an Update slot holds.
public enum CLIRowState<Key: Hashable & Sendable>: Equatable, Sendable {
    /// Nothing.
    case none
    /// Update; `admin` when it asks for an administrator password.
    case update(admin: Bool)
    /// The command to copy.
    case copy(String)
    /// A spinner and this Cancel (`InstallCancelButton`).
    case cancel(InstallRowSmoothing<Key>.GroupCancel)
    /// A spinner alone: the Cancel was accepted, and the line says so.
    case spinnerOnly

    /// Whether an update runs in the slot: what its click guard is keyed on.
    public var isRunning: Bool {
        switch self {
        case .cancel, .spinnerOnly: return true
        case .none, .update, .copy: return false
        }
    }
}

/// A running copy's progress, as its rows word it.
public enum CLIProgressLine: Equatable, Sendable {
    /// "Cancelling…".
    case cancelling
    /// Its own line: "Queued", "Starting…", its command's output, "Checking…".
    case line(String)
    /// None yet: "Updating…".
    case updating
}

/// A workbench sidebar row of one copy.
public struct CLISidebarRow<Key: Hashable & Sendable>: Equatable, Sendable {
    public enum Caption: Equatable, Sendable {
        /// The red line.
        case error(String)
        case progress(CLIProgressLine)
        /// "Updated to X", and for Claude Code "restart open sessions".
        case updated(version: String, restartSessions: Bool)
        /// What the copy's status says: its warning, or its versions.
        case status
    }

    public var slot: CLIRowState<Key>
    public var caption: Caption
}

/// A detail pane's header action.
public struct CLIDetailHeader<Key: Hashable & Sendable>: Equatable, Sendable {
    /// `.update` is "Update to <latest>".
    public var action: CLIRowState<Key>
    /// The progress capsule's line; nil while nothing runs.
    public var progress: CLIProgressLine?
}

/// The workbench's Update All for the tool groups.
public enum CLIUpdateAllHeader<Key: Hashable & Sendable>: Equatable, Sendable {
    /// Nothing on offer and nothing running.
    case hidden
    /// The button, live when `startable`.
    case update(startable: Bool)
    /// Running or waiting: the button's place kept, its spinner and Cancel over it.
    case running(InstallRowSmoothing<Key>.GroupCancel)
}

/// The popover's "Other tools" row.
public struct CLIPopoverRow<Key: Hashable & Sendable>: Equatable, Sendable {
    /// One part of the row's second line, run together with " · ".
    public enum Line: Equatable, Sendable {
        case queued
        /// "Updating <kind>"; nil is "Updating command-line tools".
        case updating(CLIToolKind?)
        /// "Updating mise tools": one manager's items (`Tool.groupTitle`).
        case updatingGroup(String)
        case progress(CLIProgressLine)
        case checking
        /// In red.
        case error(String)
        case updates(Int)
        /// "N need sudo".
        case needSudo(Int)
        case heldBack(Int)
        /// Why the copy `Key` names was held back or left unanswered.
        case withheld(Key, CLIToolWithheld)
        case notChecked(Int)
        case updated(CLIToolKind, version: String)
        /// "node updated to 20.20.2": a managed item, by its own name.
        case updatedItem(String, version: String)
        /// "3 updated": more than one copy was.
        case updatedCount(Int)
        /// When the new version takes effect, which differs for Claude Code.
        case takesEffect(CLIToolKind)
        case upToDate
    }

    public enum Mark: Equatable, Sendable { case spinner, seal, question }

    public var lines: [Line]
    public var mark: Mark?
    /// The Update All button, or the row's Cancel.
    public var button: CLIRowState<Key>
    /// An update runs: what the button slot's click guard is keyed on.
    public var isRunning: Bool
}
