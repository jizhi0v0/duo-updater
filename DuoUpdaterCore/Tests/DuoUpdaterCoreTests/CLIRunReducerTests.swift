import Foundation
import Testing
@testable import DuoUpdaterCore

/// `CLIRunReducer`: the command-line tools' runs as event sequences. Each test
/// sends what the app sends at each step — a click, a turn, an answer — and
/// asserts the state and what every surface draws from it after that step
/// (`CLIRowSnapshot`'s popover, sidebar, detail header and Update All), with
/// no model, no clock and no `until {}` polling. The bugs they replay were
/// windows between two awaits in `CLIToolsModel` (#1520, #1522, #1535, #1536).
@Suite struct CLIRunReducerTests {

    typealias State = CLIRunState<String>
    typealias Effect = CLIRunEffect<String>
    typealias Group = InstallRowSmoothing<String>.GroupCancel

    /// A Cancel one click stops.
    static let live = Group(state: .available, pending: false, live: 1)

    /// An fx copy at `path`, its key in these tests.
    static func fx(
        _ path: String, state: CLIToolState = .updateAvailable, oneClick: Bool = true, admin: Bool = false,
        latest: String = "1.1.0", withheld: CLIToolWithheld? = nil
    ) -> CLIToolStatus {
        CLIToolStatus(
            kind: .fx, path: path, installedVersion: "1.0.0", latestVersion: latest, channel: nil, state: state,
            oneClick: oneClick ? CLIToolCommand(executable: path, arguments: ["upgrade"], pathPrefix: nil) : nil,
            withheld: withheld, note: nil,
            detail: .fx(FxInstall(path: path, version: "1.0.0")), needsAdministrator: admin)
    }

    /// The app's side of a sequence, as much of it as the rows read: the lines
    /// and red lines the effects set, and whether Update All waits in the
    /// queue (`CLIRunQueue`, the app's). A class, so a step can be sent inside
    /// `#expect`; `copy` follows one run two ways. Every effect is kept, so a test can
    /// count the commands started. The answers the app feeds back — the
    /// queue's, the registry's — are sent by each test, as the steps they are.
    final class Run {
        var state = State()
        var lines: [String: String] = [:]
        var errors: [String: String] = [:]
        var effects: [Effect] = []
        var updateAllWaiting = false

        /// The same run, to follow two ways from one step.
        func copy() -> Run {
            let run = Run()
            run.state = state
            run.lines = lines
            run.errors = errors
            run.effects = effects
            run.updateAllWaiting = updateAllWaiting
            return run
        }

        @discardableResult
        func send(_ event: CLIRunEvent<String>) -> [Effect] {
            let (next, out) = CLIRunReducer.reduce(state, event)
            state = next
            for effect in out {
                switch effect {
                case .showLine(let id, let line): lines[id] = Self.text(line)
                case .clearLine(let id): lines[id] = nil
                case .sayNotRun(let id, let why): errors[id] = Self.text(why)
                default: break
                }
            }
            effects += out
            return out
        }

        /// The app's wording (`CLIToolsModel.perform`, `notRunLine`).
        static func text(_ line: CLIRunLine) -> String {
            switch line {
            case .queued: return "Queued"
            case .starting: return "Starting…"
            case .checking: return "Checking…"
            case .waitingToCheck: return "Waiting to check"
            case .output(let text): return text
            }
        }

        static func text(_ why: CLIRunNotRun) -> String {
            switch why {
            case .routeChanged(true): return "Not updated: it now asks for an administrator password — try again"
            case .routeChanged(false): return "Not updated: it no longer asks for an administrator password — try again"
            case .notOffered(let reason), .heldBack(let reason):
                return reason.map { "Not updated: \($0)" } ?? "Not updated: the update is no longer offered"
            case .silent: return ""
            }
        }

