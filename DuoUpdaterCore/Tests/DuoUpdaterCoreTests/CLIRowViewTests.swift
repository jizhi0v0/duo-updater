import Foundation
import Testing
@testable import DuoUpdaterCore

/// `CLIRowSnapshot`: what the command-line tools' rows draw — the popover's
/// "Other tools" row, a workbench sidebar row and detail header, and the
/// workbench's Update All — each case asserting every surface from one
/// snapshot, so two surfaces cannot disagree about the same copy unseen.
@Suite struct CLIRowViewTests {

    typealias Snapshot = CLIRowSnapshot<String>
    typealias Group = InstallRowSmoothing<String>.GroupCancel

    /// The row's Cancel as the smoothing hands it over: a pending one is
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

    /// One copy's own Cancel while it runs, by phase: the spec.
    static func ownCancel(_ phase: CLIRunPhase, _ cancel: Cancel) -> Group? {
        switch (phase, cancel) {
        case (.idle, _): return nil
        // Its job has ended: a live Cancel would stop nothing (#1511).
        case (.awaitingCheck, .available), (.checkingAtTurn, .available): return nil
        case (_, .available): return Group(state: .available, pending: false, live: 1)
        case (_, .pending): return Group(state: .available, pending: true, live: 0)
        // Accepted and said on the line: no glyph.
        case (_, .cancelling): return nil
        case (_, .committing): return Group(state: .committing, pending: false, live: 0)
        case (_, .tooLate): return Group(state: .tooLate, pending: false, live: 0)
        case (_, .none): return nil
        }
    }

    /// Update All's header Cancel over the same one copy: never nil while it
    /// runs (#1498), "Cancelling…" for one being stopped.
    static func headerCancel(_ phase: CLIRunPhase, _ cancel: Cancel) -> Group {
        if phase == .idle { return Group(state: .committing, pending: false, live: 0) }
        if cancel == .cancelling { return Group(state: .cancelling, pending: false, live: 0) }
        return ownCancel(phase, cancel) ?? Group(state: .committing, pending: false, live: 0)
    }

    struct Case: CustomTestStringConvertible, Sendable {
        var phase: CLIRunPhase
        var batch: Bool
        var admin: Bool
        /// One-click, or no one-click and a command to copy.
        var oneClick: Bool
        var cancel: Cancel
        var testDescription: String {
            "\(phase) \(batch ? "batch" : "single") \(admin ? "admin" : "plain") \(oneClick ? "oneClick" : "manual") \(cancel)"
        }
    }

    static let cases: [Case] = {
        let phases: [CLIRunPhase] = [.idle, .queued, .running, .awaitingCheck, .checkingAtTurn]
        var all: [Case] = []
        for phase in phases {
            for batch in [false, true] {
                for admin in [false, true] {
                    for oneClick in [true, false] {
                        for cancel in Cancel.allCases {
                            all.append(Case(phase: phase, batch: batch, admin: admin, oneClick: oneClick, cancel: cancel))
                        }
                    }
                }
            }
        }
        return all
    }()

    /// One copy, "a", with an update on offer (or held back with a command to
    /// copy). In a batch, Update All runs and holds it — or, idle, has let it go.
    static func snapshot(_ c: Case) -> Snapshot {
        let tool = Snapshot.Tool(
            id: "a", kind: .uv, phase: c.phase,
            cancel: c.cancel.state, cancelPending: c.cancel == .pending, line: "Downloading…",
            state: .updateAvailable, oneClick: c.oneClick, needsAdministrator: c.admin,
            manualCommand: c.oneClick ? nil : "uv self update")
        return Snapshot(
            tools: [tool], updatingAll: c.batch,
            batchIDs: c.batch && c.phase != .idle ? ["a"] : [],
            updateAllOffered: c.oneClick, updateAllStartable: c.oneClick && c.phase == .idle)
    }

