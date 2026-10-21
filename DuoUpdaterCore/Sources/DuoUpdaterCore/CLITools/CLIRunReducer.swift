import Foundation

/// One copy's claim on the command-line tools' runs: which click holds it,
/// and how far its run has got.
public struct CLIRunClaim: Equatable, Sendable {
    /// Never `.idle`: an idle copy has no claim.
    public var phase: CLIRunPhase
    /// Claimed by Update All, not by a click of its own on its row.
    public let byUpdateAll: Bool

    public init(phase: CLIRunPhase, byUpdateAll: Bool) {
        self.phase = phase
        self.byUpdateAll = byUpdateAll
    }
}

/// What the command-line tools' runs are, as plain values: every claim, every
/// Cancel, whether Update All runs, and what each row says once its run is
/// over — its red line, its log, its "Updated to X". `CLIRunReducer` is the
/// only thing that changes it, so every transition — a click, Update All, a
/// turn, a Cancel, a release, a check landing — is a pure function a sequence
/// test can replay step by step, rather than a model under `until {}` polling
/// (UI = f(state), phases 4 and 4b).
public struct CLIRunState<Key: Hashable & Sendable>: Equatable, Sendable {
    /// Every copy DuoUpdater is updating right now, one claim each, from the
    /// click until the re-check after it has landed — and, under Update All,
    /// every copy it will update, from the start: a copy waiting its turn is
    /// claimed, so it shows "Queued" rather than a live Update. `updating`,
    /// `queued`, `awaitingCheck` and `batchIDs` are read off it: kept as
    /// parallel sets by hand, they drifted apart and drew wrong rows (#1511).
    public var claims: [Key: CLIRunClaim] = [:]
    /// The Cancel of each copy claimed (`InstallCancelState`): live while it
    /// waits its turn or runs what comes before its command, greyed once the
    /// command started. Cleared with the claim.
    public var cancels: [Key: InstallCancelState] = [:]
    /// True for the whole of Update All, including the re-checks at the end
    /// of each tool's lanes.
    public var updatingAll = false
    /// Each copy's red line: its last failed update, a run that left its
    /// version where it was, or why a click was not run at its turn. Kept past
    /// the claim, until a retry or a check says it no longer holds
    /// (`checkLanded`, `offersPublished`).
    public var redLines: [Key: CLIRunRedLine] = [:]
    /// The full output of each failed update: the detail pane's log.
    public var logs: [Key: String] = [:]
    /// Copies just updated → the version they now read as: "Updated to X".
    /// A confirmation, not a state: the app's window ends it
    /// (`startConfirmation`, `confirmationEnded`), and a check that finds the
    /// copy changed again, or gone, ends it sooner.
    public var justUpdated: [Key: String] = [:]

    public init() {}

    public var updating: Set<Key> { Set(claims.keys) }
    public var queued: Set<Key> { Set(claims.lazy.filter { $0.value.phase == .queued }.map(\.key)) }
    public var awaitingCheck: Set<Key> { Set(claims.lazy.filter { $0.value.phase == .awaitingCheck }.map(\.key)) }
    /// The copies the running (or waiting) Update All still holds. A copy
    /// cancelled while queued is not among them, nor is one a click of its
    /// own claimed again after that (#1535).
    public var batchIDs: Set<Key> { Set(claims.lazy.filter { $0.value.byUpdateAll }.map(\.key)) }

    public func phase(_ key: Key) -> CLIRunPhase { claims[key]?.phase ?? .idle }

    /// The copies whose red line says a click was not run at its turn: about
    /// that click only, so gone once a later check of its tool lands.
    public var notRunAtTurn: Set<Key> {
        Set(redLines.lazy.filter { if case .notRun = $0.value { return true } else { return false } }.map(\.key))
    }

    /// The copies a landing check may change something of — a red line, an
    /// "Updated to X": those `checkLanded` needs to be told about.
    public var readByACheck: Set<Key> { Set(redLines.keys).union(justUpdated.keys) }
}