        /// Every surface for `statuses`, the copies' verdicts on screen now,
        /// as `CLIToolsModel.rowSnapshot` builds it — less the smoothing,
        /// whose clock these tests leave out.
        func snapshot(_ statuses: [CLIToolStatus]) -> CLIRowSnapshot<String> {
            let tools = statuses.map { status -> CLIRowSnapshot<String>.Tool in
                let id = status.path
                let phase = state.phase(id)
                let runs = phase != .idle
                return .live(
                    id: id, kind: status.kind, phase: phase,
                    cancel: runs ? state.cancels[id] : nil, cancelPending: false, line: runs ? lines[id] : nil,
                    state: status.state, oneClick: status.oneClick != nil,
                    needsAdministrator: status.needsAdministrator, withheld: status.withheld,
                    manualCommand: nil, hasLatestVersion: status.latestVersion != nil,
                    error: errors[id], justUpdated: nil)
            }
            let offered = statuses.filter { $0.state == .updateAvailable && $0.oneClick != nil }
            return .live(
                tools: tools, unlisted: [], hasSightings: true, checked: true,
                updatingAll: state.updatingAll, updateAllWaiting: updateAllWaiting, batchIDs: state.batchIDs,
                updateAllOffered: !offered.isEmpty,
                updateAllStartable: offered.contains { !state.updating.contains($0.path) })
        }

        /// How many times `id`'s command was started.
        func runs(of id: String) -> Int { effects.filter { $0 == .startCommand(id) }.count }
    }

    // MARK: - #1520: a click's offer read at its turn

