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
        latest: String = "1.1.0", withheld: CLIToolWithheld? = nil, installed: String = "1.0.0"
    ) -> CLIToolStatus {
        CLIToolStatus(
            kind: .fx, path: path, installedVersion: installed, latestVersion: latest, channel: nil, state: state,
            oneClick: oneClick ? CLIToolCommand(executable: path, arguments: ["upgrade"], pathPrefix: nil) : nil,
            withheld: withheld, note: nil,
            detail: .fx(FxInstall(path: path, version: installed)), needsAdministrator: admin)
    }

    /// The app's side of a sequence, as much of it as the rows read: the lines
    /// the effects set, the red lines worded from the state, and whether
    /// Update All waits in the queue (`CLIRunQueue`, the app's). A class, so a step can be sent inside
    /// `#expect`; `copy` follows one run two ways. Every effect is kept, so a test can
    /// count the commands started. The answers the app feeds back — the
    /// queue's, the registry's — are sent by each test, as the steps they are.
    final class Run {
        var state = State()
        var lines: [String: String] = [:]
        var stages: [String: InstallStage] = [:]
        var effects: [Effect] = []
        var updateAllWaiting = false

        /// The same run, to follow two ways from one step.
        func copy() -> Run {
            let run = Run()
            run.state = state
            run.lines = lines
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
                case .showLine(let id, let line): lines[id] = Self.text(line); stages[id] = Self.stage(line)
                case .clearLine(let id): lines[id] = nil; stages[id] = nil
                default: break
                }
            }
            effects += out
            return out
        }

        /// Each row's red line, as the app words it (`CLIToolsModel.errors`).
        var errors: [String: String] { state.redLines.mapValues(Self.text) }

        /// Whether nothing runs, waits or is claimed: what is left once every
        /// run is over, whatever its rows still say.
        var runsNothing: Bool { state.claims.isEmpty && state.cancels.isEmpty && !state.updatingAll }

        /// The app's wording (`CLIToolsModel.perform`, `notRunLine`, `redLine`).
        static func text(_ line: CLIRunLine) -> String {
            switch line {
            case .queued: return "Queued"
            case .starting: return "Starting…"
            case .checking: return "Checking…"
            case .waitingToCheck: return "Waiting to check"
            case .output(let text): return text
            }
        }

        /// The stage the app records each line with (`CLIToolsModel.perform`).
        static func stage(_ line: CLIRunLine) -> InstallStage {
            switch line {
            case .queued: return .queued
            case .starting: return .runningCommand("")
            case .checking, .waitingToCheck: return .checking
            case .output(let text): return .runningCommand(text)
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

        static func text(_ line: CLIRunRedLine) -> String {
            switch line {
            case .failed(let message): return message
            case .stillOn(let version): return "Still \(version) after the update"
            case .versionUnreadable: return "Couldn’t read the version after the update"
            case .notRun(let why): return text(why)
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
                    lineStage: runs ? stages[id] : nil,
                    state: status.state, oneClick: status.oneClick != nil,
                    needsAdministrator: status.needsAdministrator, withheld: status.withheld,
                    manualCommand: nil, hasLatestVersion: status.latestVersion != nil,
                    error: errors[id], justUpdated: state.justUpdated[id])
            }
            let offered = statuses.filter { $0.state == .updateAvailable && $0.oneClick != nil }
            return .live(
                tools: tools, unlisted: [], hasSightings: true, checked: true,
                updatingAll: state.updatingAll, updateAllWaiting: updateAllWaiting, batchIDs: state.batchIDs,
                updateAllOffered: !offered.isEmpty,
                updateAllStartable: offered.contains { !state.updating.contains($0.path) })
        }

        /// A check landing, as `CLIToolsModel.apply` sends it: each copy the
        /// state holds a red line or an "Updated to X" for, as `statuses`
        /// list it now (nil when they do not), its tool asked or not. Every
        /// copy in these tests is an fx one, so one flag says it.
        @discardableResult
        func checkLanded(_ statuses: [CLIToolStatus], answered: Bool) -> [Effect] {
            let byID = Dictionary(statuses.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            return send(.checkLanded(Dictionary(uniqueKeysWithValues: state.readByACheck.map {
                ($0, CLIRunChecked(answered: answered, status: byID[$0]))
            })))
        }

        /// How many times `id`'s command was started.
        func runs(of id: String) -> Int { effects.filter { $0 == .startCommand(id) }.count }

        /// A lane copy's turn and command, as `CLIToolsModel.runLane` sends
        /// them for one offered as clicked whose command needs its tool's
        /// re-check: `report` is the generation of its tool's report on screen.
        func runLaneCopy(_ id: String, report: Int = 0, _ result: CLIRunLaneResult) {
            send(.laneTurnCame(id, reportGeneration: report))
            send(.offerRead(id, .run(CLIRunReducerTests.fx(id))))
            send(.commandStarting(id))
            send(.commandEnded(id, needsRecheck: true, cancelStopped: false))
            send(.laneCommandEnded(id, result))
        }

        /// The re-checks Update All asked for, in order.
        var rechecks: [Effect] { effects.filter { if case .recheck = $0 { return true } else { return false } } }
    }

    /// A copy of Update All's lanes: `tool` its provider, `lane` its lane.
    static func lane(_ id: String, tool: Int = 0, _ lane: String, admin: Bool = false) -> CLIRunLaneCopy<String> {
        CLIRunLaneCopy(id: id, tool: tool, lane: lane, needsAdministrator: admin)
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
        #expect(r.send(.offerRead("a", second)) == [])
        #expect(r.state.redLines["a"] == .notRun(.notOffered(reason: busy)))
        #expect(r.state.cancels["a"] == nil)
        r.send(.released("a"))
        #expect(r.runsNothing)
        #expect(r.state.notRunAtTurn == ["a"])
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
        #expect(s.popover == CLIPopoverRow(lines: [.updating(.fx)],
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
        #expect(r.send(.offerRead("a", offer)) == [])
        #expect(r.state.redLines["a"] == .notRun(.notOffered(reason: why)))
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
        #expect(r.send(.offerRead("a", offer)) == [])
        #expect(r.state.redLines["a"] == .notRun(.routeChanged(nowNeedsAdministrator: true)))
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
        #expect(r.send(.laneTurnCame("a", reportGeneration: 0)) == [.readLaneOffer("a", readsTheLane: false)])
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
        #expect(s.popover?.lines == [.updating(.fx)])
        #expect(s.updateAllHeader == .running(three))
        // Its re-check waits on the lane's other copies.
        #expect(r.send(.commandEnded("a", needsRecheck: true, cancelStopped: false)) == [.showLine("a", .waitingToCheck)])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .awaitingCheck, byUpdateAll: true))

        // `b`: now asks for an administrator password.
        #expect(r.send(.laneTurnCame("b", reportGeneration: 0)) == [.readLaneOffer("b", readsTheLane: false)])
        let admin = Self.fx("b", admin: true)
        let readB = CLIRunOffer.laneAtTurn(clicked: b, published: admin, checked: admin, readsTheLane: true,
                                           clickedNow: { b })
        #expect(readB.offer == .notRun(.routeChanged(nowNeedsAdministrator: true)))
        #expect(r.send(.offerRead("b", readB.offer)) == [])
        #expect(r.state.redLines["b"] == .notRun(.routeChanged(nowNeedsAdministrator: true)))
        r.send(.released("b"))
        #expect(r.state.batchIDs == ["a", "c"])
        s = r.snapshot([moved, admin, c])
        #expect(s.sidebar("b") == CLISidebarRow(
            slot: .update(admin: true),
            caption: .error("Not updated: it now asks for an administrator password — try again")))
        #expect(s.detailHeader("b") == CLIDetailHeader(action: .update(admin: true), progress: nil))

        // `c`: "not verified", read while its lane ran.
        #expect(r.send(.laneTurnCame("c", reportGeneration: 0)) == [.readLaneOffer("c", readsTheLane: false)])
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
        #expect(r.runsNothing)
        #expect(r.state.redLines == ["b": .notRun(.routeChanged(nowNeedsAdministrator: true))])
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
        #expect(r.send(.laneTurnCame("a", reportGeneration: 0)) == [])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .queued, byUpdateAll: false))
        #expect(r.send(.laneTurnCame("b", reportGeneration: 0)) == [.readLaneOffer("b", readsTheLane: false)])
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
        r.send(.laneTurnCame("a", reportGeneration: 0))
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
        r.send(.laneTurnCame("b", reportGeneration: 0))
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
        #expect(s.popover?.lines == [.updating(.fx)])
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

    // MARK: - Red lines, checks landing, settle (phase 4b)

    /// A lane copy not run at its turn — its update now asks for an
    /// administrator password — whose tool's re-check is the batch's own,
    /// right after its "Not updated" line was said. That check takes the line
    /// away, as any check of its tool does; the lane says it again while it
    /// still holds, so the row does not come back as a live Update with
    /// nothing said (review, 2026-10-21). Once it no longer holds, it is not.
    @Test func laneCopyNotRunAtItsTurnKeepsItsLineThroughTheBatchsCheck() {
        let r = Run()
        let a = Self.fx("a"), b = Self.fx("b")
        r.send(.updateAllClicked(lanes: ["a", "b"], asking: []))
        r.send(.lanesReady(["a", "b"]))
        r.send(.laneTurnCame("a", reportGeneration: 0))
        r.send(.offerRead("a", .run(a)))
        r.send(.commandStarting("a"))
        r.send(.commandEnded("a", needsRecheck: true, cancelStopped: false))

        // `b`'s turn: on the other route now, so not run.
        r.send(.laneTurnCame("b", reportGeneration: 0))
        let admin = Self.fx("b", admin: true)
        let why = CLIRunNotRun.routeChanged(nowNeedsAdministrator: true)
        #expect(CLIRunOffer.laneAtTurn(clicked: b, published: admin, checked: admin, readsTheLane: true,
                                       clickedNow: { b }).offer == .notRun(why))
        r.send(.offerRead("b", .notRun(why)))
        r.send(.released("b"))
        let line = "Not updated: it now asks for an administrator password — try again"
        #expect(r.errors["b"] == line)

        // The tool's re-check, once its last lane is done: the batch's own.
        r.send(.recheckStarted(["a"]))
        let updated = Self.fx("a", state: .upToDate, oneClick: false, installed: "1.1.0")
        r.checkLanded([updated, admin], answered: true)
        #expect(r.errors["b"] == nil)
        let checked = r.copy()

        // Still offered on the other route: said again.
        #expect(r.send(.notRunRechecked("b", why, clickedNeedsAdministrator: false, now: admin)) == [])
        #expect(r.errors["b"] == line)
        #expect(r.state.notRunAtTurn == ["b"])
        r.send(.updateSettled("a", before: "1.0.0", after: "1.1.0"))
        r.send(.released("a"))
        r.send(.updateAllFinished)
        #expect(r.runsNothing)
        let s = r.snapshot([updated, admin])
        #expect(s.sidebar("b") == CLISidebarRow(slot: .update(admin: true), caption: .error(line)))
        #expect(s.detailHeader("b") == CLIDetailHeader(action: .update(admin: true), progress: nil))
        #expect(s.sidebar("a") == CLISidebarRow(slot: .none, caption: .updated(version: "1.1.0", restartSessions: false)))
        // The next check of its tool takes it away for good.
        r.checkLanded([updated, admin], answered: true)
        #expect(r.errors["b"] == nil)

        // No longer holding, it is not said again: offered on the route
        // clicked, current, or gone.
        let nows: [CLIToolStatus?] = [Self.fx("b"), Self.fx("b", state: .upToDate, oneClick: false, installed: "1.1.0"), nil]
        for now in nows {
            let other = checked.copy()
            #expect(other.send(.notRunRechecked("b", why, clickedNeedsAdministrator: false, now: now)) == [])
            #expect(other.errors["b"] == nil)
        }
        // Nor over a line the row says by now.
        let failed = checked.copy()
        failed.send(.commandFailed("b", message: "EACCES", log: "EACCES"))
        failed.send(.notRunRechecked("b", why, clickedNeedsAdministrator: false, now: admin))
        #expect(failed.errors["b"] == "EACCES")
    }

    /// A click whose copy was updated from a terminal while it waited its
    /// turn, a background check landing first: that check takes the copy's
    /// old red line away — it describes an update no longer on offer — and
    /// the turn, asking once more, runs nothing and says nothing.
    @Test func clickUpdatedFromATerminalWithACheckBeforeItsTurnRunsNothingAndSaysNothing() {
        let r = Run()
        let a = Self.fx("a")
        // An earlier click on it failed.
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: false))
        r.send(.turnCame("a"))
        r.send(.offerRead("a", .run(a)))
        r.send(.commandStarting("a"))
        r.send(.commandEnded("a", needsRecheck: false, cancelStopped: false))
        r.send(.commandFailed("a", message: "EACCES", log: "line 1\nEACCES"))
        r.send(.released("a"))
        #expect(r.errors["a"] == "EACCES")
        #expect(r.state.logs["a"] == "line 1\nEACCES")

        // Clicked again, behind another click's run.
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
        // Updated from a terminal meanwhile; a background check lands.
        let current = Self.fx("a", state: .upToDate, oneClick: false, installed: "1.1.0")
        r.checkLanded([current], answered: true)
        #expect(r.errors["a"] == nil)
        #expect(r.state.logs["a"] == nil)
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .queued, byUpdateAll: false))
        var s = r.snapshot([current])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .cancel(Self.live), caption: .progress(.line("Queued"))))

        // Its turn: not offered, so its tool is asked once more; still current.
        r.send(.turnCame("a"))
        let first = CLIRunOffer.atTurn(offered: nil, published: current, heldByPause: false, asked: false,
                                       needsAdministrator: false)
        #expect(first == .askTool)
        #expect(r.send(.offerRead("a", first)) == [.showLine("a", .checking), .check("a")])
        r.checkLanded([current], answered: true)
        let second = CLIRunOffer.atTurn(offered: nil, published: current, heldByPause: false, asked: true,
                                        needsAdministrator: false)
        #expect(second == .notRun(.silent))
        #expect(r.send(.offerRead("a", second)) == [])
        r.send(.released("a"))
        #expect(r.runsNothing)
        #expect(r.state.redLines.isEmpty)
        #expect(r.state.logs.isEmpty)
        // Only the earlier, failed click ran.
        #expect(r.runs(of: "a") == 1)
        s = r.snapshot([current])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .none, caption: .status))
        #expect(s.popover == CLIPopoverRow(lines: [.upToDate], mark: .seal, button: .none, isRunning: false))
    }

    /// A lane copy whose command failed, its tool re-checked for another
    /// copy that ran: the failure is still on offer, so its red line and log
    /// stay through that check. A later check that finds it current takes
    /// them away.
    @Test func failedCommandKeepsItsRedLineThroughTheRecheck() {
        let r = Run()
        let a = Self.fx("a"), b = Self.fx("b")
        r.send(.updateAllClicked(lanes: ["a", "b"], asking: []))
        r.send(.lanesReady(["a", "b"]))
        r.send(.laneTurnCame("a", reportGeneration: 0))
        r.send(.offerRead("a", .run(a)))
        r.send(.commandStarting("a"))
        // A failure needs no re-check: it is said on the row, and released.
        #expect(r.send(.commandEnded("a", needsRecheck: false, cancelStopped: false)) == [])
        r.send(.commandFailed("a", message: "npm ERR! code EACCES", log: "npm ERR! code EACCES\nnpm ERR! path /opt"))
        r.send(.released("a"))
        #expect(r.errors["a"] == "npm ERR! code EACCES")

        r.send(.laneTurnCame("b", reportGeneration: 0))
        r.send(.offerRead("b", .run(b)))
        r.send(.commandStarting("b"))
        r.send(.commandEnded("b", needsRecheck: true, cancelStopped: false))
        r.send(.recheckStarted(["b"]))
        // The tool's re-check: `a` still behind and offered, `b` current.
        let updatedB = Self.fx("b", state: .upToDate, oneClick: false, installed: "1.1.0")
        r.checkLanded([a, updatedB], answered: true)
        #expect(r.errors["a"] == "npm ERR! code EACCES")
        #expect(r.state.logs["a"] == "npm ERR! code EACCES\nnpm ERR! path /opt")
        #expect(r.send(.updateSettled("b", before: "1.0.0", after: "1.1.0")) == [.startConfirmation("b")])
        r.send(.released("b"))
        r.send(.updateAllFinished)
        #expect(r.runsNothing)
        let s = r.snapshot([a, updatedB])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .update(admin: false), caption: .error("npm ERR! code EACCES")))
        #expect(s.sidebar("b") == CLISidebarRow(slot: .none, caption: .updated(version: "1.1.0", restartSessions: false)))
        // Another tool's check leaves it too.
        r.checkLanded([a, updatedB], answered: false)
        #expect(r.errors["a"] == "npm ERR! code EACCES")

        // Updated from a terminal since: the failure no longer holds.
        let current = Self.fx("a", state: .upToDate, oneClick: false, installed: "1.1.0")
        r.checkLanded([current, updatedB], answered: true)
        #expect(r.errors["a"] == nil)
        #expect(r.state.logs["a"] == nil)
    }

    /// An administrator panel declined: a decision, not a failure. Its retry
    /// cleared the copy's last failure as its command started — before the
    /// panel — and the decline says nothing: no red line, no re-check, its
    /// Update back.
    @Test func declinedAdministratorPanelLeavesNoRedLine() {
        let r = Run()
        let a = Self.fx("a", admin: true)
        // An earlier click on it failed.
        r.send(.clicked("a", offered: true, needsAdministrator: true, queueBusy: false))
        r.send(.turnCame("a"))
        r.send(.offerRead("a", .run(a)))
        r.send(.commandStarting("a"))
        r.send(.commandEnded("a", needsRecheck: false, cancelStopped: false))
        r.send(.commandFailed("a", message: "fx: permission denied", log: "fx: permission denied"))
        r.send(.released("a"))
        #expect(r.errors["a"] == "fx: permission denied")

        // Clicked again: its panel at the click.
        #expect(r.send(.clicked("a", offered: true, needsAdministrator: true, queueBusy: true)) == [.raisePanel("a")])
        r.send(.turnCame("a"))
        r.send(.offerRead("a", .run(a)))
        #expect(r.send(.commandStarting("a")) == [.showLine("a", .starting)])
        #expect(r.state.redLines["a"] == nil)
        #expect(r.state.logs["a"] == nil)
        // Declined: nothing ran, nothing to re-check.
        #expect(r.send(.commandEnded("a", needsRecheck: false, cancelStopped: false)) == [])
        r.send(.released("a"))
        #expect(r.runsNothing)
        #expect(r.state.redLines.isEmpty)
        #expect(r.state.logs.isEmpty)
        let s = r.snapshot([a])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .update(admin: true), caption: .status))
        #expect(s.detailHeader("a") == CLIDetailHeader(action: .update(admin: true), progress: nil))
    }

    /// Exit 0 is not proof of an update (`CLITools.settle`): a run that left
    /// the version where it was says so in red, one whose version could not
    /// be read says that. One that moved it says "Updated to X" for the
    /// confirmation window — and no longer once a check finds the copy
    /// changed again, or gone.
    @Test func settleConfirmsAnUpdateOnlyWhenTheVersionMoved() {
        let r = Run()
        let a = Self.fx("a")
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: false))
        r.send(.turnCame("a"))
        r.send(.offerRead("a", .run(a)))
        r.send(.commandStarting("a"))
        r.send(.commandEnded("a", needsRecheck: true, cancelStopped: false))
        r.send(.recheckStarted(["a"]))
        let ran = r.copy()

        let still = ran.copy()
        #expect(still.send(.updateSettled("a", before: "1.0.0", after: "1.0.0")) == [])
        #expect(still.errors["a"] == "Still 1.0.0 after the update")
        #expect(still.state.justUpdated.isEmpty)
        let unreadable = ran.copy()
        #expect(unreadable.send(.updateSettled("a", before: "1.0.0", after: nil)) == [])
        #expect(unreadable.errors["a"] == "Couldn’t read the version after the update")

        #expect(r.send(.updateSettled("a", before: "1.0.0", after: "1.1.0")) == [.startConfirmation("a")])
        #expect(r.state.justUpdated == ["a": "1.1.0"])
        #expect(r.state.redLines.isEmpty)
        r.send(.released("a"))
        let updated = Self.fx("a", state: .upToDate, oneClick: false, installed: "1.1.0")
        var s = r.snapshot([updated])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .none, caption: .updated(version: "1.1.0", restartSessions: false)))
        // A check that finds it as DuoUpdater left it keeps it.
        r.checkLanded([updated], answered: true)
        #expect(r.state.justUpdated == ["a": "1.1.0"])
        let ended = r.copy()
        #expect(ended.send(.confirmationEnded("a")) == [])
        #expect(ended.state.justUpdated.isEmpty)
        s = ended.snapshot([updated])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .none, caption: .status))
        // Updated again from a terminal, or gone: the claim no longer holds.
        let again = r.copy()
        again.checkLanded([Self.fx("a", state: .upToDate, oneClick: false, installed: "1.2.0")], answered: true)
        #expect(again.state.justUpdated.isEmpty)
        let gone = r.copy()
        gone.checkLanded([], answered: true)
        #expect(gone.state.justUpdated.isEmpty)
    }

    /// The verdicts published again with a copy offered where it was not —
    /// the GitHub pause that held it back at its click's turn lifted, with no
    /// check of its tool: its "Not updated" line goes, or it would read as the
    /// reason beside a live Update (review, #1511 round 2). A failure stays,
    /// and so does a "Not updated" line beside an Update that stayed: one not
    /// newly offered waits for its tool's next check.
    @Test func offeredAgainTakesTheNotRunLineAwayAndNothingElse() {
        let r = Run()
        let pausedWhy = CLIRunNotRun.notOffered(reason: "paused")
        r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: false))
        r.send(.turnCame("a"))
        r.send(.offerRead("a", .notRun(pausedWhy)))
        r.send(.released("a"))
        r.send(.clicked("b", offered: true, needsAdministrator: false, queueBusy: false))
        r.send(.turnCame("b"))
        r.send(.offerRead("b", .run(Self.fx("b"))))
        r.send(.commandStarting("b"))
        r.send(.commandEnded("b", needsRecheck: false, cancelStopped: false))
        r.send(.commandFailed("b", message: "EACCES", log: "EACCES"))
        r.send(.released("b"))
        r.send(.clicked("c", offered: true, needsAdministrator: false, queueBusy: false))
        r.send(.turnCame("c"))
        r.send(.offerRead("c", .notRun(.routeChanged(nowNeedsAdministrator: true))))
        r.send(.released("c"))
        #expect(r.state.notRunAtTurn == ["a", "c"])

        #expect(r.send(.offersPublished(newlyOffered: ["a", "b"])) == [])
        #expect(r.errors == [
            "b": "EACCES",
            "c": "Not updated: it now asks for an administrator password — try again",
        ])
        let s = r.snapshot([Self.fx("a")])
        #expect(s.sidebar("a") == CLISidebarRow(slot: .update(admin: false), caption: .status))
    }

    // MARK: - Update All's lanes (phase 4b-2)

    /// Update All over two npm prefixes and uv: npm's copies in two lanes
    /// (nvm's, fnm's), uv's in one. Each tool is re-checked once, as soon as
    /// the last lane holding one of its copies is done — uv's while npm's
    /// fnm lane still runs, npm's only after it — and that check settles
    /// every copy of the tool that ran, then releases it.
    @Test func twoLanesOnOneProviderAreRecheckedOnceAfterTheLastLane() {
        let r = Run()
        let copies = [Self.lane("a", tool: 0, "node:/nvm"), Self.lane("b", tool: 0, "node:/fnm"),
                      Self.lane("c", tool: 0, "node:/nvm"), Self.lane("u", tool: 1, "uv")]
        r.send(.updateAllClicked(lanes: ["a", "b", "c", "u"], asking: []))
        r.send(.lanesReady(["a", "b", "c", "u"]))
        // Lanes in click order, each copy in its lane in click order.
        #expect(r.send(.batchStarted(copies, checkGeneration: 0)) == [.runLanes([["a", "c"], ["b"], ["u"]])])
        #expect(r.state.batch?.lanesLeft == [0: 2, 1: 1])

        // nvm's lane: both its copies; npm still has fnm's lane left.
        r.runLaneCopy("a", .updated(before: "1.0.0", reported: nil))
        r.runLaneCopy("c", .updated(before: "1.0.0", reported: "1.1.0"))
        #expect(r.send(.laneDone(0)) == [])
        #expect(r.state.batch?.lanesLeft == [0: 1, 1: 1])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .awaitingCheck, byUpdateAll: true))
        #expect(r.lines["a"] == "Waiting to check")
        #expect(r.lines["c"] == "Waiting to check")

        // uv's only lane: uv is re-checked now, without npm.
        r.runLaneCopy("u", .ranNothing)
        #expect(r.send(.laneDone(2)) == [.showLine("u", .checking), .recheck([1])])
        let uvNow = Self.fx("u", state: .upToDate, oneClick: false)
        #expect(r.send(.toolRechecked(1, now: ["u": uvNow])) == [.clearLine("u")])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .awaitingCheck, byUpdateAll: true))
        #expect(r.state.claims["c"] == CLIRunClaim(phase: .awaitingCheck, byUpdateAll: true))

        // fnm's lane, npm's last: npm is re-checked once, for all three.
        r.runLaneCopy("b", .updated(before: "1.0.0", reported: nil))
        #expect(r.send(.laneDone(1)) == [
            .showLine("a", .checking), .showLine("c", .checking), .showLine("b", .checking), .recheck([0]),
        ])
        #expect(r.lines["b"] == "Checking…")
        // `a` moved; `c`'s updater re-read 1.1.0 where the check had not
        // caught up, and its own re-read comes first; `b` stayed put.
        let now = ["a": Self.fx("a", state: .upToDate, oneClick: false, installed: "1.1.0"),
                   "b": Self.fx("b"), "c": Self.fx("c")]
        #expect(r.send(.toolRechecked(0, now: now)) == [
            .startConfirmation("a"), .clearLine("a"), .startConfirmation("c"), .clearLine("c"), .clearLine("b"),
        ])
        #expect(r.state.justUpdated == ["a": "1.1.0", "c": "1.1.0"])
        #expect(r.state.redLines == ["b": .stillOn("1.0.0")])
        #expect(r.state.batchIDs.isEmpty)
        #expect(r.rechecks == [.recheck([1]), .recheck([0])])
        // Asked again, the batch has nothing left to settle or release.
        #expect(r.send(.toolRechecked(0, now: now)) == [])

        r.send(.updateAllFinished)
        #expect(r.runsNothing)
        #expect(r.state.batch == nil)
        #expect(["a", "b", "c", "u"].map(r.runs(of:)) == [1, 1, 1, 1])
    }

    /// The real-Mac case of #1541: a copy in nvm's lane not run at its turn
    /// (its prefix's node quarantined while Update All waited), the fnm lane
    /// of the same tool running. Its "Not updated" line is said again after
    /// the batch's own npm check from what the reducer recorded at its turn —
    /// no `notRunRechecked` sent by the app — and only for the tool
    /// re-checked, and only while it still holds.
    @Test func notUpdatedLineIsSaidAgainFromTheReducersOwnRecord() {
        let r = Run()
        let copies = [Self.lane("a", tool: 0, "node:/nvm"), Self.lane("s", tool: 0, "node:/nvm"),
                      Self.lane("b", tool: 0, "node:/fnm")]
        r.send(.updateAllClicked(lanes: ["a", "s", "b"], asking: []))
        r.send(.lanesReady(["a", "s", "b"]))
        r.send(.batchStarted(copies, checkGeneration: 0))

        // `a`: not run, and why. `s`: updated from a terminal, said nothing.
        let quarantined = Self.fx("a", oneClick: false, withheld: .unverified)
        let why = CLIRunNotRun.notOffered(reason: CLIToolWording.reason(.unverified, of: quarantined))
        #expect(CLIRunOffer.laneAtTurn(clicked: Self.fx("a"), published: quarantined, checked: quarantined,
                                       readsTheLane: false, clickedNow: { Self.fx("a") }).offer == .notRun(why))
        r.send(.laneTurnCame("a", reportGeneration: 0))
        r.send(.offerRead("a", .notRun(why)))
        r.send(.released("a"))
        r.send(.laneTurnCame("s", reportGeneration: 0))
        r.send(.offerRead("s", .notRun(.silent)))
        r.send(.released("s"))
        #expect(r.state.batch?.notRun == [0: [CLIRunBatch<String>.NotRun(id: "a", why: why, clickedNeedsAdministrator: false)]])
        // npm's fnm lane is still to come: no re-check yet.
        #expect(r.send(.laneDone(0)) == [])

        r.runLaneCopy("b", .updated(before: "1.0.0", reported: "1.1.0"))
        #expect(r.send(.laneDone(1)) == [.showLine("b", .checking), .recheck([0])])
        // The batch's own check lands, and takes the line away, as any check
        // of its tool does.
        let updatedB = Self.fx("b", state: .upToDate, oneClick: false, installed: "1.1.0")
        r.checkLanded([quarantined, updatedB], answered: true)
        #expect(r.errors["a"] == nil)
        let landed = r.copy()

        // Its tool re-checked: said again, from the batch's record.
        let line = "Not updated: \(CLIToolWording.reason(.unverified, of: quarantined))"
        #expect(r.send(.toolRechecked(0, now: ["a": quarantined, "b": updatedB])) == [
            .startConfirmation("b"), .clearLine("b"),
        ])
        #expect(r.errors == ["a": line])
        #expect(r.state.batch?.notRun[0] == nil)
        r.send(.updateAllFinished)
        #expect(r.runsNothing)
        let snap = r.snapshot([quarantined, updatedB])
        #expect(snap.sidebar("a") == CLISidebarRow(slot: .none, caption: .error(line)))
        #expect(snap.sidebar("b") == CLISidebarRow(slot: .none, caption: .updated(version: "1.1.0", restartSessions: false)))
        #expect(r.runs(of: "a") == 0)
        #expect(r.runs(of: "s") == 0)

        // Another tool's re-check says nothing of it.
        let other = landed.copy()
        #expect(other.send(.toolRechecked(1, now: ["a": quarantined])) == [])
        #expect(other.errors["a"] == nil)
        // Nor once it no longer holds: the quarantine lifted and the copy
        // offered again on the route clicked, or the copy gone.
        for now in [Self.fx("a"), nil] {
            let lifted = landed.copy()
            lifted.send(.toolRechecked(0, now: now.map { ["a": $0, "b": updatedB] } ?? ["b": updatedB]))
            #expect(lifted.errors["a"] == nil)
        }
    }

    /// What a lane's turn reads its check against: a check started before the
    /// lane's first command is about the copy (`readsTheLane` false) — also
    /// one started after Update All's turn came; one started after that
    /// command may have read the lane's own work (true). Per lane: another
    /// lane that has run nothing yet reads false.
    @Test func readsTheLaneOnlyForACheckStartedAfterTheLanesFirstCommand() {
        // With no batch, a check changes nothing.
        let idle = Run()
        #expect(idle.send(.checkStarted(generation: 7)) == [])
        #expect(idle.state == State())

        let r = Run()
        let copies = [Self.lane("a", "fx"), Self.lane("b", "fx"), Self.lane("c", tool: 1, "uv")]
        r.send(.updateAllClicked(lanes: ["a", "b", "c"], asking: []))
        r.send(.lanesReady(["a", "b", "c"]))
        r.send(.batchStarted(copies, checkGeneration: 3))
        // A check started at the turn, before the lane ran anything, landed.
        r.send(.checkStarted(generation: 4))
        #expect(r.send(.laneTurnCame("a", reportGeneration: 4)) == [.readLaneOffer("a", readsTheLane: false)])
        r.send(.offerRead("a", .run(Self.fx("a"))))
        #expect(r.state.batch?.ranSince == [:])
        r.send(.commandStarting("a"))
        #expect(r.state.batch?.ranSince == [0: 4])
        r.send(.commandEnded("a", needsRecheck: true, cancelStopped: false))
        r.send(.laneCommandEnded("a", .updated(before: "1.0.0", reported: nil)))

        // `b`'s turn, with that same report on screen: about the copy.
        let before = r.copy()
        #expect(before.send(.laneTurnCame("b", reportGeneration: 4)) == [.readLaneOffer("b", readsTheLane: false)])
        // A check that started once `a`'s command had: about the batch.
        r.send(.checkStarted(generation: 5))
        #expect(r.copy().send(.laneTurnCame("b", reportGeneration: 5)) == [.readLaneOffer("b", readsTheLane: true)])
        // The other lane has run nothing yet: the same report is about its copy.
        #expect(r.copy().send(.laneTurnCame("c", reportGeneration: 5)) == [.readLaneOffer("c", readsTheLane: false)])
        // A later command in the lane keeps the lane's first.
        r.send(.laneTurnCame("b", reportGeneration: 5))
        r.send(.offerRead("b", .run(Self.fx("b"))))
        r.send(.commandStarting("b"))
        #expect(r.state.batch?.ranSince == [0: 4])
        #expect(r.state.batch?.checkGeneration == 5)
    }

    /// #1535 through the lanes: a copy cancelled out of a waiting Update All
    /// and clicked again. Its lane skips it, its own click's command and its
    /// own "Not updated" are not the batch's, the batch's re-check releases
    /// only the copy that ran in it, and its own turn runs it: once.
    @Test func laneCopyCancelledWhileWaitingThenClickedAgainRunsOnce() {
        let r = Run()
        r.updateAllWaiting = true
        r.send(.updateAllClicked(lanes: ["a", "b"], asking: []))
        r.send(.lanesReady(["a", "b"]))
        r.send(.cancelClicked("a"))
        #expect(r.send(.notWaitingInQueue("a", updateAllWaiting: true)) == [.clearLine("a")])
        #expect(r.send(.clicked("a", offered: true, needsAdministrator: false, queueBusy: true))
            == [.showLine("a", .queued), .enqueue("a")])

        // Update All's turn: `a` is still among the copies its lane lists.
        r.updateAllWaiting = false
        #expect(r.send(.batchStarted([Self.lane("a", "fx"), Self.lane("b", "fx")], checkGeneration: 0))
            == [.runLanes([["a", "b"]])])
        #expect(r.send(.laneTurnCame("a", reportGeneration: 0)) == [])
        #expect(r.state.claims["a"] == CLIRunClaim(phase: .queued, byUpdateAll: false))
        #expect(r.lines["a"] == "Queued")

        // Its own click's run, while the lane still runs, is not the lane's:
        // no `ranSince`, no "Not updated" kept for the batch's check.
        let own = r.copy()
        own.send(.turnCame("a"))
        own.send(.offerRead("a", .run(Self.fx("a"))))
        own.send(.commandStarting("a"))
        #expect(own.state.batch?.ranSince == [:])
        let ownNotRun = r.copy()
        ownNotRun.send(.turnCame("a"))
        ownNotRun.send(.offerRead("a", .notRun(.notOffered(reason: nil))))
        #expect(ownNotRun.state.batch?.notRun == [:])

        r.runLaneCopy("b", .updated(before: "1.0.0", reported: "1.1.0"))
        #expect(r.send(.laneDone(0)) == [.showLine("b", .checking), .recheck([0])])
        #expect(r.send(.toolRechecked(0, now: ["b": Self.fx("b", state: .upToDate, oneClick: false, installed: "1.1.0")]))
            == [.startConfirmation("b"), .clearLine("b")])
        #expect(r.state.claims == ["a": CLIRunClaim(phase: .queued, byUpdateAll: false)])
        #expect(r.lines["a"] == "Queued")
        r.send(.updateAllFinished)
        #expect(r.state.claims == ["a": CLIRunClaim(phase: .queued, byUpdateAll: false)])

        // Its own turn: it runs, once.
        r.send(.turnCame("a"))
        #expect(r.send(.offerRead("a", .run(Self.fx("a")))) == [.startCommand("a")])
        #expect(r.runs(of: "a") == 1)
        #expect(r.runs(of: "b") == 1)
    }

    /// #1536 through the lanes: from the release of the last copy by its
    /// tool's re-check to Update All's end — another lane done after it,
    /// with nothing to re-check — no row says "Queued", nothing draws as
    /// running, and the header has no Cancel.
    @Test func noQueuedBetweenTheLastLaneReleaseAndUpdateAllsEnd() {
        let r = Run()
        r.send(.updateAllClicked(lanes: ["a", "b"], asking: []))
        r.send(.lanesReady(["a", "b"]))
        r.send(.batchStarted([Self.lane("a", tool: 0, "fx"), Self.lane("b", tool: 1, "uv")], checkGeneration: 0))

        // `b` fails: said on its row, released at once, nothing to re-check.
        r.send(.laneTurnCame("b", reportGeneration: 0))
        r.send(.offerRead("b", .run(Self.fx("b"))))
        r.send(.commandStarting("b"))
        r.send(.commandEnded("b", needsRecheck: false, cancelStopped: false))
        r.send(.commandFailed("b", message: "EACCES", log: "EACCES"))
        #expect(r.send(.laneCommandEnded("b", .nothingToCheck)) == [.clearLine("b")])
        #expect(r.state.batchIDs == ["a"])

        r.runLaneCopy("a", .updated(before: "1.0.0", reported: "1.1.0"))
        #expect(r.send(.laneDone(0)) == [.showLine("a", .checking), .recheck([0])])
        let current = Self.fx("a", state: .upToDate, oneClick: false, installed: "1.1.0")
        let behind = Self.fx("b")
        r.send(.toolRechecked(0, now: ["a": current]))

        // The window: the last copy released, Update All not yet ended.
        func drawsEnded() {
            #expect(r.state.updatingAll)
            #expect(r.state.batchIDs.isEmpty)
            #expect(r.state.claims.isEmpty)
            #expect(!r.lines.values.contains("Queued"))
            let s = r.snapshot([current, behind])
            #expect(s.popover?.isRunning == false)
            #expect(s.popover?.lines.contains(.queued) == false)
            #expect(s.sidebar("a") == CLISidebarRow(slot: .none, caption: .updated(version: "1.1.0", restartSessions: false)))
            #expect(s.sidebar("b") == CLISidebarRow(slot: .update(admin: false), caption: .error("EACCES")))
            #expect(s.detailHeader("a") == CLIDetailHeader(action: .none, progress: nil))
            // `b` is on offer again: the button, live, and no Cancel.
            #expect(s.updateAllHeader == .update(startable: true))
        }
        drawsEnded()
        // uv's lane done last: it ran nothing to re-check.
        #expect(r.send(.laneDone(1)) == [])
        drawsEnded()

        r.send(.updateAllFinished)
        #expect(r.runsNothing)
        #expect(r.state.batch == nil)
        #expect(!r.lines.values.contains("Queued"))
    }
}