/// A row's red line, as a transition sets it. Worded by the app, whose strings
/// are localized; a failed command's own message is passed through.
public enum CLIRunRedLine: Equatable, Sendable {
    /// Its update failed: the command's own one-line message.
    case failed(String)
    /// Its update exited 0, and the copy still reads as this version: "Still
    /// X after the update" (`CLITools.settle`).
    case stillOn(String)
    /// Its update exited 0, and no version could be read after it.
    case versionUnreadable
    /// Not run at its turn, and why. Never `.silent`, which says nothing.
    case notRun(CLIRunNotRun)
}

/// A copy as a check that has just landed leaves it (`CLIRunEvent.checkLanded`).
public struct CLIRunChecked: Equatable, Sendable {
    /// Its tool was among those the check asked.
    public var answered: Bool
    /// Its verdict on screen now; nil when no check on screen finds it.
    public var status: CLIToolStatus?

    public init(answered: Bool, status: CLIToolStatus?) {
        self.answered = answered
        self.status = status
    }

    /// Offered now: behind, with a one-click.
    var offered: Bool { status.map { $0.state == .updateAvailable && $0.oneClick != nil } ?? false }
}

/// A row's progress line, as a transition sets it. Worded by the app, whose
/// strings are localized; the command's own output is passed through.
public enum CLIRunLine: Equatable, Sendable {
    /// "Queued".
    case queued
    /// "Starting…", before the command's first line.
    case starting
    /// "Checking…".
    case checking
    /// "Waiting to check": said apart from "Checking…", since under Update
    /// All the check can wait a while on the tool's other lanes.
    case waitingToCheck
    /// A line of the command's output.
    case output(String)
}

/// Something that happened to the runs: a click, a turn, an answer. The app
/// sends each to `CLIRunReducer` with the facts it read at that moment.
public enum CLIRunEvent<Key: Hashable & Sendable>: Equatable, Sendable {
    /// A click on a copy's own Update. `offered`: its offer as the click reads
    /// it, every gate passed; `needsAdministrator`: the route the click
    /// decides on; `queueBusy`: another click's run holds the queue.
    case clicked(Key, offered: Bool, needsAdministrator: Bool, queueBusy: Bool)
    /// A click's turn has come (or its panel's, for one that asks for an
    /// administrator password): what comes before its command.
    case turnCame(Key)
    /// Its offer read at its turn (`CLIRunOffer.atTurn`, `laneAtTurn`).
    case offerRead(Key, CLIRunOffer)
    /// Its command is about to start: a retry, so its last red line and log
    /// no longer hold.
    case commandStarting(Key)
    /// A line of its command's output.
    case outputLine(Key, String)
    /// Its job moved to `phase` (`InstallJobs.phase(of:)`), read when the
    /// app heard of the move.
    case jobPhaseChanged(Key, InstallJobs.Phase?)
    /// Its job ended. `needsRecheck`: what it did changed, or may have, what
    /// its tool's check says; `cancelStopped`: an accepted Cancel kept a
    /// command from starting (`InstallJobs.cancelStoppedSomething`).
    case commandEnded(Key, needsRecheck: Bool, cancelStopped: Bool)
    /// Its command failed, and the Cancel did not stop it first: `message` is
    /// the row's line, `log` the detail pane's.
    case commandFailed(Key, message: String, log: String)
    /// Its update exited 0 and its tool's re-check has landed: `before` is the
    /// version it was run on, `after` the version it reads as now — the
    /// updater's own re-read, else the check's. Exit 0 is not proof of an
    /// update (`CLITools.settle`).
    case updateSettled(Key, before: String?, after: String?)
    /// Its "Updated to X" has been up for the app's confirmation window.
    case confirmationEnded(Key)
    /// The verdicts on screen were published again — a check landed, or the
    /// GitHub pause moved — and these copies are offered now where they were
    /// not before.
    case offersPublished(newlyOffered: Set<Key>)
    /// A check's reports are on screen: each copy of `readByACheck`, as it now
    /// stands. A copy left out is left as it is.
    case checkLanded([Key: CLIRunChecked])
    /// Update All's re-check of the tool of a lane copy not run at its turn
    /// has landed, and took its "Not updated" line away (`checkLanded`):
    /// `why` is what that line said, `clickedNeedsAdministrator` the route
    /// Update All's click read, `now` its verdict on screen now.
    case notRunRechecked(Key, CLIRunNotRun, clickedNeedsAdministrator: Bool, now: CLIToolStatus?)    /// The re-check of these copies' tool starts.
    case recheckStarted([Key])
    /// Its part is over, however it ended: done, failed, not run, cancelled.
    case released(Key)
    /// A click on a copy's Cancel.
    case cancelClicked(Key)
    /// The queue held no click of this copy to take back: it is Update All's,
    /// or its run started. `updateAllWaiting`: Update All waits its turn.
    case notWaitingInQueue(Key, updateAllWaiting: Bool)
    /// The registry's answer to its job's cancel (`InstallJobs.cancel`).
    case cancelAnswered(Key, InstallJobs.CancelResult)
    /// A click on Update All: the copies its lanes would run now, and the
    /// copies that ask for an administrator password, each behind its panel.
    case updateAllClicked(lanes: [Key], asking: [Key])
    /// Update All's next panel is due: the panel before has its answer.
    case panelTurnCame(Key)
    /// A panel copy's update has ended. `updateAllWaiting` as above.
    case panelRunEnded(Key, updateAllWaiting: Bool)
    /// Every panel is up or answered: Update All's lanes take their place in
    /// the queue with these copies, those it still holds.
    case lanesReady([Key])
    /// A lane has reached this copy.
    case laneTurnCame(Key)
    /// Update All, still waiting its turn, was taken back out of the queue.
    case updateAllWithdrawn
    /// Update All's run and its panels' runs have all returned.
    case updateAllFinished
    /// A click on Update All's Cancel.
    case cancelUpdateAllClicked
    /// The queue held no Update All to take back: it runs.
    case updateAllNotWaiting
}