    /// #1520: a click queued behind another run, whose offer a background
    /// check took away before its turn ("npm is busy": the run ahead of it).
    /// The turn reads the offer as it stands then, never the click's: gone,
    /// its tool is asked once more — "Checking…", no Cancel; still gone, the
    /// click goes away with its reason said, and nothing runs.
    @Test func clickWhoseOfferACheckTookAwayBeforeItsTurn() {
        let r = Run()
        let clicked = Self.fx("a")
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .queued, byUpdateAll: false))
        #expect(r.effects == [.showLine("a", .queued), .enqueue("a")])
        var s = r.snapshot([clicked])
        #expect(s.popover == CLIPopoverRow(lines: [.queued], mark: .spinner, button: .cancel(Self.live), isRunning: true))
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Queued"))))
        #expect(s.detailHeader("a") == CLIDetailHeader(action: .cancel(Self.live), progress: .line("Queued")))
        #expect(s.updateAllHeader == .update(startable: false))

        // A background check lands while it waits: its row still waits.
        let gone = Self.fx("a", state: .unknown, oneClick: false, withheld: .busy)
        s = r.snapshot([gone])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Queued"))))

        // Its turn.
        #expect(r.send(.turnCame("a")) == [])
        #expect(r.state.phase("a") == .running)
        let first = CLIRunOffer.atTurn(offered: nil, published: gone, heldByPause: false, asked: false,
                                       needsAdministrator: false)
        #expect(first == .askTool)
        #expect(r.send(.offerRead("a", first)) == [.showLine("a", .checking), .check("a")])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .checkingAtTurn, byUpdateAll: false))
        #expect(r.state.cancels["a"] == nil)
        s = r.snapshot([gone])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .spinnerOnly, caption: .progress(.line("Checking…"))))
        #expect(s.detailHeader("a") == CLIDetailHeader(action: .spinnerOnly, progress: .line("Checking…")))
        #expect(s.popover == CLIPopoverRow(lines: [.updating(.fx), .progress(.line("Checking…"))],
                                           mark: .spinner, button: .none, isRunning: true))
        #expect(s.updateAllHeader == .hidden)

        // Asked again, still not offered: not run, and why.
        let second = CLIRunOffer.atTurn(offered: nil, published: gone, heldByPause: false, asked: true,
                                        needsAdministrator: false)
        let busy = CLIToolWording.reason(.busy, of: gone)
        #expect(second == .notRun(.notOffered(reason: busy)))
        #expect(r.send(.offerRead("a", second)) == [.sayNotRun("a", .notOffered(reason: busy))])
        #expect(r.state.cancels["a"] == nil)
        r.send(.released("a"))
        #expect(r.state == State())
        #expect(r.runs(of: "a") == 0)
        s = r.snapshot([gone])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .none, caption: .error("Not updated: \(busy)")))
        #expect(s.detailHeader("a") == CLIDetailHeader(action: .none, progress: nil))
        #expect(s.popover == CLIPopoverRow(lines: [.withheld("a", .busy)], mark: .question, button: .none, isRunning: false))
        #expect(s.updateAllHeader == .hidden)
    }

    /// The same turn, where the tool asked again offers it after all: its
    /// Cancel comes back, and it runs once, as it stands now.
    @Test func clickWhoseToolAskedAtItsTurnOffersItAgainRunsOnce() {
        let r = Run()
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
        r.send(.turnCame("a"))
        r.send(.offerRead("a", .askTool))
        let back = Self.fx("a", latest: "1.2.0")
        let offer = CLIRunOffer.atTurn(offered: back, published: back, heldByPause: false, asked: true,
                                       needsAdministrator: false)
        #expect(offer == .run(back))
        #expect(r.send(.offerRead("a", offer)) == [.startCommand("a")])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .running, byUpdateAll: false))
        #expect(r.state.cancels["a"] == .available)
        r.send(.commandStarting("a"))
        let s = r.snapshot([back])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Starting…"))))
        #expect(s.popover == CLIPopoverRow(lines: [.updating(.fx), .progress(.line("Starting…"))],
                                           mark: .spinner, button: .cancel(Self.live), isRunning: true))
        #expect(r.runs(of: "a") == 1)
    }

    /// Updated from a terminal before its turn: asked, its tool says it is
    /// current, and the row says that by itself — no red line.
    @Test func clickWhoseToolWasUpdatedFromATerminalBeforeItsTurn() {
        let r = Run()
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
        r.send(.turnCame("a"))
        let current = Self.fx("a", state: .upToDate, oneClick: false)
        let first = CLIRunOffer.atTurn(offered: nil, published: current, heldByPause: false, asked: false,
                                       needsAdministrator: false)
        #expect(first == .askTool)
        r.send(.offerRead("a", first))
        let second = CLIRunOffer.atTurn(offered: nil, published: current, heldByPause: false, asked: true,
                                        needsAdministrator: false)
        #expect(second == .notRun(.silent))
        #expect(r.send(.offerRead("a", second)) == [])
        r.send(.released("a"))
        let s = r.snapshot([current])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .none, caption: .status))
        #expect(s.popover == CLIPopoverRow(lines: [.upToDate], mark: .seal, button: .none, isRunning: false))
        #expect(r.runs(of: "a") == 0)
    }

    /// Held back only by the GitHub pause at its turn: not asked again — the
    /// check would be refused by the same budget, and its "no verdict" would
    /// replace the update the pause holds back (review, 2026-10-20, round 2).
    @Test func clickHeldByTheGitHubPauseAtItsTurnIsNotAskedAgain() {
        let paused = Self.fx("a", oneClick: false, withheld: .rateLimited)
        let offer = CLIRunOffer.atTurn(offered: nil, published: paused, heldByPause: true, asked: false,
                                       needsAdministrator: false)
        let why = CLIToolWording.reason(.rateLimited, of: paused)
        #expect(offer == .notRun(.notOffered(reason: why)))
        let r = Run()
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: false))
        r.send(.turnCame("a"))
        #expect(r.send(.offerRead("a", offer)) == [.sayNotRun("a", .notOffered(reason: why))])
        // Its Cancel was never taken: no ask, no "Checking…".
        #expect(r.state.cancels["a"] == .available)
        #expect(r.lines["a"] == nil)
    }

    /// Offered at its turn on the other route: the click decided it, and the
    /// panel would come minutes after it, so not run.
    @Test func clickWhoseRouteChangedBeforeItsTurnIsNotRun() {
        let admin = Self.fx("a", admin: true)
        let offer = CLIRunOffer.atTurn(offered: admin, published: admin, heldByPause: false, asked: false,
                                       needsAdministrator: false)
        #expect(offer == .notRun(.routeChanged(nowNeedsAdministrator: true)))
        let r = Run()
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
        r.send(.turnCame("a"))
        #expect(r.send(.offerRead("a", offer)) == [.sayNotRun("a", .routeChanged(nowNeedsAdministrator: true))])
        r.send(.released("a"))
        let s = r.snapshot([admin])
        #expect(s.sidebar("a") == CLISidebarRow(
            slot: .update(admin: true),
            caption: .error("Not updated: it now asks for an administrator password — try again")))
        #expect(s.detailHeader("a") == CLIDetailHeader(action: .update(admin: true), progress: nil))
        #expect(r.runs(of: "a") == 0)
    }

    // MARK: - #1522: an Update All lane copy's offer read at its turn

    /// #1522: three copies in one lane of Update All, each read at its turn.
    /// `a`'s offer moved (a newer release): it runs as it stands now. `b` now
    /// asks for an administrator password: the lanes never raise a panel, so
    /// it is not run and its row says to try again. `c`'s check, made while
    /// its lane ran, says "not verified": about the batch, not the copy, so
    /// it runs on the offer clicked.
    @Test func laneCopyReadsItsOfferAtItsTurn() {
        let r = Run()
        let a = Self.fx("a"), b = Self.fx("b"), c = Self.fx("c")
        r.updateAllWaiting = true
        r.send(.updateAllClicked(lanes: ["a", "b", "c"], asking: []))
        #expect(r.effects == [.showLine("a", .queued), .showLine("b", .queued), .showLine("c", .queued), .runUpdateAll])
        #expect(r.send(.lanesReady(["a", "b", "c"])) == [.enqueueUpdateAll(["a", "b", "c"])])
        var s = r.snapshot([a, b, c])
        let three = Group(state: .available, pending: false, live: 3)
        #expect(s.popover == CLIPopoverRow(lines: [.queued], mark: .spinner, button: .cancel(three), isRunning: true))
        #expect(s.updateAllHeader == .running(three))
        #expect(s.sidebar("b") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Queued"))))

        // Its turn. `a`: the offer moved.
        r.updateAllWaiting = false
        #expect(r.send(.laneTurnCame("a")) == [.readLaneOffer("a")])
        let moved = Self.fx("a", latest: "1.2.0")
        let readA = CLIRunOffer.laneAtTurn(clicked: a, published: moved, checked: moved, readsTheLane: false,
                                           clickedNow: { a })
        #expect(readA == CLIRunOffer.Lane(offer: .run(moved), onClickedOffer: false))
        #expect(r.send(.offerRead("a", readA.offer)) == [.startCommand("a")])
        r.send(.commandStarting("a"))
        r.send(.outputLine("a", "Downloading 1.2.0"))
        s = r.snapshot([moved, b, c])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Downloading 1.2.0"))))
        #expect(s.sidebar("b") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Queued"))))
        #expect(s.popover?.lines == [.updating(.fx), .progress(.line("Downloading 1.2.0"))])
        #expect(s.updateAllHeader == .running(three))
        // Its re-check waits on the lane's other copies.
        #expect(r.send(.commandEnded("a", needsRecheck: true, cancelStopped: false)) == [.showLine("a", .waitingToCheck)])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .awaitingCheck, byUpdateAll: true))

        // `b`: now asks for an administrator password.
        #expect(r.send(.laneTurnCame("b")) == [.readLaneOffer("b")])
        let admin = Self.fx("b", admin: true)
        let readB = CLIRunOffer.laneAtTurn(clicked: b, published: admin, checked: admin, readsTheLane: true,
                                           clickedNow: { b })
        #expect(readB.offer == .notRun(.routeChanged(nowNeedsAdministrator: true)))
        #expect(r.send(.offerRead("b", readB.offer)) == [.sayNotRun("b", .routeChanged(nowNeedsAdministrator: true))])
        r.send(.released("b"))
        #expect(r.state.batchIDs == ["a", "c"])
        s = r.snapshot([moved, admin, c])
        #expect(s.sidebar("b") == CLISidebarRow(
            slot: .update(admin: true),
            caption: .error("Not updated: it now asks for an administrator password — try again")))
        #expect(s.detailHeader("b") == CLIDetailHeader(action: .update(admin: true), progress: nil))

        // `c`: "not verified", read while its lane ran.
        #expect(r.send(.laneTurnCame("c")) == [.readLaneOffer("c")])
        let unverified = Self.fx("c", state: .unknown, oneClick: false, withheld: .unverified)
        let readC = CLIRunOffer.laneAtTurn(clicked: c, published: unverified, checked: unverified, readsTheLane: true,
                                           clickedNow: { c })
        #expect(readC == CLIRunOffer.Lane(offer: .run(c), onClickedOffer: true))
        // The same verdict from a check before the lane ran is about the copy.
        let before = CLIRunOffer.laneAtTurn(clicked: c, published: unverified, checked: unverified,
                                            readsTheLane: false, clickedNow: { c })
        #expect(before.offer == .notRun(.notOffered(reason: CLIToolWording.reason(.unverified, of: unverified))))
        // The fallback still honours the GitHub pause.
        let paused = Self.fx("c", oneClick: false, withheld: .rateLimited)
        let held = CLIRunOffer.laneAtTurn(clicked: c, published: unverified, checked: unverified, readsTheLane: true,
                                          clickedNow: { paused })
        #expect(held.offer == .notRun(.heldBack(reason: CLIToolWording.reason(.rateLimited, of: paused))))
        #expect(r.send(.offerRead("c", readC.offer)) == [.startCommand("c")])
        r.send(.commandStarting("c"))
        r.send(.commandEnded("c", needsRecheck: true, cancelStopped: false))

        // The tool's re-check, once its last lane is done; then each is released.
        #expect(r.send(.recheckStarted(["a", "c"])) == [.showLine("a", .checking), .showLine("c", .checking)])
        r.send(.released("a"))
        r.send(.released("c"))
        r.send(.updateAllFinished)
        #expect(r.state == State())
        #expect(r.runs(of: "a") == 1)
        #expect(r.runs(of: "b") == 0)
        #expect(r.runs(of: "c") == 1)
    }

    // MARK: - #1535: cancelled out of Update All, clicked again

    /// #1535: a copy cancelled out of a waiting Update All and clicked again
    /// waits as a click of its own. Update All's lane skips it, its Cancel
    /// and its withdrawal leave it alone, and its own turn runs it: once.
    @Test func copyCancelledOutOfUpdateAllAndClickedAgainRunsOnce() {
        let r = Run()
        let a = Self.fx("a"), b = Self.fx("b")
        r.updateAllWaiting = true
        r.send(.updateAllClicked(lanes: ["a", "b"], asking: []))
        r.send(.lanesReady(["a", "b"]))

        // Its Cancel: the queue holds no click of its own, and Update All has
        // not reached it — out of the batch.
        #expect(r.send(.cancelClicked("a")) == [.withdrawClick("a")])
        #expect(r.send(.notWaitingInQueue("a", updateAllWaiting: true)) == [.clearLine("a")])
        #expect(r.state.batchIDs == ["b"])
        var s = r.snapshot([a, b])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .update(admin: false), caption: .status))
        #expect(s.updateAllHeader == .running(Self.live))

        // Clicked again, behind Update All: a click of its own, "Queued".
        #expect(r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
            == [.showLine("a", .queued), .enqueue("a")])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .queued, byUpdateAll: false))
        s = r.snapshot([a, b])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Queued"))))
        #expect(s.updateAllHeader == .running(Self.live))
        // Neither Update All's Cancel nor its withdrawal is this click's.
        let cancelled = r.copy()
        #expect(cancelled.send(.updateAllNotWaiting) == [.cancelCopy("b")])
        let withdrawn = r.copy()
        #expect(withdrawn.send(.updateAllWithdrawn) == [.clearLine("b"), .updateAllEnded])
        #expect(withdrawn.state.claims == ["a": CLIRunClaim(phase: .queued, byUpdateAll: false)])
        #expect(!withdrawn.state.updatingAll)

        // Update All's turn: its lane skips `a`, whose "Queued" stays.
        r.updateAllWaiting = false
        #expect(r.send(.laneTurnCame("a")) == [])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .queued, byUpdateAll: false))
        #expect(r.send(.laneTurnCame("b")) == [.readLaneOffer("b")])
        r.send(.offerRead("b", .run(b)))
        r.send(.commandStarting("b"))
        s = r.snapshot([a, b])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Queued"))))
        #expect(s.sidebar("b") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Starting…"))))
        r.send(.commandEnded("b", needsRecheck: true, cancelStopped: false))
        r.send(.recheckStarted(["b"]))
        r.send(.released("b"))
        r.send(.updateAllFinished)
        #expect(r.state.claims == ["a": CLIRunClaim(phase: .queued, byUpdateAll: false)])

        // Its own turn: it runs, once.
        r.send(.turnCame("a"))
        #expect(r.send(.offerRead("a", .run(a))) == [.startCommand("a")])
        #expect(r.runs(of: "a") == 1)
        #expect(r.runs(of: "b") == 1)
    }

    // MARK: - #1536: the window before Update All's end

    /// #1536: the last copy released, Update All not yet ended — the moment
    /// between the two. Holding nothing and waiting on nothing, it draws as
    /// ended: no "Queued", no running row, no header Cancel.
    @Test func windowBetweenTheLastReleaseAndUpdateAllsEndDrawsNoQueued() {
        let r = Run()
        let a = Self.fx("a")
        r.send(.updateAllClicked(lanes: ["a"], asking: []))
        r.send(.lanesReady(["a"]))
        r.send(.laneTurnCame("a"))
        r.send(.offerRead("a", .run(a)))
        r.send(.commandStarting("a"))
        r.send(.commandEnded("a", needsRecheck: true, cancelStopped: false))
        r.send(.recheckStarted(["a"]))
        var s = r.snapshot([a])
        #expect(s.popover?.lines == [.updating(.fx), .progress(.line("Checking…"))])
        #expect(s.updateAllHeader == .running(Group(state: .committing, pending: false, live: 0)))

        r.send(.released("a"))
        // The window.
        #expect(r.state.updatingAll)
        #expect(r.state.batchIDs.isEmpty)
        let current = Self.fx("a", state: .upToDate, oneClick: false)
        s = r.snapshot([current])
        #expect(s.popover == CLIPopoverRow(lines: [.upToDate], mark: .seal, button: .none, isRunning: false))
        #expect(s.sidebar("a") == CLISidebarRow(slot: .none, caption: .status))
        #expect(s.detailHeader("a") == CLIDetailHeader(action: .none, progress: nil))
        #expect(s.updateAllHeader == .hidden)

        r.send(.updateAllFinished)
        #expect(r.state == State())
        let ended = r.snapshot([current])
        #expect(ended.popover == s.popover)
        #expect(ended.sidebar("a") == s.sidebar("a"))
        #expect(ended.updateAllHeader == s.updateAllHeader)
    }

    // MARK: - Cancel

    /// A Cancel accepted before the command starts stops it: nothing ran,
    /// nothing to re-check, the row goes back to its Update. One after the
    /// commit is greyed and changes nothing: the command runs to its end, and
    /// its tool is re-checked.
    @Test func cancelAcceptedBeforeTheCommandVersusAfterTheCommit() {
        let r = Run()
        let a = Self.fx("a")
        #expect(r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: false)) == [.enqueue("a")])
        r.send(.turnCame("a"))
        r.send(.offerRead("a", .run(a)))
        r.send(.commandStarting("a"))
        let started = r.copy()

        // Before its command: through the registry, which accepts.
        let before = started.copy()
        #expect(before.send(.cancelClicked("a")) == [.withdrawClick("a")])
        #expect(before.send(.notWaitingInQueue("a", updateAllWaiting: false)) == [.cancelJob("a")])
        #expect(before.send(.cancelAnswered("a", .cancelled)) == [])
        #expect(before.state.cancels["a"] == .cancelling)
        var s = before.snapshot([a])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .spinnerOnly, caption: .progress(.cancelling)))
        #expect(s.detailHeader("a") == CLIDetailHeader(action: .spinnerOnly, progress: .cancelling))
        #expect(s.popover == CLIPopoverRow(lines: [.updating(.fx), .progress(.cancelling)],
                                           mark: .spinner, button: .none, isRunning: true))
        // Its output no longer replaces "Cancelling…", and a second click
        // finds nothing to cancel.
        #expect(before.send(.outputLine("a", "Downloading")) == [])
        #expect(before.send(.cancelClicked("a")) == [])
        // It kept the command from starting.
        #expect(before.send(.commandEnded("a", needsRecheck: true, cancelStopped: true)) == [.stoppedBeforeCommand("a")])
        #expect(before.state.phase("a") == .running)
        before.send(.released("a"))
        s = before.snapshot([a])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .update(admin: false), caption: .status))
        #expect(s.popover == CLIPopoverRow(lines: [.updates(1)], mark: nil, button: .update(admin: false), isRunning: false))
        #expect(before.errors.isEmpty)

        // Accepted, but the command had run already: its result stands.
        let ran = started.copy()
        ran.send(.cancelClicked("a"))
        ran.send(.notWaitingInQueue("a", updateAllWaiting: false))
        ran.send(.cancelAnswered("a", .cancelled))
        #expect(ran.send(.commandEnded("a", needsRecheck: true, cancelStopped: false)) == [.showLine("a", .waitingToCheck)])
        #expect(ran.state.claims["a"] == CLIRunClaim(phase: .awaitingCheck, byUpdateAll: false))

        // After the commit: greyed, and a click on it does nothing.
        let after = started.copy()
        #expect(after.send(.jobPhaseChanged("a", .committing)) == [])
        #expect(after.state.cancels["a"] == .committing)
        #expect(after.send(.cancelClicked("a")) == [])
        let greyed = Group(state: .committing, pending: false, live: 0)
        s = after.snapshot([a])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(greyed), caption: .progress(.line("Starting…"))))
        #expect(s.detailHeader("a") == CLIDetailHeader(action: .cancel(greyed), progress: .line("Starting…")))
        #expect(s.popover?.button == .cancel(greyed))
        #expect(after.send(.commandEnded("a", needsRecheck: true, cancelStopped: false)) == [.showLine("a", .waitingToCheck)])
        #expect(after.state.claims["a"] == CLIRunClaim(phase: .awaitingCheck, byUpdateAll: false))
        #expect(after.state.cancels["a"] == .committing)

        // Clicked just as the commit began, before the row heard: too late.
        let late = started.copy()
        late.send(.cancelClicked("a"))
        late.send(.notWaitingInQueue("a", updateAllWaiting: false))
        late.send(.cancelAnswered("a", .tooLate(committing: "fx upgrade")))
        #expect(late.state.cancels["a"] == .tooLate)
    }

    /// A click queued behind a running Update All, then cancelled: the queue
    /// takes it back and its `whenCancelled` releases it. Update All goes on.
    @Test func clickQueuedBehindUpdateAllCancelledLeavesUpdateAllRunning() {
        let r = Run()
        let a = Self.fx("a"), b = Self.fx("b")
        r.send(.updateAllClicked(lanes: ["b"], asking: []))
        r.send(.lanesReady(["b"]))
        r.send(.laneTurnCame("b"))
        r.send(.offerRead("b", .run(b)))
        r.send(.commandStarting("b"))
        #expect(r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
            == [.showLine("a", .queued), .enqueue("a")])
        #expect(r.send(.cancelClicked("a")) == [.withdrawClick("a")])
        // The queue took it back: its `whenCancelled`.
        #expect(r.send(.released("a")) == [.clearLine("a")])
        #expect(r.state.batchIDs == ["b"])
        #expect(r.state.updatingAll)
        let s = r.snapshot([a, b])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .update(admin: false), caption: .status))
        #expect(s.popover?.lines == [.updating(.fx), .progress(.line("Starting…"))])
        #expect(s.updateAllHeader == .running(Self.live))
    }

    /// Update All waiting its turn, each copy cancelled: the last one leaves
    /// nothing for the turn to run, so Update All itself is taken back, and is
    /// over at once.
    @Test func updateAllWaitingWithEveryCopyCancelledIsTakenBack() {
        let r = Run()
        let a = Self.fx("a"), b = Self.fx("b")
        r.updateAllWaiting = true
        r.send(.updateAllClicked(lanes: ["a", "b"], asking: []))
        r.send(.lanesReady(["a", "b"]))
        r.send(.cancelClicked("a"))
        #expect(r.send(.notWaitingInQueue("a", updateAllWaiting: true)) == [.clearLine("a")])
        r.send(.cancelClicked("b"))
        #expect(r.send(.notWaitingInQueue("b", updateAllWaiting: true)) == [.clearLine("b"), .cancelUpdateAll])
        #expect(r.send(.cancelUpdateAllClicked) == [.withdrawUpdateAll])
        // The queue took it back: its `whenCancelled`.
        r.updateAllWaiting = false
        #expect(r.send(.updateAllWithdrawn) == [.updateAllEnded])
        #expect(r.state == State())
        let s = r.snapshot([a, b])
        #expect(s.popover == CLIPopoverRow(lines: [.updates(2)], mark: nil, button: .update(admin: false), isRunning: false))
        #expect(s.updateAllHeader == .update(startable: true))
    }

    // MARK: - Administrator panels

    /// A copy that asks for an administrator password raises its panel at the
    /// click, never queued behind another run. Declined, nothing ran: no red
    /// line, no re-check, its Update back. Allowed, it runs and is re-checked.
    @Test func adminClickRaisesItsPanelAtTheClick() {
        let r = Run()
        let a = Self.fx("a", admin: true)
        #expect(r.send(.clicked("a", offered: true, needsAdministrator: true, queueBusy: true)) == [.raisePanel("a")])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .running, byUpdateAll: false))
        var s = r.snapshot([a])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.updating)))
        r.send(.turnCame("a"))
        #expect(r.send(.offerRead("a", .run(a))) == [.startCommand("a")])
        r.send(.commandStarting("a"))

        let declined = r.copy()
        #expect(declined.send(.commandEnded("a", needsRecheck: false, cancelStopped: false)) == [])
        declined.send(.released("a"))
        s = declined.snapshot([a])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .update(admin: true), caption: .status))
        // Update All asks for its panel too.
        #expect(s.popover == CLIPopoverRow(lines: [.updates(1), .needSudo(1)], mark: nil,
                                           button: .update(admin: false), isRunning: false))

        let allowed = r.copy()
        #expect(allowed.send(.commandEnded("a", needsRecheck: true, cancelStopped: false)) == [.showLine("a", .waitingToCheck)])
        s = allowed.snapshot([a])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .spinnerOnly, caption: .progress(.line("Waiting to check"))))
    }

    /// Update All's panels come one after another, each only while Update All
    /// still holds its copy; the last panel copy to end with its lane copies
    /// all cancelled takes back the Update All still waiting its turn
    /// (review, #1502 round 1).
    @Test func updateAllPanelsOnlyForTheCopiesItStillHolds() {
        let r = Run()
        r.updateAllWaiting = true
        r.send(.updateAllClicked(lanes: ["c"], asking: ["a", "b"]))
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .queued, byUpdateAll: true))
        #expect(r.send(.panelTurnCame("a")) == [.raisePanel("a")])
        r.send(.turnCame("a"))
        // `b` cancelled while `a`'s panel was up.
        r.send(.cancelClicked("b"))
        #expect(r.send(.notWaitingInQueue("b", updateAllWaiting: true)) == [.clearLine("b")])
        #expect(r.send(.panelTurnCame("b")) == [])
        #expect(r.send(.lanesReady(["c"])) == [.enqueueUpdateAll(["c"])])
        // `c` cancelled while `a` runs: Update All still holds `a`.
        r.send(.cancelClicked("c"))
        #expect(r.send(.notWaitingInQueue("c", updateAllWaiting: true)) == [.clearLine("c")])
        // `a`'s run ends: nothing is left for the waiting turn to run.
        #expect(r.send(.panelRunEnded("a", updateAllWaiting: true)) == [.clearLine("a"), .cancelUpdateAll])
        r.updateAllWaiting = false
        #expect(r.send(.updateAllWithdrawn) == [.updateAllEnded])
        #expect(r.state == State())
    }

    /// A second click on a copy already claimed claims nothing, and a click on
    /// one no longer offered neither; a second Update All while one runs, or
    /// one with nothing to start, does nothing.
    @Test func clicksThatClaimNothing() {
        let r = Run()
        #expect(r.send(.clicked("a", offered: false, needsAdministrator: false, queueBusy: false)) == [])
        #expect(r.state == State())
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
        let claimed = r.state
        #expect(r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: false)) == [])
        #expect(r.state == claimed)
        #expect(r.send(.updateAllClicked(lanes: [], asking: [])) == [])
        r.send(.updateAllClicked(lanes: ["b"], asking: []))
        let running = r.state
        #expect(r.send(.updateAllClicked(lanes: ["c"], asking: [])) == [])
        #expect(r.state == running)
        // A line after the copy was released pins nothing on its row.
        r.send(.released("a"))
        #expect(r.send(.outputLine("a", "late")) == [])
    }
}