    @Test(arguments: cases) func everySurfaceFromOneSnapshot(_ c: Case) {
        let s = Self.snapshot(c)
        let running = c.phase != .idle
        let own = Self.ownCancel(c.phase, c.cancel)
        let runningSlot: CLIRowState<String> = own.map(CLIRowState.cancel) ?? .spinnerOnly
        let progress: CLIProgressLine = c.cancel == .cancelling ? .cancelling : .line("Downloading…")

        // Sidebar.
        let sidebar = s.sidebar("a")
        if running {
            #expect(sidebar.slot == runningSlot)
            #expect(sidebar.caption == .progress(progress))
        } else {
            #expect(sidebar.slot == (c.oneClick ? .update(admin: c.admin) : .copy("uv self update")))
            #expect(sidebar.caption == .status)
        }

        // Detail header.
        let header = s.detailHeader("a")
        if running {
            #expect(header == CLIDetailHeader(action: runningSlot, progress: progress))
        } else {
            #expect(header == CLIDetailHeader(action: c.oneClick ? .update(admin: c.admin) : .none, progress: nil))
        }

        // Popover.
        let popover = s.popover
        if running || c.batch {
            #expect(popover?.isRunning == true)
            #expect(popover?.mark == .spinner)
            #expect(popover?.button == (own.map(CLIRowState.cancel) ?? CLIRowState<String>.none))
            if c.phase == .idle || c.phase == .queued {
                #expect(popover?.lines == [.queued])
            } else {
                #expect(popover?.lines == [.updating(.uv), .progress(progress)])
            }
        } else if c.oneClick {
            #expect(popover == CLIPopoverRow(
                lines: [.updates(1)] + (c.admin ? [.needSudo(1)] : []),
                mark: nil, button: .update(admin: false), isRunning: false))
        } else {
            #expect(popover == CLIPopoverRow(lines: [.heldBack(1)], mark: nil, button: .none, isRunning: false))
        }

        // Update All header.
        if c.batch {
            #expect(s.updateAllHeader == .running(Self.headerCancel(c.phase, c.cancel)))
        } else if c.oneClick {
            #expect(s.updateAllHeader == .update(startable: !running))
        } else {
            #expect(s.updateAllHeader == .hidden)
        }
    }

    // MARK: - Replays

    /// Update All's header Cancel, when it shows one.
    static func headerCancel(_ s: Snapshot) -> Group? {
        guard case .running(let cancel) = s.updateAllHeader else { return nil }
        return cancel
    }

    /// #1506: a single click started from the workbench — the popover row
    /// has its Cancel too.
    @Test func aClickFromTheWorkbenchHasItsCancelOnThePopover() {
        let s = Snapshot(tools: [.init(id: "a", kind: .uv, phase: .running, cancel: .available,
                                       state: .updateAvailable, oneClick: true)])
        #expect(s.popover?.button == .cancel(Group(state: .available, pending: false, live: 1)))
    }

    /// #1515-1a: the row names a copy past its commit; its Cancel stops only
    /// the queued ones, and says so.
    @Test func aCancelOverOnlyQueuedCopiesSaysSo() {
        let s = Snapshot(tools: [
            .init(id: "go", kind: .uv, phase: .running, cancel: .committing, state: .updateAvailable, oneClick: true),
            .init(id: "x", kind: .npm, phase: .queued, cancel: .available, state: .updateAvailable, oneClick: true),
        ], updatingAll: true, updateAllWaiting: true, batchIDs: ["x"])
        #expect(s.popover?.button
            == .cancel(Group(state: .available, pending: false, live: 1, queuedOnly: true)))
    }

    /// #1520-1: one copy being stopped beside one past its commit says
    /// "Cancelling…" on the row and on the header alike.
    @Test func cancellingBesideCommittingSaysCancelling() {
        let s = Snapshot(tools: [
            .init(id: "claude", kind: .claudeCode, phase: .running, cancel: .committing, state: .updateAvailable, oneClick: true),
            .init(id: "pnpm", kind: .npm, phase: .running, cancel: .cancelling, state: .updateAvailable, oneClick: true),
        ], updatingAll: true, batchIDs: ["claude", "pnpm"])
        #expect(s.popover?.button == .cancel(Group(state: .cancelling, pending: false, live: 0)))
        #expect(Self.headerCancel(s).map { [$0.state] } == [.cancelling])
    }

    /// #1511-2: a job that ended with its Cancel still live — waiting on its
    /// check — has nothing to stop: no Cancel on its row, the popover's, or a
    /// live one on the header.
    @Test func aJobThatEndedHasNoCancel() {
        let s = Snapshot(tools: [.init(id: "a", kind: .uv, phase: .awaitingCheck, cancel: .available,
                                       line: "Waiting to check", state: .updateAvailable, oneClick: true)],
                         updatingAll: true, batchIDs: ["a"])
        #expect(s.sidebar("a").slot == .spinnerOnly)
        #expect(s.popover?.button == CLIRowState.none)
        #expect(Self.headerCancel(s).map { [$0.state] } == [.committing])
    }

    /// 4(a): a cancel accepted a moment ago reads the same on the header and
    /// on the row: greyed and pending on both, not "Cancelling…" on the
    /// header ~300 ms before the row.
    @Test func theHeaderAndTheRowSayCancellingTogether() {
        let s = Snapshot(tools: [.init(id: "a", kind: .uv, phase: .running, cancel: .available, cancelPending: true,
                                       state: .updateAvailable, oneClick: true)],
                         updatingAll: true, batchIDs: ["a"])
        let row = s.popover?.button
        #expect(row == .cancel(Group(state: .available, pending: true, live: 0)))
        let header = Self.headerCancel(s)
        #expect(header?.state == .available)
        #expect(header?.pending == true)
    }

    /// #1498: Update All running with none of its copies left — the header
    /// keeps a greyed Cancel, so its height does not move.
    @Test func theHeaderKeepsAGreyedCancelWithNoCopyLeft() {
        let s = Snapshot(tools: [.init(id: "a", kind: .uv, state: .updateAvailable, oneClick: true)],
                         updatingAll: true, batchIDs: [], updateAllOffered: true)
        #expect(Self.headerCancel(s).map { [$0.state] } == [.committing])
        #expect(Self.headerCancel(s)?.pending == false)
    }

    /// The two detail panes decide alike: Claude Code's header asks for an
    /// administrator password when its update does, as every other tool's.
    @Test func everyDetailHeaderSaysItAsksForAPassword() {
        let s = Snapshot(tools: [.init(id: "claude", kind: .claudeCode, state: .updateAvailable,
                                       oneClick: true, needsAdministrator: true)])
        #expect(s.detailHeader("claude").action == .update(admin: true))
    }

    // MARK: - Unlisted copies

    /// A copy still claimed that a check during its update no longer lists:
    /// it still runs, so the popover row is running, its Cancel reaches it,
    /// and Update All's header Cancel is live — as `updatingAll ||
    /// !updating.isEmpty`, `groupCancel(of: updating)` and `updateAllCancel`
    /// over `batchIDs` counted it at a82b2dd3. No row names it.
    @Test func aClaimedCopyTheCheckNoLongerListsStillCounts() {
        let gone = Snapshot.Tool(id: "gone", kind: .npm, phase: .running, cancel: .available)
        let single = Snapshot(tools: [.init(id: "a", kind: .uv)], unlisted: [gone])
        #expect(single.popover == CLIPopoverRow(
            lines: [.queued], mark: .spinner,
            button: .cancel(Group(state: .available, pending: false, live: 1)), isRunning: true))
        #expect(single.rowCancel == Group(state: .available, pending: false, live: 1))
        #expect(single.sidebar("a") == CLISidebarRow(slot: .none, caption: .status))

        let batch = Snapshot(tools: [.init(id: "a", kind: .uv)], unlisted: [gone],
                             updatingAll: true, batchIDs: ["gone"])
        #expect(batch.updateAllHeader == .running(Group(state: .available, pending: false, live: 1)))
    }

    // MARK: - Scoped rows

    /// An idle copy's own surfaces read neither its Cancel nor its line, so
    /// the app's per-copy builder may leave them out for an idle copy
    /// (`CLIToolsModel.rowTool`) without changing what is drawn.
    @Test(arguments: Cancel.allCases) func anIdleCopyDrawsTheSameWithoutItsCancelAndLine(_ cancel: Cancel) {
        for (oneClick, admin) in [(true, false), (true, true), (false, false)] {
            let bare = Snapshot.Tool(id: "a", kind: .claudeCode, state: .updateAvailable, oneClick: oneClick,
                                     needsAdministrator: admin, manualCommand: oneClick ? nil : "claude update")
            var stale = bare
            stale.cancel = cancel.state
            stale.cancelPending = cancel == .pending
            stale.line = "Downloading…"
            #expect(stale.sidebar == bare.sidebar)
            #expect(stale.detailHeader == bare.detailHeader)
            #expect(Snapshot(tools: [stale]).popover == Snapshot(tools: [bare]).popover)
        }
    }

    // MARK: - The popover's other rungs

    struct PopoverCase: CustomTestStringConvertible, Sendable {
        var name: String
        var snapshot: Snapshot
        /// What `MenuContentView.toolsHalf` drew at a82b2dd3.
        var expected: CLIPopoverRow<String>?
        var testDescription: String { name }
    }

    static let popoverCases: [PopoverCase] = [
        PopoverCase(
            // `outdated.compactMap { errors[$0] }.first`, red, with the Update.
            name: "error line",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv, state: .updateAvailable, oneClick: true),
                .init(id: "b", kind: .npm, state: .updateAvailable, oneClick: true, error: "npm ERR! b"),
            ], updateAllOffered: true, updateAllStartable: true),
            expected: CLIPopoverRow(lines: [.error("npm ERR! b")], mark: nil, button: .update(admin: false), isRunning: false)),
        PopoverCase(
            // An error on a copy that is not outdated is not the row's.
            name: "error on a current copy",
            snapshot: Snapshot(tools: [.init(id: "a", kind: .uv, state: .upToDate, error: "stale")]),
            expected: CLIPopoverRow(lines: [.upToDate], mark: .seal, button: .none, isRunning: false)),
        PopoverCase(
            // Nothing offered: the first held-back copy's reason, no held count at one.
            name: "withheld, one held",
            snapshot: Snapshot(tools: [.init(id: "a", kind: .fx, state: .updateAvailable, withheld: .autoUpdateOff)]),
            expected: CLIPopoverRow(lines: [.withheld("a", .autoUpdateOff)], mark: nil, button: .none, isRunning: false)),
        PopoverCase(
            // The first held-back copy WITH a reason, then "2 held back".
            name: "withheld, two held",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .fx, state: .updateAvailable),
                .init(id: "b", kind: .bun, state: .updateAvailable, withheld: .rateLimited),
            ]),
            expected: CLIPopoverRow(lines: [.withheld("b", .rateLimited), .heldBack(2)], mark: nil, button: .none, isRunning: false)),
        PopoverCase(
            // Held back without any reason: the count alone.
            name: "held back, no reason",
            snapshot: Snapshot(tools: [.init(id: "a", kind: .fx, state: .updateAvailable)]),
            expected: CLIPopoverRow(lines: [.heldBack(1)], mark: nil, button: .none, isRunning: false)),
        PopoverCase(
            // "1 updates · 1 need sudo · 2 held back", Update All live.
            name: "offered beside two held back",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv, state: .updateAvailable, oneClick: true, needsAdministrator: true),
                .init(id: "b", kind: .fx, state: .updateAvailable, withheld: .autoUpdateOff),
                .init(id: "c", kind: .bun, state: .updateAvailable),
            ], updateAllOffered: true, updateAllStartable: true),
            expected: CLIPopoverRow(lines: [.updates(1), .needSudo(1), .heldBack(2)], mark: nil,
                                    button: .update(admin: false), isRunning: false)),
        PopoverCase(
            // Offered but nothing startable: no button.
            name: "offered, not startable",
            snapshot: Snapshot(tools: [.init(id: "a", kind: .uv, state: .updateAvailable, oneClick: true)],
                               updateAllOffered: true, updateAllStartable: false),
            expected: CLIPopoverRow(lines: [.updates(1)], mark: nil, button: .none, isRunning: false)),
        PopoverCase(
            name: "not checked",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv, state: .unknown),
                .init(id: "b", kind: .fx, state: .unknown),
            ]),
            expected: CLIPopoverRow(lines: [.notChecked(2)], mark: .question, button: .none, isRunning: false)),
        PopoverCase(
            // The first unanswered copy with a reason says it.
            name: "not checked, with a reason",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv, state: .unknown),
                .init(id: "b", kind: .fx, state: .unknown, withheld: .channelUnreadable),
            ]),
            expected: CLIPopoverRow(lines: [.withheld("b", .channelUnreadable)], mark: .question, button: .none, isRunning: false)),
        PopoverCase(
            name: "updated, Claude Code",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv),
                .init(id: "c", kind: .claudeCode, justUpdated: "2.1.285"),
            ]),
            expected: CLIPopoverRow(lines: [.updated(.claudeCode, version: "2.1.285"), .takesEffect(.claudeCode)],
                                    mark: .seal, button: .none, isRunning: false)),
        PopoverCase(
            name: "updated, another tool",
            snapshot: Snapshot(tools: [.init(id: "a", kind: .uv, justUpdated: "0.9.1")]),
            expected: CLIPopoverRow(lines: [.updated(.uv, version: "0.9.1"), .takesEffect(.uv)],
                                    mark: .seal, button: .none, isRunning: false)),
        PopoverCase(
            name: "before the first check",
            snapshot: Snapshot(tools: [.init(id: "a", kind: .uv)], checked: false),
            expected: CLIPopoverRow(lines: [.checking], mark: .spinner, button: .none, isRunning: false)),
        PopoverCase(
            name: "no copy found",
            snapshot: Snapshot(tools: [], hasSightings: false),
            expected: nil),
        PopoverCase(
            // Two kinds running: no name, and the first running copy's line.
            name: "multi-kind head",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv, phase: .running, cancel: .committing, line: "Downloading uv"),
                .init(id: "b", kind: .npm, phase: .running, cancel: .committing, line: "added 1 package"),
            ], updatingAll: true, batchIDs: ["a", "b"]),
            expected: CLIPopoverRow(lines: [.updating(nil), .progress(.line("Downloading uv"))], mark: .spinner,
                                    button: .cancel(Group(state: .committing, pending: false, live: 0)), isRunning: true)),
        PopoverCase(
            // Two copies of one kind: its name.
            name: "one kind, two copies",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .npm, phase: .running, cancel: .committing, line: "added 1 package"),
                .init(id: "b", kind: .npm, phase: .running, cancel: .committing),
            ], updatingAll: true, batchIDs: ["a", "b"]),
            expected: CLIPopoverRow(lines: [.updating(.npm), .progress(.line("added 1 package"))], mark: .spinner,
                                    button: .cancel(Group(state: .committing, pending: false, live: 0)), isRunning: true)),
        PopoverCase(
            // One waiting on its check before one still running: the running
            // one is named and its line shown, not "Waiting to check".
            name: "awaitingCheck before running",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv, phase: .awaitingCheck, line: "Waiting to check"),
                .init(id: "b", kind: .npm, phase: .running, cancel: .committing, line: "added 1 package"),
            ], updatingAll: true, batchIDs: ["a", "b"]),
            expected: CLIPopoverRow(lines: [.updating(.npm), .progress(.line("added 1 package"))], mark: .spinner,
                                    button: .cancel(Group(state: .committing, pending: false, live: 0)), isRunning: true)),
        PopoverCase(
            // Every claimed one waits on its check: they are named, the first one's line.
            name: "all awaitingCheck",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv, phase: .awaitingCheck, line: "Waiting to check"),
                .init(id: "b", kind: .npm, phase: .awaitingCheck, line: "Checking…"),
            ], updatingAll: true, batchIDs: ["a", "b"]),
            expected: CLIPopoverRow(lines: [.updating(nil), .progress(.line("Waiting to check"))], mark: .spinner,
                                    button: .none, isRunning: true)),
        PopoverCase(
            // The first running copy WITH a line gives the row's line.
            name: "first running copy has no line",
            snapshot: Snapshot(tools: [
                .init(id: "a", kind: .uv, phase: .running, cancel: .available),
                .init(id: "b", kind: .uv, phase: .running, cancel: .cancelling, line: "Downloading"),
            ]),
            expected: CLIPopoverRow(lines: [.updating(.uv), .progress(.cancelling)], mark: .spinner,
                                    button: .cancel(Group(state: .available, pending: false, live: 1)), isRunning: true)),
    ]

    @Test(arguments: popoverCases) func thePopoversOtherRungs(_ c: PopoverCase) {
        #expect(c.snapshot.popover == c.expected)
    }
}
