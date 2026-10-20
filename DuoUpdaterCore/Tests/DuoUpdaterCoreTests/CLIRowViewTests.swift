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
}