/// What a transition asks the app to do. The app (`CLIToolsModel`) is the
/// effect runner: the synchronous ones it performs as it applies the new
/// state, the async ones — a queue turn, a panel, a check, a command — are
/// awaited by the flow that sent the event.
public enum CLIRunEffect<Key: Hashable & Sendable>: Equatable, Sendable {
    /// Its row's line now reads this.
    case showLine(Key, CLIRunLine)
    /// Its row has no line any more.
    case clearLine(Key)
    /// Its "Updated to X" is up: start its confirmation window, or start it
    /// again, which ends in `confirmationEnded`.
    case startConfirmation(Key)
    /// Wait for its turn in the queue (`CLIRunQueue`), then run it.
    case enqueue(Key)
    /// Run it now, outside the queue: its administrator panel comes at the
    /// click, not when its turn would come — minutes later.
    case raisePanel(Key)
    /// Ask its tool again before its turn gives up on it.
    case check(Key)
    /// Run its command, as the offer read at its turn stands.
    case startCommand(Key)
    /// Its Cancel kept its command from starting: nothing ran, nothing to
    /// re-check, no failure.
    case stoppedBeforeCommand(Key)
    /// Take its click back out of the queue (`CLIRunQueue.cancel`); the
    /// queue's answer comes back as `notWaitingInQueue` when it held none.
    case withdrawClick(Key)
    /// Cancel its job (`InstallJobs.cancel`); the answer comes back as
    /// `cancelAnswered`.
    case cancelJob(Key)
    /// Cancel this copy as its own Cancel would.
    case cancelCopy(Key)
    /// Update All goes on: its panels, then its lanes.
    case runUpdateAll
    /// Put Update All's lanes in the queue with these copies.
    case enqueueUpdateAll([Key])
    /// Read this lane copy's offer at its turn.
    case readLaneOffer(Key)
    /// Take Update All back out of the queue, or cancel each copy it holds
    /// that can still be (`updateAllNotWaiting`).
    case withdrawUpdateAll
    /// Update All's Cancel, as its own button would.
    case cancelUpdateAll
    /// Update All is over.
    case updateAllEnded
}

/// The transitions of the command-line tools' runs (`CLIRunState`), as one
/// pure function. Every decision that used to be read off the model between
/// two awaits — whether a click claims its copy, whether a lane's turn still
/// holds one, which Cancel a click reaches, when Update All is over — is
/// made here on the state and the event's facts alone.
public enum CLIRunReducer {
    public static func reduce<Key: Hashable & Sendable>(
        _ state: CLIRunState<Key>, _ event: CLIRunEvent<Key>
    ) -> (CLIRunState<Key>, [CLIRunEffect<Key>]) {
        var s = state
        var effects: [CLIRunEffect<Key>] = []
        switch event {
        case .clicked(let id, let offered, let needsAdministrator, let queueBusy):
            // Re-read at the click, not trusted from the row: the list may
            // have been re-checked since it was drawn, and an offer already
            // claimed is ours.
            guard offered, s.claims[id] == nil else { return (state, []) }
            s.claims[id] = CLIRunClaim(phase: .running, byUpdateAll: false)
            s.cancels[id] = .available
            // Nothing to clash with: the root shell runs under `env -i` with
            // the system `PATH` and writes only its tool's file
            // (`CLIToolAdministratorRun`); the queue is there for Homebrew
            // against the tools.
            if needsAdministrator { return (s, [.raisePanel(id)]) }
            // Behind another click's run, it waits its turn claimed, as a
            // copy under Update All does: "Queued", with its Cancel live.
            if queueBusy {
                s.claims[id]?.phase = .queued
                effects.append(.showLine(id, .queued))
            }
            effects.append(.enqueue(id))

        case .turnCame(let id):
            s.claims[id]?.phase = .running

        case .offerRead(let id, let offer):
            switch offer {
            case .askTool:
                // Nothing to cancel while its tool is asked: the update
                // starts after. Its phase says so, rather than being read
                // off its missing Cancel.
                s.cancels[id] = nil
                s.claims[id]?.phase = .checkingAtTurn
                return (s, [.showLine(id, .checking), .check(id)])
            case .run, .notRun:
                // Asked, and offered again: its Cancel comes back.
                if offer.offered, s.claims[id]?.phase == .checkingAtTurn {
                    s.cancels[id] = .available
                    s.claims[id]?.phase = .running
                }
            }
            switch offer {
            case .run: effects.append(.startCommand(id))
            case .notRun(.silent), .askTool: break
            // Its row says why; about this click only (`checkLanded`).
            case .notRun(let why): s.redLines[id] = .notRun(why)
            }

        case .commandStarting(let id):
            // A retry: the last failure, or why the last click was not run,
            // no longer holds.
            effects.append(.showLine(id, .starting)) // RED CHECK 4: no clear

        case .outputLine(let id, let line):
            // A line can arrive after the update has finished and its row
            // been released; nor over "Cancelling…", which holds until the
            // row settles.
            guard s.claims[id] != nil, s.cancels[id] != .cancelling else { return (state, []) }
            effects.append(.showLine(id, .output(line)))

        case .jobPhaseChanged(let id, let phase):
            // The Cancel moves with the job: greyed once the command started,
            // live again if it was refused and the tool may try again.
            if let cancel = s.cancels[id] { s.cancels[id] = cancel.following(phase) }

        case .commandEnded(let id, let needsRecheck, let cancelStopped):
            // The job has ended, so a Cancel still live would find nothing
            // and just go away (review, 2026-10-20). Not offered from here.
            if s.cancels[id] == .available { s.cancels[id] = nil }
            // Accepted, and it kept a command from starting: whatever the
            // provider made of the cancel — "could not start" — is no failure.
            if s.cancels[id] == .cancelling, cancelStopped { return (s, [.stoppedBeforeCommand(id)]) }
            if needsRecheck {
                s.claims[id]?.phase = .awaitingCheck
                effects.append(.showLine(id, .waitingToCheck))
            }

        case .commandFailed(let id, let message, let log):
            s.redLines[id] = .failed(message)
            s.logs[id] = log

        case .updateSettled(let id, let before, let after):
            switch CLITools.settle(before: before, after: after) {
            case .updated(let version):
                s.justUpdated[id] = version
                effects.append(.startConfirmation(id))
            // Brew's "brew update finished, but Homebrew is still X" rule: a
            // run that changed nothing reads as a failure, not as silence.
            case .unchanged(let version):
                s.redLines[id] = .stillOn(version)
            case .unreadable:
                s.redLines[id] = .versionUnreadable
            }

        case .confirmationEnded(let id):
            s.justUpdated[id] = nil

        case .offersPublished(let newlyOffered):
            // "Not updated: <reason>" said why a click's copy was not offered
            // at its turn. Offered again — also with no check of its tool, as
            // when the GitHub pause lifts — it would read as the reason beside
            // a live Update (review, #1511 round 2). Offered again only: one
            // said beside an Update that stayed (its update now asks for an
            // administrator password) is kept until its tool's next check.
            for id in newlyOffered {
                if case .notRun? = s.redLines[id] { _ = id } // RED CHECK 6
            }

        case .checkLanded(let copies):
            for (id, copy) in copies {
                if let line = s.redLines[id] {
                    let notRun: Bool
                    if case .notRun = line { notRun = true } else { notRun = false }
                    if !copy.offered {
                        // A red line describes an attempt at an update still on
                        // offer. Once the copy is no longer behind — updated
                        // from a terminal, or gone — it would sit beside a
                        // current install. Nor once nothing is offered:
                        // openclaw's own update reported a failed check after
                        // installing the newest release its node runs
                        // (2026-10-02), and the row went on showing that
                        // failure where it should say the next release needs
                        // a newer Node. Not "Not updated: <reason>", whose copy
                        // is not on offer by its nature: it waits for its own
                        // tool's check, below — any tool's check took it away
                        // (review, 2026-10-20, round 2).
                        if notRun && copy.answered { // RED CHECK 2
                            s.redLines[id] = nil
                            s.logs[id] = nil
                        }
                    } else if copy.answered { // RED CHECK 3
                        // "Not updated: <reason>" was true when the click's
                        // turn came. Kept by the rule above once its tool is
                        // offered again, it read as the reason beside a live
                        // Update on every later check (review, #1511 round 1).
                        s.redLines[id] = nil
                    }
                }
                // "Updated to X" is about the copy as DuoUpdater left it.
                // Something else has changed it since (or it is gone): the
                // claim no longer holds.
                if let version = s.justUpdated[id], copy.status?.installedVersion != version, false { // RED CHECK 5
                    s.justUpdated[id] = nil
                }
            }

        case .notRunRechecked(let id, let why, let clickedNeedsAdministrator, let now):
            // "Not updated: …" goes with its tool's next check, and this one
            // is the batch's own, right after the line was said: a copy
            // skipped for its new administrator route came back as a live
            // Update with nothing said (review, 2026-10-21). Said again while
            // it still holds — not offered, or offered on the other route —
            // unless the row says something else by now.
            guard false, why != .silent, let now, // RED CHECK 1 now.state == .updateAvailable,
                  now.oneClick == nil || now.needsAdministrator != clickedNeedsAdministrator,
                  s.redLines[id] == nil
            else { return (state, []) }
            s.redLines[id] = .notRun(why)

        case .recheckStarted(let ids):
            effects = ids.map { CLIRunEffect<Key>.showLine($0, .checking) }

        case .released(let id):
            // Out of a running or waiting Update All for good, however its
            // claim ended: a click of its own on this row later is not Update
            // All's to cancel or release (review, #1498, rounds 1 and 2).
            effects.append(release(&s, id))

        case .cancelClicked(let id):
            guard s.cancels[id] == .available else { return (state, []) }
            // Its own click, waiting behind another's run, first: out of the
            // queue, its row released by the click's `whenCancelled`.
            effects.append(.withdrawClick(id))

        case .notWaitingInQueue(let id, let updateAllWaiting):
            guard s.claims[id]?.phase == .queued else {
                // Running what comes before its command: through the registry,
                // which refuses once the command started.
                return (s, [.cancelJob(id)])
            }
            // Its claim goes, so it is out of `batchIDs`: its lane, or the
            // panels' loop, skips it.
            effects.append(release(&s, id))
            effects += lastCopyLeft(s, updateAllWaiting: updateAllWaiting)

        case .cancelAnswered(let id, let answer):
            s.cancels[id] = InstallCancelState.after(answer)

        case .updateAllClicked(let lanes, let asking):
            guard !s.updatingAll, !(lanes.isEmpty && asking.isEmpty) else { return (state, []) }
            s.updatingAll = true
            // Every copy is claimed now, not when its turn comes: until then
            // its row says "Queued" instead of offering an Update that would
            // race its lane — while Update All waits behind another click's
            // run too, and for a copy whose panel waits on the one before it.
            for id in lanes + asking {
                s.claims[id] = CLIRunClaim(phase: .queued, byUpdateAll: true)
                s.cancels[id] = .available
                effects.append(.showLine(id, .queued))
            }
            effects.append(.runUpdateAll)

        case .panelTurnCame(let id):
            // Cancelled while it waited for the panel before its own — and
            // perhaps claimed again since by a click of its own.
            if s.claims[id]?.byUpdateAll == true { effects.append(.raisePanel(id)) }

        case .panelRunEnded(let id, let updateAllWaiting):
            effects.append(release(&s, id))
            // Its lane copies cancelled while this one ran (review, #1502
            // round 1).
            effects += lastCopyLeft(s, updateAllWaiting: updateAllWaiting)

        case .lanesReady(let ids):
            // One cancelled while the panels were up is released, and a click
            // of its own may have it now. With none left there is no turn to
            // wait for.
            let held = ids.filter { s.claims[$0]?.byUpdateAll == true }
            if !held.isEmpty { effects.append(.enqueueUpdateAll(held)) }

        case .laneTurnCame(let id):
            // Cancelled while it waited: its row was released then — and may
            // be claimed again by a click of its own, whose "Queued" stays
            // and whose own turn runs it, once (#1535).
            guard s.claims[id]?.byUpdateAll == true else { return (state, []) }
            s.claims[id]?.phase = .running
            effects.append(.readLaneOffer(id))

        case .updateAllWithdrawn:
            // Nothing of the lanes ran. The batch's copies as they stand, not
            // as clicked: one cancelled out of it and clicked again waits as a
            // click of its own, and is left to that click.
            for id in s.batchIDs where s.claims[id]?.phase == .queued {
                effects.append(release(&s, id))
            }
            // Over at once unless a copy behind a panel still runs.
            if s.batchIDs.isEmpty {
                s.updatingAll = false
                effects.append(.updateAllEnded)
            }

        case .updateAllFinished:
            // Every copy it claimed has been released by now.
            s.updatingAll = false

        case .cancelUpdateAllClicked:
            // Still waiting its turn, it leaves the queue first.
            effects.append(.withdrawUpdateAll)

        case .updateAllNotWaiting:
            guard s.updatingAll else { return (state, []) }
            // Each copy that still can be is cancelled; those past their
            // command finish.
            effects = s.batchIDs.filter { s.cancels[$0] == .available }.map { CLIRunEffect<Key>.cancelCopy($0) }
        }
        return (s, effects)
    }

    private static func release<Key: Hashable & Sendable>(_ s: inout CLIRunState<Key>, _ id: Key) -> CLIRunEffect<Key> {
        s.claims[id] = nil
        s.cancels[id] = nil
        return .clearLine(id)
    }

    /// The last copy of an Update All still waiting its turn has gone:
    /// nothing is left for that turn to run.
    private static func lastCopyLeft<Key: Hashable & Sendable>(_ s: CLIRunState<Key>, updateAllWaiting: Bool) -> [CLIRunEffect<Key>] {
        updateAllWaiting && s.batchIDs.isEmpty ? [.cancelUpdateAll] : []
    }
}
