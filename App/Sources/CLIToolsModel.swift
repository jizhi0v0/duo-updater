import Foundation
import Observation
import DuoUpdaterCore

/// One install of one tool: a `CLIToolStatus`'s identity. Two tools cannot share
/// a path, but nothing here relies on it — an install is always named by both.
struct CLIToolID: Hashable, Sendable {
    let kind: CLIToolKind
    let path: String

    /// The workbench sidebar's selection tag, "claude-code:/Users/…/claude". The
    /// kind's raw value holds no colon, so the path is everything after the first.
    var tag: String { "\(kind.rawValue):\(path)" }
}

extension CLIToolStatus {
    var toolID: CLIToolID { CLIToolID(kind: kind, path: path) }
}

/// One click in the CLI tab that changes something, as its queue
/// (`CLIRunQueue`) names it: one of Homebrew's runs, or an "Other tools" update.
enum CLIRun: Hashable, Sendable {
    /// `brew update`.
    case homebrewUpdate
    /// Homebrew's Upgrade All.
    case upgradeAll
    /// One formula's own upgrade.
    case upgradeFormula(String)
    /// One copy's own update.
    case tool(CLIToolID)
    /// "Other tools" Update All.
    case updateAllTools
}

extension CLIToolSighting {
    var toolID: CLIToolID { CLIToolID(kind: kind, path: path) }
}

/// Command-line tools that are not Homebrew's — Claude Code, bub, fx — as the
/// popover's "command-line tools" row and the workbench CLI tab show them.
///
/// Its own model rather than more of `AppListModel`: each tool has its own rules
/// (Claude Code's channel and auto-update switch live in Claude Code's settings,
/// not ours), and those rules stay in each tool's `CLIToolProvider`. This model
/// only sums the providers up and runs their updates, so a later tool is one more
/// provider here without touching the app list.
///
/// Free of SwiftUI and of `AppListModel` on purpose: the app test target compiles
/// this file on its own and drives it with injected providers, so no test reaches
/// the network or runs an installer.
@MainActor
@Observable
final class CLIToolsModel {

    /// Every install found, with its verdict, in `CLIToolKind.allCases` order and
    /// each tool's own order within that. Empty until the first check returns
    /// (`checked`). The checks' verdicts (`checkedStatuses`), with a one-click
    /// held back while the GitHub API budget its updater would spend is closed
    /// (`gitHubPause`).
    private(set) var statuses: [CLIToolStatus] = []
    /// The verdicts as the checks returned them.
    @ObservationIgnored private var checkedStatuses: [CLIToolStatus] = []

    /// Until when each GitHub API budget is closed (`GitHubRateLimitGate`), as
    /// the app last read it; a credential absent is open. While the budget a
    /// tool's own update command would spend is closed, its one-click is held
    /// back (`CLIToolKind.updaterSpendsGitHubAPI`): the command asks GitHub
    /// from its own process, which the gate cannot stop.
    @ObservationIgnored var gitHubPause: [GitHubRateLimitGate.Credential: Date] = [:] {
        didSet { publishStatuses() }
    }
    /// Whether a GitHub token resolves, so uv, bun and mise would be handed it.
    @ObservationIgnored var updatersGetOurToken = false

    private func publishStatuses() {
        let current = self.now()
        let wasOffered = Set(statuses.lazy.filter { $0.oneClick != nil }.map(\.toolID))
        statuses = checkedStatuses.map {
            $0.applyingGitHubPause(gitHubPause, updatersGetOurToken: updatersGetOurToken, now: current)
        }
        // A "Not updated" line beside an Update offered again goes
        // (`CLIRunEvent.offersPublished`).
        let newlyOffered = Set(statuses.lazy.filter { $0.oneClick != nil }.map(\.toolID)).subtracting(wasOffered)
        if !newlyOffered.isEmpty { send(.offersPublished(newlyOffered: newlyOffered)) }
    }
    /// The tool-wide settings each tool's verdicts were made under, for its group
    /// header: Claude Code's channel and auto-update, fx's settings.
    private(set) var contexts: [CLIToolKind: CLIToolReport.Context] = [:]
    /// Flips true once the first check returns.
    private(set) var checked = false
    /// A check is in flight.
    private(set) var checking = false

    /// Every install the last look found — the local scan's answer until the first
    /// check lands, the check's own installs after. Known long before the verdicts
    /// (the scan is local; the check waits on the network), which is what lets the
    /// popover reserve its row before the check lands, like `brewInstalled` does
    /// for the brew row.
    private(set) var sightings: [CLIToolSighting] = []

    /// Every copy's claim and Cancel, and whether Update All runs
    /// (`CLIRunState`): from the click until the re-check after it has landed
    /// — and, under `updateAll`, every copy it will update, from the start, so
    /// a copy waiting its turn shows "Queued" rather than a live Update. Also
    /// what each row says once its run is over: its red line, its log, its
    /// "Updated to X" (`errors`, `errorLogs`, `justUpdated`), set and cleared
    /// by the same reducer — at a retry, a failure, a settle, a check landing
    /// (phase 4b).
    /// Changed only through `send`, by `CLIRunReducer`: the transitions are a
    /// pure function in Core, replayed there as event sequences, and this
    /// model is their effect runner — the awaits stay here (UI = f(state),
    /// phase 4). Before, they were writes to `claims` and `cancels` between
    /// two awaits, tested by polling the model (#1520, #1522, #1535, #1536).
    private var runState = CLIRunState<CLIToolID>() {
        didSet { smoothCancelRows() }
    }
    /// Installs DuoUpdater is updating right now (`CLIRunState.claims`).
    var updating: Set<CLIToolID> { runState.updating }
    /// The copies claimed whose turn has not come: behind another click's run,
    /// or in a lane of `updateAll`'s whose earlier copies are still running.
    var queued: Set<CLIToolID> { runState.queued }
    /// The copies whose update has run and whose tool's re-check has not landed:
    /// still claimed, so the old verdict's Update does not come back, but no
    /// longer running anything. Under `updateAll` the re-check waits for the
    /// tool's other lanes, so this can last as long as the slowest of them.
    var awaitingCheck: Set<CLIToolID> { runState.awaitingCheck }
    /// Every click in the CLI tab that changes something, Homebrew's included,
    /// run one at a time in the order made (`CLIRunQueue`). Here because the
    /// tools' runs are; `AppListModel` puts Homebrew's in the same one.
    let runQueue = CLIRunQueue<CLIRun>()
    /// True for the whole of `updateAll`, including the re-checks at the end of
    /// each tool's lanes, so the popover row stays in its updating state instead
    /// of flashing back to "Update" between two copies.
    var updatingAll: Bool { runState.updatingAll }
    /// The Cancel of each copy whose update DuoUpdater runs
    /// (`InstallCancelState`): live while it waits its turn under `updateAll`
    /// or runs what comes before its command, greyed once the command started
    /// (its `InstallCommit`). Cleared with the claim (`release`).
    var cancels: [CLIToolID: InstallCancelState] { runState.cancels }
    /// `cancels` and the progress lines' stages as the rows draw them
    /// (`InstallRowSmoothing`): an accepted cancel says "Cancelling…" only once
    /// it has lasted `InstallRowSmoothing.cancellingDelay`, and one that ended
    /// the update sooner never does; a stage — "Queued", "Starting…" and the
    /// command's output, "Checking…" — stays up for `InstallRowSmoothing.dwell`
    /// before the next one replaces it, as an app row's does.
    private(set) var cancelRows = InstallRowSmoothing<CLIToolID>.Output()
    /// Each row's line with the stage it belongs to, so a row whose stage is
    /// held back keeps that stage's line (`progressLine`).
    @ObservationIgnored private var progressLines = InstallRowLines<CLIToolID>()
    @ObservationIgnored private var cancelRowSmoothing = InstallRowSmoothing<CLIToolID>()
    @ObservationIgnored private var cancelRowWake: Task<Void, Never>?
    /// The copies the running (or waiting) `updateAll` still holds. A copy
    /// cancelled while queued is not among them, nor is one a click of its own
    /// claimed again after that: its lane, or the loop raising the panels in
    /// `updateAll`, skips it (only one `updateAll` runs at a time).
    private var batchIDs: Set<CLIToolID> { runState.batchIDs }
    /// The latest output line of each running update. Set through
    /// `setProgress`, which records its stage for the rows (`progressLine`).
    private(set) var progress: [CLIToolID: String] = [:] {
        didSet { smoothCancelRows() }
    }
    /// The last failed update of each install: the row's one line. Also an update
    /// that exited 0 but left the version where it was, and a click not run at
    /// its turn. Worded here from `CLIRunState.redLines`, which the reducer
    /// sets and clears — at a retry, a failure, a settle, a check landing.
    var errors: [CLIToolID: String] { runState.redLines.mapValues(Self.redLine) }
    /// The full output of each failed update: the detail pane's log
    /// (`CLIRunState.logs`).
    var errorLogs: [CLIToolID: String] { runState.logs }
    /// Installs just updated → the version they now read as
    /// (`CLIRunState.justUpdated`). Open sessions keep the old version until
    /// restarted, so the row says so.
    ///
    /// A confirmation, not a state: each entry clears itself after
    /// `confirmationWindow`, as an app row's "Updated ✓" does
    /// (`AppListModel.markJustUpdated`). Kept until something changed the copy, it
    /// pinned "Claude Code updated to 2.1.285" on the popover for good — the first
    /// thing the user saw after a real update on 2026-10-01.
    var justUpdated: [CLIToolID: String] { runState.justUpdated }
    /// Who is running each install right now (`CLIToolProcesses`), for the row's
    /// running dot and its "still on the old version" line. Only installs
    /// something runs are in it. Re-read by `watchProcesses`, on its own clock.
    /// A stale copy is in it only once two reads apart have seen it
    /// (`staleSeen`). Surfaces read it through `liveUsage`.
    private(set) var usage: [CLIToolID: CLIToolUsage] = [:]
    /// Whether the watch, after its last read, found a window of the app on
    /// screen (or was in a wake's grace); reads outside the watch — after a
    /// check, a confirm, an exit — leave it as it is. A read with none on screen is for the notice only:
    /// a popover opened later draws nothing from it, and is drawn again — this
    /// flag is observed — when the read its open wakes lands. A clock check
    /// could not do that: SwiftUI does not observe the clock, and the menu's
    /// view tree outlives a closed popover (review, #1374 round 5).
    private(set) var usageDrawable = false
    /// When each stale process the last read saw was first seen stale: one is
    /// shown only once it has been for `staleConfirmSeconds`. By time, not by
    /// reads: a confirm read left by one short process and a tick of the clock
    /// can be under a second apart, and counting reads let a process that
    /// lived 1 s through (measured 2026-10-17, 1 of 6).
    @ObservationIgnored private var staleSeen: [StaleProcess: Date] = [:]
    private struct StaleProcess: Hashable { let id: CLIToolID; let pid: pid_t }
    /// Reads left on the 3 s clock after a wake, whether or not AppKit says a
    /// window is on screen yet at that moment (review, #1374).
    @ObservationIgnored private var wakeGraceReads = 0
    /// One kernel exit watch per process `usage` names, so a dot, a mark and
    /// a notice go when the process does — not at the next tick, which with no
    /// window on screen left a notice up for 60 s after the session closed
    /// (measured 2026-10-17).
    @ObservationIgnored private var exitWatches: [pid_t: DispatchSourceProcess] = [:]
    /// The stale processes each install's banner has named, so one is posted
    /// for each update a running copy missed, not on every read
    /// (`onStaleProcesses`). Forgotten once the install has none left.
    @ObservationIgnored private var announcedStale: [CLIToolID: Set<pid_t>] = [:]
    /// Told, after a read of the process table, which installs newly have
    /// processes left on a copy from before an update, and which no longer
    /// have any. `AppListModel` posts and withdraws the banner.
    @ObservationIgnored var onStaleProcesses: (@MainActor (
        _ newly: [CLIToolStatus], _ changed: [CLIToolStatus], _ cleared: [CLIToolID]) -> Void)?
    /// The stale processes each banner names now, to bring its text up to date
    /// (`changed`) when some have gone and none is new.
    @ObservationIgnored private var bannerStale: [CLIToolID: Set<pid_t>] = [:]

    /// The stale processes `id`'s banner should name now; nil once withdrawn.
    func bannerProcesses(_ id: CLIToolID) -> Set<pid_t>? { bannerStale[id] }
    @ObservationIgnored private var processWatch: Task<Void, Never>?
    /// The watch's current wait; cancelled to wake it early (`wakeProcessWatch`).
    @ObservationIgnored private var processWatchSleep: Task<Void, Never>?
    /// Update rows whose release notes mark breaking changes in the versions the
    /// update brings → those versions, oldest first
    /// (`CLIToolChangelog.breakingVersions`). A hint beside the version, never a
    /// gate. Filled after a check lands (`loadBreaking`).
    private(set) var breaking: [CLIToolID: [String]] = [:]
    /// The range, "installed|latest", each row's `breaking` was read for, so a
    /// check that finds the same update fetches nothing again — even where the
    /// notes have no section for the latest yet, which `releaseNotes` would
    /// otherwise fetch again every time.
    @ObservationIgnored private var breakingRead: [CLIToolID: String] = [:]
    /// The latest `loadBreaking` pass; the next one waits for it.
    @ObservationIgnored private var breakingPass: Task<Void, Never>?

    /// Installs with an update on their own channel.
    var outdated: [CLIToolStatus] { statuses.filter { $0.state == .updateAvailable } }
    /// The outdated installs one click may update: every gate passed and
    /// DuoUpdater is not already updating it.
    var oneClickable: [CLIToolStatus] {
        outdated.filter { $0.oneClick != nil && !updating.contains($0.toolID) }
    }
    /// The outdated installs a click updates, whether or not one is running now:
    /// what an "updates" count says. A held-back one is not among them — counted
    /// with them, "2 updates" sat beside one Update button (2026-10-06: openclaw
    /// 2026.9.8 needs Node ≥ 24.16, its prefix runs 24.13).
    var offered: [CLIToolStatus] { outdated.filter { $0.oneClick != nil } }
    /// The outdated installs no click will update: a gate held them back
    /// (`CLIToolStatus.withheld` says which).
    var heldBack: [CLIToolStatus] { outdated.filter { $0.oneClick == nil } }
    /// The offered updates Update All runs in its lanes: not one that needs an
    /// administrator password (`CLIToolStatus.needsAdministrator`). Lanes never
    /// raise a panel; those are `adminOffered`.
    var batchOffered: [CLIToolStatus] { offered.filter(\.joinsUpdateAll) }
    /// `batchOffered` less the copies already updating: what Update All would
    /// start now in its lanes.
    var batchable: [CLIToolStatus] { oneClickable.filter(\.joinsUpdateAll) }
    /// The offered updates that ask for an administrator password. Update All
    /// asks for each at its click, one panel per copy, before its lanes' turn —
    /// never one panel for all of them, which would run every such command as
    /// root on a single answer about none of them in particular.
    var adminOffered: [CLIToolStatus] { offered.filter(\.needsAdministrator) }
    /// `adminOffered` less the copies already updating: the panels Update All
    /// would raise now.
    var adminBatchable: [CLIToolStatus] { oneClickable.filter(\.needsAdministrator) }
    /// How many offered updates need sudo: the summary's "need sudo".
    var needSudoCount: Int { adminOffered.count }
    /// Whether Update All has anything to start now, in a lane or behind a panel.
    var updateAllStartable: Bool { !batchable.isEmpty || !adminBatchable.isEmpty }
    /// Whether Update All has anything on offer, running or not.
    var updateAllOffered: Bool { !batchOffered.isEmpty || !adminOffered.isEmpty }

    /// Whether this Mac has anything for the CLI surface to show at all.
    var hasAnything: Bool { !statuses.isEmpty }

    /// Installs whose check gave no verdict — broken, not signed by the vendor,
    /// version unreadable, or the channel unreachable. While any is here the row
    /// must not claim "up to date", the same rule the brew row keeps for unchecked
    /// packages.
    var unchecked: [CLIToolStatus] { statuses.filter { $0.state == .unknown } }

    /// The install `id` names, if the last check found it.
    func status(_ id: CLIToolID) -> CLIToolStatus? {
        statuses.first { $0.toolID == id }
    }

    /// Claude Code's settings, once a check has read them.
    var claudeCodeSettings: ClaudeCodeSettings? {
        guard case .claudeCode(let settings)? = contexts[.claudeCode] else { return nil }
        return settings
    }

    /// One per tool, in `CLIToolKind.allCases` order: every report and scan is
    /// put in that order, whichever provider answers first.
    @ObservationIgnored private let providers: [any CLIToolProvider]
    /// The clock `refreshOnOpen` measures a report's age by. Injected so the
    /// interval can be tested without waiting it out.
    @ObservationIgnored private let now: @Sendable () -> Date
    /// How long an "Updated to X" confirmation stays. Injected so tests can end it
    /// without waiting.
    @ObservationIgnored private let confirmationWindow: Duration
    /// The running confirmation window per install, so a second update restarts it.
    @ObservationIgnored private var confirmationTimers: [CLIToolID: Task<Void, Never>] = [:]

    /// What the last check's own scans saw, for `refreshOnOpen` to hold a fresh
    /// scan against.
    @ObservationIgnored private var checkedSightings: [CLIToolSighting] = []

    /// Per provider (by index in `providers`), when the check whose report is on
    /// screen started; no entry until one has landed. Per provider because the
    /// background check asks only the tools whose turn it is (`isDue`), and an
    /// update re-checks only its own: each tool's report is as old as its own
    /// last check.
    @ObservationIgnored private var checkedAt: [Int: Date] = [:]
    /// How old a report may get before an open of the popover checks again.
    static let recheckInterval: TimeInterval = 15 * 60
    /// How often the background check may ask a tool whose check reads the
    /// GitHub API (`CLIToolProvider.readsGitHubAPI`) while no GitHub token
    /// resolves. With a token there is no floor: a 304 costs nothing then.
    nonisolated static let gitHubFloor: TimeInterval = 15 * 60

    /// Bumped by every check; a check applies a tool's report only if it is still
    /// the latest one started for that tool (`latestCheck`). Reads overlap — a
    /// popover open can start one, and each update ends with one — and a check
    /// started before an update finished must not land after the re-check that
    /// follows it and put the stale "outdated" verdict back.
    /// `AppListModel.readBrewFormulae`'s rule, per tool: an update re-checks only its own.
    @ObservationIgnored private var refreshGeneration = 0
    /// Per provider (by index in `providers`), the generation of the latest check
    /// started that asks it.
    @ObservationIgnored private var latestCheck: [Int: Int] = [:]
    /// Per provider, the generation of the check whose report is on screen:
    /// whether it started before an Update All lane ran anything
    /// (`laneOfferAtTurn`).
    @ObservationIgnored private var reportGeneration: [Int: Int] = [:]
    /// Per provider, the report on screen.
    @ObservationIgnored private var reports: [Int: CLIToolReport] = [:]
    /// Checks started and not yet returned; `checking` while any is out.
    @ObservationIgnored private var checksInFlight = 0

    /// Called whenever a check's reports have landed, whichever path asked: the
    /// app announces new versions from there (`AppListModel.notifyNewCLIToolUpdates`),
    /// so one found by an open of the popover is announced like one the schedule
    /// found.
    @ObservationIgnored var onReport: (@MainActor () -> Void)?

    /// Each document's whole release notes, fetched once and kept for the session:
    /// every install's pane reads the same document (Claude Code's is ~860 KB, 407
    /// sections on 2026-09-30), so switching between installs should not fetch and
    /// parse it again. By `CLIToolStatus.releaseNotesKey`, since a tool can have
    /// several (rustup's and Rust's; one per npm package).
    @ObservationIgnored private var releaseNotesCache: [String: Changelog] = [:]

    init(
        providers: [any CLIToolProvider] = CLITools.providers(),
        now: @escaping @Sendable () -> Date = { Date() },
        confirmationWindow: Duration = .seconds(2)
    ) {
        self.providers = CLITools.inKindOrder(providers)
        self.now = now
        self.confirmationWindow = confirmationWindow
    }

    /// Find the installs without checking them — local and network-free — so the
    /// row's space is known before any check. Run once at launch; a check that has
    /// already landed is newer and wins, so this never overwrites it.
    func scanInstalls() async {
        let found = await scanAll()
        guard !checked else { return }
        sightings = found
    }

    /// This model's lane (`RefreshLane`): what an open of the popover or the
    /// workbench, a focus of the workbench and a tick of the background schedule
    /// call for is decided here (`decide`), one check at a time, and logged under
    /// `refresh[cli-tools]`. The plan is which tools to check (indices into
    /// `providers`); triggers that arrive during a check are decided after it
    /// lands, against its report. An update's own re-check (`check([provider])`)
    /// does not go through here: it re-asks one tool the moment its update ends.
    @ObservationIgnored private(set) lazy var lane = RefreshLane<Set<Int>>(
        "cli-tools",
        decide: { [weak self] trigger in await self?.decide(trigger) ?? .skip(because: "model gone") },
        merge: { $0.union($1) },
        work: { [weak self] plan in await self?.check(plan.sorted()) })

    /// Whether a GitHub token resolves, for the background check (`onTick`).
    /// Asked only when a tool would be held back for want of one: resolving a
    /// token can run `gh auth token`.
    @ObservationIgnored private var hasGitHubToken: @MainActor () async -> Bool = { false }

    /// How soon after a check an open re-asks a copy it left unanswered
    /// (offline, GitHub's rate limit). Every open re-asked every tool before, so
    /// a popover opened again and again while rate-limited kept asking GitHub —
    /// which says not to retry before `x-ratelimit-reset`, and that "continuing
    /// to make requests while you are rate limited may result in the banning of
    /// your integration" (docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api,
    /// read 2026-10-14; it does not say whether the refused requests count).
    static let unansweredRecheckInterval: TimeInterval = 60

    private func decide(_ trigger: RefreshTrigger) async -> RefreshDecision<Set<Int>> {
        switch trigger {
        case .popoverOpen, .workbenchOpen, .workbenchFocus:
            // Who runs what, now, whatever the check decides: the process watch
            // may be in its hidden-window sleep (`watchProcesses`), and a dot that
            // came up to a minute after the window did read as wrong (2026-10-16).
            wakeProcessWatch()
        default: break
        }
        switch trigger {
        case .popoverOpen, .workbenchOpen: return await onOpen()
        case .workbenchFocus: return await onFocus()
        case .backgroundTick(let interval): return await onTick(interval: interval)
        case .afterAction: return .skip(because: "an update re-checks its own tool by itself")
        // The button asks for a fresh answer from everything: every tool, past
        // the age and unanswered throttles. Still not while an update runs: it
        // re-checks by itself, and a check mid-run reads a half-done copy.
        case .manual:
            guard updating.isEmpty, !updatingAll else { return .skip(because: "an update is running") }
            return .run(Set(providers.indices), because: "the refresh button")
        case .diskChanged, .backstopTick:
            return .skip(because: "the apps lane's; tools are checked on opens, focuses and ticks")
        }
    }

    /// What an open of the popover does: a local scan, and the networked check
    /// only when the report on screen may be wrong — the app list's rule (a full
    /// check on the first open, a local rescan on later ones) applied here. Checks
    /// when there is no completed report yet, when it is older than
    /// `recheckInterval`, when the scan disagrees with it (a copy of any tool
    /// appeared or went, or its version moved — a `claude update` in a terminal),
    /// or when it left a copy unanswered and `unansweredRecheckInterval` has
    /// passed since that copy was asked. An update re-checks by itself and does
    /// not go through here.
    ///
    /// A change the scan sees, or an unanswered copy, re-checks every tool, as one
    /// check of all of them (`refresh`) did before the reports had ages of their
    /// own. Age alone re-checks only the tools whose report is that old: the
    /// background check (`backgroundCheck`) keeps those ages too, so an open
    /// right after it asks nothing again.
    ///
    /// One open at a time: the lane's (`RefreshLane`). Only opens and the other
    /// triggers this lane decides queue behind one another; an update's re-check
    /// of its one tool answers for that tool only, so an open during one still
    /// decides for every tool (found in review, #1290).
    func refreshOnOpen() async {
        await lane.handle(.popoverOpen)
    }

    private func onOpen() async -> RefreshDecision<Set<Int>> {
        let all = Set(providers.indices)
        guard !checkedAt.isEmpty else { return .run(all, because: "no report yet") }
        let found = await scanAll()
        // What the scan can see change without a check: which copies of which
        // tool there are, the version each one reads as, and the rest of what its
        // verdict rests on (`CLIToolSighting.state`) — held against what the last
        // check's own scan saw, built by the same rule.
        if Set(found) != Set(checkedSightings) {
            return .run(all, because: "the scan disagrees with the last check")
        }
        let now = now()
        var held: String?
        let unanswered = unchecked.filter(Self.mayClearByItself)
        if !unanswered.isEmpty {
            // Each copy asked when its tool's report was; the longest-waiting one decides.
            let asked = unanswered.compactMap { provider(of: $0).flatMap { checkedAt[$0] } }.min()
            let age = asked.map { now.timeIntervalSince($0) } ?? .infinity
            let names = unanswered.map { "\($0.kind.displayName) (\($0.withheld.map { "\($0)" } ?? "no verdict"))" }
                .joined(separator: ", ")
            let what = "\(unanswered.count) unanswered — \(names) — asked \(Int(age))s ago"
            if age >= Self.unansweredRecheckInterval { return .run(all, because: what) }
            held = "\(what), re-asked after \(Int(Self.unansweredRecheckInterval))s"
        }
        let stale = providers.indices.filter { index in
            checkedAt[index].map { now.timeIntervalSince($0) >= Self.recheckInterval } ?? true
        }
        guard !stale.isEmpty else { return .skip(because: held ?? "every report is fresh and the scan agrees") }
        return .run(Set(stale), because: "\(stale.count) report(s) \(Int(Self.recheckInterval / 60)) min old or more: \(names(stale))")
    }

    /// What the workbench becoming key again does: a local scan, and a check of
    /// every tool only when the scan disagrees with the report on screen (a
    /// copy appeared or went, or its version moved — a tool installed in a
    /// terminal while the window was open). The apps' rule on the same event
    /// (`AppListModel.refreshLocal`): a disk re-read, never the network for its
    /// own sake, so going back and forth between windows asks nothing. Age and
    /// unanswered copies are left to the popover's open (`refreshOnOpen`) and
    /// the background check. Skipped until a first report has landed (the
    /// window's open checks), while an update's re-check is out (its report is
    /// about to replace the one this compares against) and while an update runs
    /// (which re-checks by itself, and a scan mid-run sees a half-done copy).
    func refreshOnFocus() async {
        await lane.handle(.workbenchFocus)
    }

    private func onFocus() async -> RefreshDecision<Set<Int>> {
        guard !checkedAt.isEmpty else { return .skip(because: "no report yet; the open checks") }
        guard !checking else { return .skip(because: "an update's re-check is out") }
        guard updating.isEmpty, !updatingAll else { return .skip(because: "an update is running") }
        let found = await scanAll()
        guard Set(found) != Set(checkedSightings) else { return .skip(because: "the scan agrees with the last check") }
        return .run(Set(providers.indices), because: "the scan disagrees with the last check")
    }

    /// What a tick of the app's background schedule does for these tools: check
    /// every tool whose turn it is (`isDue`), each on its own clock. `interval` is
    /// the app's check interval; nil is "Only when I check", and then nothing runs
    /// — a tick already under way when the user chose it must not start a check.
    ///
    /// `hasGitHubToken` is asked only when a tool would be held back for want of
    /// one: resolving a token can run `gh auth token`.
    func backgroundCheck(
        interval: TimeInterval?, hasGitHubToken: @escaping @MainActor () async -> Bool
    ) async {
        self.hasGitHubToken = hasGitHubToken
        await lane.handle(.backgroundTick(interval: interval))
    }

    private func onTick(interval: TimeInterval?) async -> RefreshDecision<Set<Int>> {
        guard interval != nil else { return .skip(because: "Only when I check") }
        let now = now()
        let due = { (token: Bool) in
            self.providers.indices.filter { index in
                Self.isDue(readsGitHubAPI: self.providers[index].readsGitHubAPI,
                           checkedAt: self.checkedAt[index], now: now, hasGitHubToken: token)
            }
        }
        var indices = due(false)
        if indices.count < providers.count, await hasGitHubToken() { indices = due(true) }
        guard !indices.isEmpty else { return .skip(because: "no tool's turn yet") }
        let held = providers.count - indices.count
        return .run(Set(indices), because: "\(indices.count) tool(s) due" + (held > 0 ? ", \(held) held to the GitHub floor" : ""))
    }

    /// The tools at `indices`, by name, for the log.
    private func names(_ indices: [Int]) -> String {
        indices.map { providers[$0].kind.displayName }.joined(separator: ", ")
    }

    /// Whether a tool is checked on this tick. Every tool is, except one whose
    /// check reads the GitHub API while no token resolves: that one waits until
    /// `gitHubFloor` has passed since its last check started. Anonymous, the API
    /// allows 60 requests an hour per IP, and the app's own rows spend from the
    /// same budget; at the 5-minute schedule two such tools alone would spend 24.
    /// Measured from the start of a check, as the schedule's ticks are spaced at
    /// least an interval apart from the end of one round to the start of the next.
    nonisolated static func isDue(
        readsGitHubAPI: Bool, checkedAt: Date?, now: Date, hasGitHubToken: Bool
    ) -> Bool {
        guard readsGitHubAPI, !hasGitHubToken, let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) >= gitHubFloor
    }

    /// Whether an unchecked install's reason can go away without anything on disk
    /// changing — the network came back, the other update finished — and so is
    /// worth a re-check on the next open (`CLIRunOffer.mayClearByItself`, in
    /// Core since an Update All lane's read at its turn rests on it too).
    nonisolated static func mayClearByItself(_ status: CLIToolStatus) -> Bool {
        CLIRunOffer.mayClearByItself(status)
    }

    /// Re-scan and re-check every tool.
    ///
    /// Every provider is asked at once, and the answers are applied together when
    /// the last one lands — not each as it lands. The popover row makes one claim
    /// about all of them ("up to date", "2 updates"), and a tool whose verdict had
    /// not landed yet would be missing from that claim rather than unanswered in
    /// it: the row could seal "up to date" over a copy nobody had checked. The
    /// cost: the slowest provider holds every tool's verdict back. Claude Code's
    /// requests give up after 15 s without data (`ClaudeCodeRelease`); a provider
    /// must keep its own waits that short.
    func refresh() async {
        await check(Array(providers.indices))
    }

    /// Re-check the providers at `indices` only, and apply their reports together;
    /// every other tool keeps the verdict it has. What an update ends with: it
    /// changed one tool's copies, and re-asking every other tool's channel made
    /// all of them wait on the slowest (and spun every group's spinner).
    private func check(_ indices: [Int]) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        for index in indices { latestCheck[index] = generation }
        let started = now()
        checksInFlight += 1
        checking = true
        // Each provider's requests filed under its tool, so the request log's App
        // column names it; npm and bun packages are filed per package below that.
        //
        // In a task of the model's own, not the caller's — `refresh()`'s rule
        // in `AppListModel`. The popover's and the workbench's `.task` are
        // cancelled when the view goes, and a cancelled check does not come back
        // empty: its requests fail and its `--version` children are killed
        // (`.terminateChild`), so every tool came back "Couldn't reach … release
        // channel" / "Couldn't read the installed version" and that was put on
        // screen (2026-10-14, the popover opened and closed with the workbench
        // up). Run to the end, the check's answers are the real ones.
        let clock = ContinuousClock()
        let began = clock.now
        let timed = await Task {
            await self.inProviderOrder(indices) { provider in
                let clock = ContinuousClock()
                let began = clock.now
                let report = await RequestAttribution.withApp(provider.kind.displayName) { await provider.check() }
                return (report, clock.now - began)
            }
        }.value
        let answers = timed.map { ($0.0, $0.1.0) }
        checksInFlight -= 1
        checking = checksInFlight > 0
        let current = answers.filter { latestCheck[$0.0] == generation }
        // What tuning reads: how long the check took, which tools held it up
        // (every verdict waits for the slowest), and what it left unanswered.
        let slowest = timed.sorted { $0.1.1 > $1.1.1 }.prefix(3)
            .map { "\(providers[$0.0].kind.displayName) \(Log.seconds($0.1.1))" }.joined(separator: ", ")
        let unanswered = current.flatMap { $0.1.statuses }.filter { $0.state == .unknown }.count
        let superseded = answers.count - current.count
        Log.app.notice("cli-tools check of \(indices.count, privacy: .public) tool(s): \(Log.seconds(clock.now - began), privacy: .public); slowest \(slowest, privacy: .public); \(unanswered, privacy: .public) copies not checked\(superseded > 0 ? ", \(superseded) superseded by a later check" : "", privacy: .public)")
        guard !current.isEmpty else { return }
        for (index, _) in current { reportGeneration[index] = generation }
        apply(current, startedAt: started)
    }

    private func scanAll() async -> [CLIToolSighting] {
        await inProviderOrder(Array(providers.indices)) { await $0.scan() }.flatMap { $0.1 }
    }

    /// `work` run on the providers at `indices` at once, each answer with its
    /// provider's index, in `providers` order (`CLITools.inProviderOrder`).
    private func inProviderOrder<T: Sendable>(
        _ indices: [Int], _ work: @escaping @Sendable (any CLIToolProvider) async -> T
    ) async -> [(Int, T)] {
        await CLITools.inProviderOrder(providers, indices, work)
    }

    /// Put `answers` on screen in place of their providers' last reports, each as
    /// old as the check that asked it (`startedAt`).
    private func apply(_ answers: [(Int, CLIToolReport)], startedAt: Date) {
        // Only the tools asked: the others' verdicts are as old as they were.
        for (index, report) in answers {
            reports[index] = report
            checkedAt[index] = startedAt
        }
        let ordered = reports.keys.sorted().compactMap { reports[$0] }
        contexts = Dictionary(ordered.map { ($0.kind, $0.context) }, uniquingKeysWith: { a, _ in a })
        checkedStatuses = ordered.flatMap(\.statuses)
        publishStatuses()
        checkedSightings = ordered.flatMap(\.sightings)
        sightings = checkedSightings
        checked = true
        let byID = Dictionary(statuses.map { ($0.toolID, $0) }, uniquingKeysWith: { a, _ in a })
        let answered = Set(answers.map(\.1.kind))
        // Which red lines and "Updated to X" still hold is the reducer's to
        // say (`CLIRunEvent.checkLanded`): each copy it holds one for, as it
        // stands now, and whether its own tool was asked.
        let copies = runState.readByACheck.map { id in
            (id, CLIRunChecked(answered: answered.contains(id.kind), status: byID[id]))
        }
        if !copies.isEmpty { send(.checkLanded(Dictionary(uniqueKeysWithValues: copies))) }
        onReport?()
        Task { await loadBreaking() }
        // A check that finds the tool current is when a copy it updated by
        // itself is first known to be the new one; say now who missed it.
        Task { await refreshUsage() }
    }

    /// How often `watchProcesses` reads the process table while one of the
    /// app's windows (the popover, the workbench) is on screen, and while none
    /// is. A read is one `proc_pidpath` per process — 1.2–1.4 ms for 1049 of
    /// them, measured 2026-10-16 — so the hidden clock is there for the
    /// banner, the visible one for the dot.
    static let processWatchVisibleInterval: Duration = .seconds(3)
    static let processWatchHiddenInterval: Duration = .seconds(60)
    /// How soon a new stale copy is read again before it is shown: one that
    /// is gone by then was the old binary's last short command, not a session
    /// left behind.
    static let staleConfirmDelay: Duration = .milliseconds(2200)  // lands past `staleConfirmSeconds`
    static let staleConfirmSeconds: TimeInterval = 2
    /// Who runs `id` now, or nil — also while the last read was made with no
    /// window on screen (`usageDrawable`).
    func liveUsage(_ id: CLIToolID) -> CLIToolUsage? {
        usageDrawable ? usage[id] : nil
    }

    /// Read who runs each install now, and keep reading on the clocks above.
    /// `isVisible` says whether a window of the app is on screen. Started once.
    func watchProcesses(isVisible: @escaping @MainActor () -> Bool) {
        guard processWatch == nil else { return }
        processWatch = Task { [weak self] in
            var wasVisible: Bool?
            while !Task.isCancelled {
                await self?.refreshUsage()
                var visible = isVisible()
                if let self, self.wakeGraceReads > 0 {
                    self.wakeGraceReads -= 1
                    visible = true
                }
                if let self, self.usageDrawable != visible { self.usageDrawable = visible }
                // Said when the clock changes, so the log shows which one runs.
                if visible != wasVisible {
                    Log.app.notice("cli-tools: process watch every \(visible ? "3" : "60", privacy: .public)s (a window is \(visible ? "on screen" : "not on screen", privacy: .public))")
                    wasVisible = visible
                }
                let interval = visible ? Self.processWatchVisibleInterval : Self.processWatchHiddenInterval
                let sleep = Task { _ = try? await Task.sleep(for: interval) }
                self?.processWatchSleep = sleep
                await sleep.value
            }
        }
    }

    /// Read now and go on at the clock that fits: a window just came on
    /// screen while the watch was in its 60 s hidden-window wait, which kept
    /// the 3 s clock from starting for up to a minute.
    func wakeProcessWatch() {
        wakeGraceReads = 3
        if let processWatchSleep { processWatchSleep.cancel() } else { Task { await refreshUsage() } }
    }

    /// One read of the process table for every install there is a binary to
    /// match (`CLIToolProcesses.target`): the checked installs, or before the
    /// first check the scan's.
    func refreshUsage() async {
        let statuses = checked ? self.statuses : []
        let sightings = checked ? [] : self.sightings
        guard !statuses.isEmpty || !sightings.isEmpty else { return }
        let found = await offCooperativePool(qos: .utility) { () -> [CLIToolID: CLIToolUsage] in
            let targets = statuses.compactMap { status in CLIToolProcesses.target(of: status).map { (status.toolID, $0) } }
                + sightings.compactMap { sighting in CLIToolProcesses.target(of: sighting).map { (sighting.toolID, $0) } }
            let usage = CLIToolProcesses.usage(of: targets.map(\.1))
            var answer: [CLIToolID: CLIToolUsage] = [:]
            for (id, target) in targets { if let found = usage[target], found.isRunning { answer[id] = found } }
            return answer
        }
        // A stale copy counts once the read before saw it too; a new one is
        // read again shortly rather than at the next tick.
        let readAt = now()
        var seen: [StaleProcess: Date] = [:]
        var confirmed: [CLIToolID: CLIToolUsage] = [:]
        var unconfirmed = false
        for (id, found) in found {
            for copy in found.stale {
                let key = StaleProcess(id: id, pid: copy.pid)
                seen[key] = staleSeen[key] ?? readAt
            }
            let kept = found.keepingStale {
                guard let first = seen[StaleProcess(id: id, pid: $0.pid)] else { return false }
                return readAt.timeIntervalSince(first) >= Self.staleConfirmSeconds
            }
            if kept.stale.count < found.stale.count { unconfirmed = true }
            if kept.isRunning { confirmed[id] = kept }
        }
        staleSeen = seen
        let shownStale = { (u: [CLIToolID: CLIToolUsage]) in
            u.filter { !$0.value.stale.isEmpty }.mapValues { $0.stale.map(\.pid) }
        }
        if shownStale(confirmed) != shownStale(usage) {
            let said = shownStale(confirmed).map { "\($0.key.kind.rawValue) \($0.value)" }.sorted().joined(separator: ", ")
            Log.app.notice("cli-tools: stale shown now: \(said.isEmpty ? "none" : said, privacy: .public)\(unconfirmed ? " (more to confirm)" : "", privacy: .public)")
        }
        if confirmed != usage { usage = confirmed }
        watchExits(of: Set(found.values.flatMap { $0.current + $0.stale.map(\.pid) }))
        announceStale()
        if unconfirmed {
            Task {
                try? await Task.sleep(for: Self.staleConfirmDelay)
                await self.refreshUsage()
            }
        }
    }

    /// Keep an exit watch on exactly `pids`. One that exits before its watch
    /// is armed is dropped by the next read on the clock.
    private func watchExits(of pids: Set<pid_t>) {
        for (pid, source) in exitWatches where !pids.contains(pid) {
            source.cancel()
            exitWatches[pid] = nil
        }
        for pid in pids where exitWatches[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.processExited(pid) }
            }
            exitWatches[pid] = source
            source.resume()
        }
    }

    private func processExited(_ pid: pid_t) {
        exitWatches.removeValue(forKey: pid)?.cancel()
        // Read now; the clock stays the one that fits (no wake grace).
        if let processWatchSleep { processWatchSleep.cancel() } else { Task { await refreshUsage() } }
    }

    private func announceStale() {
        var newly: [CLIToolStatus] = []
        var changed: [CLIToolStatus] = []
        var cleared: [CLIToolID] = []
        for id in announcedStale.keys where usage[id]?.stale.isEmpty ?? true {
            announcedStale[id] = nil
            bannerStale[id] = nil
            cleared.append(id)
        }
        for status in statuses {
            guard let stale = usage[status.toolID]?.stale, !stale.isEmpty else { continue }
            let pids = Set(stale.map(\.pid))
            let known = announcedStale[status.toolID] ?? []
            if !pids.isSubset(of: known) {
                newly.append(status)
            } else if pids != bannerStale[status.toolID] {
                changed.append(status)
            }
            announcedStale[status.toolID] = known.union(pids)
            bannerStale[status.toolID] = pids
        }
        guard !newly.isEmpty || !changed.isEmpty || !cleared.isEmpty else { return }
        onStaleProcesses?(newly, changed, cleared)
    }

    /// Read the release notes of every update row whose range is new, and keep
    /// the versions they mark breaking. A pass waits for the one before it, so
    /// two checks landing together read each document once: the later pass
    /// finds the range already read.
    func loadBreaking() async {
        let previous = breakingPass
        let pass = Task { await previous?.value; await self.readBreaking() }
        breakingPass = pass
        await pass.value
    }

    /// One pass of `loadBreaking`. Rows one after another; a document that fails
    /// is not asked again in the same pass and the row gets no hint — the next
    /// check tries again. A row whose range moved while its notes loaded is left
    /// to the pass that check started.
    private func readBreaking() async {
        let range = { (status: CLIToolStatus) in "\(status.installedVersion ?? "")|\(status.latestVersion ?? "")" }
        let reading = statuses.filter(CLIToolChangelog.readsForBreaking)
        // A hint read for another range — the copy was updated, or the channel
        // moved on — says nothing about this one.
        let ranges = Dictionary(reading.map { ($0.toolID, range($0)) }, uniquingKeysWith: { a, _ in a })
        for id in Set(breaking.keys).union(breakingRead.keys) where breakingRead[id] != ranges[id] {
            breaking[id] = nil
            breakingRead[id] = nil
        }
        var failed: Set<String> = []
        for status in reading where breakingRead[status.toolID] != range(status) {
            guard !failed.contains(status.releaseNotesKey) else { continue }
            let notes: Changelog
            do { notes = try await releaseNotes(for: status, force: false) } catch {
                failed.insert(status.releaseNotesKey)
                continue
            }
            let id = status.toolID
            guard let now = statuses.first(where: { $0.toolID == id }), range(now) == range(status),
                  CLIToolChangelog.readsForBreaking(now)
            else { continue }
            let versions = CLIToolChangelog.breakingVersions(
                in: notes, installed: status.installedVersion, latest: status.latestVersion)
            breaking[id] = versions.isEmpty ? nil : versions
            breakingRead[id] = range(status)
        }
    }

    /// Run the one-click update of the install `id` names, with its own tool's
    /// provider and no other, then re-check that tool.
    func update(_ id: CLIToolID) async {
        // Re-read here, not trusted from the click: the list may have been
        // re-checked since the row was drawn, and `offered` is what carries
        // every gate — auto-update on, nothing else updating. Not already
        // ours is the reducer's to say (`CLIRunEvent.clicked`).
        let clicked = offered.first { $0.toolID == id }
        let effects = send(.clicked(id, offered: clicked != nil,
                                    needsAdministrator: clicked?.needsAdministrator ?? false,
                                    queueBusy: runQueue.running != nil))
        // One that asks for an administrator password raises its panel now,
        // beside whatever the queue runs, not when its turn comes — minutes
        // later (`CLIRunReducer`).
        if effects.contains(.raisePanel(id)) {
            await runClaimed(id, needsAdministrator: true)
            release(id)
            return
        }
        guard effects.contains(.enqueue(id)) else { return }
        // Taken back while it waits, the row is released inside the Cancel
        // (`CLIRunQueue`). Held until the re-check below has landed, not just
        // until the command exits: that check waits on the network, and
        // releasing the row earlier shows the old "outdated" verdict with a
        // live Update button for its length.
        let ran = await runQueue.perform(.tool(id), whenCancelled: { self.release(id) }) {
            await self.runClaimed(id, needsAdministrator: false)
        }
        if ran { release(id) }
    }

    /// The update of a copy already claimed (`updating`), at its turn, then its
    /// tool's re-check. The caller releases it. `needsAdministrator` is what
    /// the click decided the copy's route on (`update`).
    private func runClaimed(_ id: CLIToolID, needsAdministrator: Bool) async {
        send(.turnCame(id))
        guard let status = await offerAtTurn(id, needsAdministrator: needsAdministrator), let provider = provider(of: status) else { return }
        // Cancelled before its command started: nothing ran, nothing to re-check.
        guard let outcome = await run(status, with: provider) else { return }
        if Self.needsRecheck(outcome) {
            send(.recheckStarted([id]))
            await check([provider])
        }
        settle(status, outcome)
    }

    /// `id`'s offer, read again at its turn (`CLIRunOffer.atTurn`): a check
    /// while it waited may have moved it, or taken it away. `outdated`, not
    /// `oneClickable`, which leaves out the copy this click has claimed.
    ///
    /// Taken away, and not by the GitHub pause, it is asked of its own tool
    /// once more before the click is given up (review, 2026-10-20). Still not
    /// offered, the row says so, and why (`CLIRunState.redLines`).
    ///
    /// Offered, but now asking for an administrator password where the click
    /// queued it as one that did not, or the reverse, it is not run: the click
    /// decided its route (`update`), and the panel raised at its turn would
    /// come minutes after the click (review, 2026-10-20, round 2). The row says to try again — "click Update" would not be
    /// true in the popover, whose Other tools row has only Update All.
    private func offerAtTurn(_ id: CLIToolID, needsAdministrator: Bool) async -> CLIToolStatus? {
        let index = providers.firstIndex(where: { $0.kind == id.kind })
        let read = { (asked: Bool) in
            CLIRunOffer.atTurn(
                offered: self.outdated.first { $0.toolID == id && $0.oneClick != nil },
                published: self.status(id),
                heldByPause: self.checkedStatuses.contains {
                    $0.toolID == id && $0.state == .updateAvailable && $0.oneClick != nil
                },
                asked: asked, needsAdministrator: needsAdministrator)
        }
        var offer = read(index == nil)
        if offer == .askTool, let index {
            if send(.offerRead(id, .askTool)).contains(.check(id)) { await check([index]) }
            offer = read(true)
        }
        switch offer {
        case .run, .askTool:
            break
        case .notRun(.routeChanged(let nowNeeds)):
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): not run at its turn, \(nowNeeds ? "now needs" : "no longer needs", privacy: .public) an administrator password")
        case .notRun:
            let now = status(id)
            let why = now.flatMap { now in now.withheld.map { Self.reason($0, of: now) } }
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): not run at its turn, no longer offered (\(now.map { "\($0.state)" } ?? "gone", privacy: .public)\(why.map { ": \($0)" } ?? "", privacy: .public))")
        }
        guard send(.offerRead(id, offer)).contains(.startCommand(id)), case .run(let status) = offer else { return nil }
        return status
    }

    /// A row's red line (`CLIRunState.redLines`), worded.
    private static func redLine(_ line: CLIRunRedLine) -> String {
        switch line {
        case .failed(let message): return message
        case .stillOn(let version): return String(localized: "Still \(version) after the update")
        case .versionUnreadable: return String(localized: "Couldn’t read the version after the update")
        // Never `.silent`: the reducer stores no line for it.
        case .notRun(let why): return notRunLine(why) ?? ""
        }
    }

    /// The row's line for a copy not run at its turn because its update now
    /// asks for an administrator password, or no longer does.
    private static func routeChangedLine(nowNeedsAdministrator: Bool) -> String {
        nowNeedsAdministrator
            ? String(localized: "Not updated: it now asks for an administrator password — try again")
            : String(localized: "Not updated: it no longer asks for an administrator password — try again")
    }

    /// What an Update All lane runs for `clicked` at its turn in the lane: the
    /// copy's offer as it stands now, not as it stood at the click — the turn
    /// can come minutes later, behind Homebrew or another click, and a check
    /// meanwhile may have moved the offer (npm's one-click pins
    /// `name@version`), held it back for the GitHub pause, or changed whether
    /// it asks for an administrator password. The read itself is
    /// `CLIRunOffer.laneAtTurn`'s, a pure function in Core; here it is logged.
    /// Not `.run`, the caller releases it.
    ///
    /// Read, not asked: no check here, unlike a single click's turn
    /// (`offerAtTurn`). One per copy would be a network round per copy, and in
    /// lanes running side by side a check can read another lane's copy of the
    /// same tool halfway through its install — why a tool is re-checked only
    /// once its last lane is done (`BatchRun.lanesLeft`).
    ///
    /// So a verdict that may clear by itself (`mayClearByItself`) falls back
    /// on the click's offer: "an update is already running" (`.busy`), which a
    /// check landing mid-batch gives every other copy in an npm prefix while
    /// the lane's own previous copy runs its npm there (real Mac, 2026-10-20),
    /// a channel or a version that could not be read. Dropped on those, Update
    /// All would skip the very copies it was clicked for. So does any verdict
    /// short of an offer from a check that started once this lane had run
    /// something (`readsTheLane`): the copies of a lane share what the update
    /// writes, and the one before can be the next one's updater — rustup ahead
    /// of its toolchains, whose trust rests on rustup's own file, bun ahead of
    /// its packages — so "not verified" read mid-install is about the batch,
    /// not the copy (review, 2026-10-21). A verdict from before the lane ran,
    /// a check while Update All waited its turn, is about the copy: broken,
    /// unverified, its runtime too old, the row says why it was not run.
    ///
    /// The fallback runs what the user clicked, as every lane did before; it
    /// does not re-read what the verdict hid. npm's and Claude Code's updaters
    /// look for a running update themselves and answer `.busy` without running
    /// anything (`NpmUpdater`, `ClaudeCodeUpdater`), and the trust-checking
    /// ones (rustup, boat, herdr, atuin) check the file again; a setting
    /// changed meanwhile behind a busy verdict is not seen. The pause still
    /// applies to it.
    ///
    /// The lanes never raise a panel: one whose route changed is not run, and
    /// its row says to try again, which at the click asks for it.
    private func laneOfferAtTurn(_ clicked: CLIToolStatus, readsTheLane: Bool) -> CLIRunOffer {
        let id = clicked.toolID
        let now = status(id)
        let checked = checkedStatuses.first { $0.toolID == id }
        let lane = CLIRunOffer.laneAtTurn(
            clicked: clicked, published: now, checked: checked, readsTheLane: readsTheLane,
            clickedNow: { clicked.applyingGitHubPause(gitHubPause, updatersGetOurToken: updatersGetOurToken, now: self.now()) })
        if lane.onClickedOffer {
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): Update All runs it on the offer clicked, its check\(readsTheLane ? " (made while its lane ran)" : "", privacy: .public) now says \(checked.flatMap(\.withheld).map { "\($0)" } ?? "-", privacy: .public)")
        }
        switch lane.offer {
        case .run(let turn):
            if turn != clicked {
                Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): Update All runs it as it stands at its turn (\(clicked.latestVersion ?? "-", privacy: .public) at the click, \(turn.latestVersion ?? "-", privacy: .public) now)")
            }
        case .notRun(.heldBack(let why)):
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): Update All did not run it at its turn, held back (\(why ?? "-", privacy: .public))")
        case .notRun(.routeChanged(let nowNeeds)):
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): Update All did not run it at its turn, \(nowNeeds ? "now needs" : "no longer needs", privacy: .public) an administrator password")
        case .notRun, .askTool:
            let why = now.flatMap { now in now.withheld.map { Self.reason($0, of: now) } }
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): Update All did not run it at its turn, no longer offered (\(now.map { "\($0.state)" } ?? "gone", privacy: .public)\(why.map { ": \($0)" } ?? "", privacy: .public))")
        }
        return lane.offer
    }

    /// What a copy's row says when it was not run at its turn; nil when it
    /// says nothing (`CLIRunNotRun.silent`).
    private static func notRunLine(_ why: CLIRunNotRun) -> String? {
        switch why {
        case .routeChanged(let nowNeeds):
            return routeChangedLine(nowNeedsAdministrator: nowNeeds)
        case .notOffered(let reason), .heldBack(let reason):
            return reason.map { String(localized: "Not updated: \($0)") }
                ?? String(localized: "Not updated: the update is no longer offered")
        case .silent:
            return nil
        }
    }

    /// The index in `providers` of `status`'s own tool, never another's: each
    /// provider's command is the one its vendor documents for its own installs.
    private func provider(of status: CLIToolStatus) -> Int? {
        providers.firstIndex { $0.kind == status.kind }
    }

    private func release(_ id: CLIToolID) {
        // Out of a running or waiting Update All for good, however its claim
        // ended — done, failed, cancelled queued or before its command: a click
        // of its own on this row later is not Update All's to cancel or release
        // (review, #1498, rounds 1 and 2): its claim goes, `byUpdateAll` with it.
        send(.released(id))
    }

    /// Apply `event` (`CLIRunReducer`), then perform its synchronous effects:
    /// a row's line, a Cancel's way through the queue or the registry, the
    /// confirmation window of an "Updated to X". The rest — a turn in the
    /// queue, a panel, a check, a command — are the caller's, which awaits them; they are
    /// returned for it to read. The state is set before any effect runs, so
    /// an event an effect sends in turn (a Cancel the queue answers inside
    /// `CLIRunQueue.cancel`) sees it.
    @discardableResult
    private func send(_ event: CLIRunEvent<CLIToolID>) -> [CLIRunEffect<CLIToolID>] {
        let (next, effects) = CLIRunReducer.reduce(runState, event)
        if next != runState { runState = next }
        for effect in effects { perform(effect) }
        return effects
    }

    private func perform(_ effect: CLIRunEffect<CLIToolID>) {
        switch effect {
        case .showLine(let id, let line):
            switch line {
            case .queued: setProgress(id, .queued, String(localized: "Queued"))
            case .starting: setProgress(id, .runningCommand(""), String(localized: "Starting…"))
            case .checking: setProgress(id, .checking, String(localized: "Checking…"))
            case .waitingToCheck: setProgress(id, .checking, String(localized: "Waiting to check"))
            case .output(let text): setProgress(id, .runningCommand(text), text)
            }
        case .clearLine(let id):
            progressLines.clear(id)
            progress[id] = nil
        case .startConfirmation(let id):
            startConfirmation(id)
        case .withdrawClick(let id):
            // Its own click, waiting behind another's run: out of the queue,
            // its row released by the click's `whenCancelled`.
            if runQueue.cancel(.tool(id)) {
                Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): cancelled while it waited its turn")
                return
            }
            let next = send(.notWaitingInQueue(id, updateAllWaiting: runQueue.isWaiting(.updateAllTools)))
            if !next.contains(.cancelJob(id)) {
                Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): cancelled before it started")
            }
        case .cancelJob(let id):
            send(.cancelAnswered(id, InstallJobs.cancel(Self.jobID(id))))
        case .cancelCopy(let id):
            cancel(id)
        case .withdrawUpdateAll:
            if runQueue.cancel(.updateAllTools) {
                Log.app.notice("Update All: cancelled while it waited its turn")
                return
            }
            if updatingAll {
                let cancellable = batchIDs.filter { cancels[$0] == .available }
                Log.app.notice("Update All: cancel, \(cancellable.count, privacy: .public) of \(self.batchIDs.count, privacy: .public) copies still cancellable")
            }
            send(.updateAllNotWaiting)
        case .cancelUpdateAll:
            cancelUpdateAll()
        // The caller's, awaited where it sent the event.
        case .enqueue, .raisePanel, .check, .startCommand, .stoppedBeforeCommand,
             .runUpdateAll, .enqueueUpdateAll, .readLaneOffer, .updateAllEnded:
            break
        }
    }

    /// A copy's Cancel. One `updateAll` has not reached leaves its lane at once;
    /// one running what comes before its command is cancelled through the
    /// registry (`InstallJobs.cancel`), which refuses once the command started —
    /// no error then (§5.8): the registry logs it, and the row says it is
    /// already finishing. Cancelled is not failed: no red line, no re-check.
    ///
    /// The order — the queue, then a copy not reached yet, then the registry —
    /// is `CLIRunReducer`'s (`cancelClicked`, `notWaitingInQueue`); the queue's
    /// and the registry's answers come back to it as events.
    func cancel(_ id: CLIToolID) {
        send(.cancelClicked(id))
    }

    /// The running update's line on its row: the line of the stage the row
    /// shows (`cancelRows`), or "Cancelling…" once that is due.
    func progressLine(_ id: CLIToolID) -> String? {
        if cancelRows.cancels[id] == .cancelling { return String(localized: "Cancelling…") }
        return stageLine(id)
    }

    /// The line of the stage `id`'s row shows (`cancelRows`), "Cancelling…"
    /// aside; nil while it has none.
    private func stageLine(_ id: CLIToolID) -> String? {
        // Read through `progress`, which is observed, rather than only
        // `progressLines`, which is not: a new line of the same stage —
        // "Waiting to check", then "Checking…" — redraws the row by itself
        // instead of on whatever else changes `cancelRows` with it.
        guard progress[id] != nil else { return nil }
        return progressLines.line(id, shown: cancelRows.stages[id])
    }

    /// `id`'s row now reads `text`, a line of `stage`.
    private func setProgress(_ id: CLIToolID, _ stage: InstallStage, _ text: String) {
        progressLines.record(id, stage: stage, text: text)
        progress[id] = text
    }

    private func smoothCancelRows() {
        let rows = cancelRowSmoothing.update(stages: progressLines.stages, cancels: cancels, now: .now)
        if rows != cancelRows { cancelRows = rows }
        cancelRowWake?.cancel()
        cancelRowWake = rows.nextWake.map { due in
            Task { @MainActor [weak self] in
                // cancel-ok: one-shot; a superseded wake is cancelled on purpose.
                try? await Task.sleep(until: due, clock: .continuous)
                guard !Task.isCancelled else { return }
                self?.smoothCancelRows()
            }
        }
    }

    /// The registry's id for a copy's update: apart from the app rows', whose
    /// ids are bundle paths.
    nonisolated static func jobID(_ id: CLIToolID) -> String {
        "cli-tool:\(id.kind.rawValue):\(id.path)"
    }

    /// The Cancel moves with the job: greyed once the command started, live
    /// again if it was refused and the tool may try again (`InstallJobs`).
    private func followPhase(_ id: CLIToolID) {
        send(.jobPhaseChanged(id, InstallJobs.phase(of: Self.jobID(id))))
    }

    /// The command alone, for a copy already in `updating`: its output goes to the
    /// row, a failure to the row and the log. What it means once the tool is
    /// re-checked is `settle`'s. Nil when its Cancel stopped it before the
    /// command started.
    private func run(_ status: CLIToolStatus, with provider: Int) async -> CLIToolUpdateOutcome? {
        let id = status.toolID
        // Clears its last red line and log: a retry (`CLIRunEvent.commandStarting`).
        send(.commandStarting(id))
        let update = providers[provider]
        // A job of its own (`InstallJobs.run`), so the row's Cancel reaches the
        // update before its command, and the command's `InstallCommit` greys it.
        let jobID = Self.jobID(id)
        let (outcome, cancelStopped) = await InstallJobs.run(jobID, phaseChanged: { [weak self] _ in
            Task { @MainActor in self?.followPhase(id) }
        }) { @MainActor [weak self] in
            let outcome = await RequestAttribution.withApp(Self.attributionID(status)) {
                await update.update(status) { [weak self] line in
                    Task { @MainActor in
                        // A line can arrive after the update has finished and its progress
                        // been cleared; writing it then would pin a stale line on the row.
                        // Nor over "Cancelling…", which holds until the row settles
                        // (`CLIRunEvent.outputLine`).
                        guard let self else { return }
                        self.send(.outputLine(id, line))
                    }
                }
            }
            // Asked while the job is still registered: it is forgotten when it ends.
            return (outcome, InstallJobs.cancelStoppedSomething(jobID))
        }
        // The job has ended, so a Cancel still live would find nothing and just
        // go away (review, 2026-10-20): one that ran nothing — `.busy`,
        // `.notOffered` — never committed, and kept it through the re-check
        // and, under `updateAll`, the other lanes' wait. Not offered from here.
        // Accepted, and it kept a command from starting — the first, or a retry
        // after a refused run (uv's, bun's, mise's rejected token): whatever the
        // provider made of the cancel — "could not start" — is no failure.
        // Otherwise one that needs its tool's re-check waits for it, said apart
        // from "Checking…": under `updateAll` the check can wait a while on the
        // tool's other lanes, and nothing is checking meanwhile.
        let ended = send(.commandEnded(id, needsRecheck: Self.needsRecheck(outcome), cancelStopped: cancelStopped))
        if ended.contains(.stoppedBeforeCommand(id)) {
            Log.app.notice("\(status.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): cancelled before its command started")
            return nil
        }
        // Accepted only after the command had run and failed, with nothing left
        // to start: the cancel stopped nothing, and the failure is the result.
        if cancels[id] == .cancelling {
            Log.app.notice("\(status.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): cancelled after its command had run; its result stands")
        }
        switch outcome {
        case .updated:
            break
        case .failed(let message, let output):
            Log.app.info("\(status.kind.rawValue, privacy: .public) update failed at \(id.path, privacy: .public): \(message, privacy: .public)")
            send(.commandFailed(id, message: message, log: output))
        case .busy, .notOffered:
            // Nothing ran. Something changed between the check and the click — an
            // update started elsewhere, or the offer went away — so the re-check
            // lets the row say what is true now.
            break
        case .declined:
            // The user dismissed the administrator panel: a decision, not a
            // failure, so no red line — the row goes back to its Update, as an
            // app's declined panel leaves no error (`AppListModel`).
            Log.app.notice("\(status.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): administrator panel dismissed, nothing ran")
        }
        return outcome
    }

    /// A failure is on the row already, and a dismissed panel ran nothing;
    /// anything else changed, or may have, what the tool's check says.
    nonisolated private static func needsRecheck(_ outcome: CLIToolUpdateOutcome) -> Bool {
        switch outcome {
        case .failed, .declined: return false
        case .updated, .busy, .notOffered: return true
        }
    }

    /// What a finished update says, once its tool's re-check has landed.
    private func settle(_ status: CLIToolStatus, _ outcome: CLIToolUpdateOutcome) {
        guard case .updated(let version) = outcome else { return }
        let id = status.toolID
        // Exit 0 is not proof of an update (`CLITools.settle`): the updater's
        // own re-read first, the fresh check's when it had none. "Updated to
        // X", or a red line saying it is still there, is the reducer's
        // (`CLIRunEvent.updateSettled`).
        let after = version ?? self.status(id)?.installedVersion
        if !send(.updateSettled(id, before: status.installedVersion, after: after)).contains(.startConfirmation(id)) {
            Log.app.info("\(status.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public) exited 0 but left \(after ?? "an unreadable version", privacy: .public)")
        }
    }

    /// Keep "Updated to X" for `confirmationWindow`, then let the row say what it
    /// says of any current copy. Re-entry restarts the window.
    private func startConfirmation(_ id: CLIToolID) {
        confirmationTimers[id]?.cancel()
        let window = confirmationWindow
        confirmationTimers[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: window)
            // A newer window owns the clearing.
            guard !Task.isCancelled, let self else { return }
            self.confirmationTimers[id] = nil
            self.send(.confirmationEnded(id))
        }
    }

    /// Update every install in `batchable` and `adminBatchable`, whatever its
    /// tool.
    ///
    /// First, at the click, each copy that asks for an administrator password,
    /// in row order: its panel is raised, and the next copy's only once this
    /// one's is answered, so the panels come one after another. Outside the
    /// queue, as a row's own click on one is (`update`); a dismissed panel drops
    /// that copy and the rest goes on.
    ///
    /// Then, at Update All's turn in the queue, the lanes (`lane(of:)`) at once,
    /// the copies of one lane one after another, and each tool re-checked once,
    /// as soon as the last lane holding any of its copies is done. With no lane
    /// copy left there is no turn to wait for.
    ///
    /// One copy at a time across every tool, as it was, took the sum of every
    /// installer — Junie's alone downloads ~330 MB — plus a re-check of every
    /// tool after each copy.
    func updateAll() async {
        let withProvider = { (statuses: [CLIToolStatus]) in
            statuses.compactMap { status in self.provider(of: status).map { (status, $0) } }
        }
        let batch = withProvider(batchable)
        let asking = withProvider(adminBatchable)
        // Already running, or nothing to start: the reducer's to say
        // (`CLIRunEvent.updateAllClicked`). Every copy is claimed now, "Queued".
        guard send(.updateAllClicked(lanes: batch.map(\.0.toolID), asking: asking.map(\.0.toolID)))
            .contains(.runUpdateAll) else { return }
        var rootRuns: [Task<Void, Never>] = []
        for (status, _) in asking {
            // Cancelled while it waited for the panel before its own — and
            // perhaps claimed again since by a click of its own.
            guard send(.panelTurnCame(status.toolID)).contains(.raisePanel(status.toolID)) else { continue }
            rootRuns.append(await startAsking(status.toolID))
        }
        // The lane copies still Update All's: one cancelled while the panels
        // were up is released, and a click of its own may have it now.
        var held: Set<CLIToolID> = []
        for case .enqueueUpdateAll(let ids) in send(.lanesReady(batch.map(\.0.toolID))) { held = Set(ids) }
        let lanes = batch.filter { held.contains($0.0.toolID) }
        var ended = false
        if !lanes.isEmpty {
            // Taken back while it waited (`cancelUpdateAll`): nothing of the
            // lanes ran, and every lane copy is released inside the Cancel
            // (`CLIRunEvent.updateAllWithdrawn`).
            _ = await runQueue.perform(.updateAllTools, whenCancelled: {
                if self.send(.updateAllWithdrawn).contains(.updateAllEnded) { ended = true }
            }) { await self.runBatch(lanes) }
        }
        for run in rootRuns { await run.value }
        if !ended { endUpdateAll() }
    }

    /// Start the update of `id`, claimed by `updateAll`, and return once its
    /// administrator panel has its answer (`CLIToolAdministratorPanel`) — or
    /// once its update has ended without raising one. The update goes on in
    /// the task returned.
    private func startAsking(_ id: CLIToolID) async -> Task<Void, Never> {
        let answered = PanelAnswer()
        let run = Task { @MainActor in
            await CLIToolAdministratorPanel.$answered.withValue({ answered.signal() }) {
                await self.runClaimed(id, needsAdministrator: true)
            }
            // Released; the last copy of an Update All still waiting its turn
            // — its lane copies cancelled while this one ran: nothing is left
            // for that turn to run (review, #1502 round 1).
            self.send(.panelRunEnded(id, updateAllWaiting: self.runQueue.isWaiting(.updateAllTools)))
            answered.signal()
        }
        await answered.wait()
        return run
    }

    /// One panel's answer, awaited once.
    @MainActor private final class PanelAnswer {
        private var done = false
        private var waiter: CheckedContinuation<Void, Never>?

        func signal() {
            guard !done else { return }
            done = true
            waiter?.resume()
            waiter = nil
        }

        func wait() async {
            guard !done else { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }

    /// Every copy it claimed has been released by now, so `batchIDs` is
    /// already empty.
    private func endUpdateAll() {
        send(.updateAllFinished)
    }

    /// Whether Update All is waiting behind another click's run.
    var updateAllWaiting: Bool { runQueue.isWaiting(.updateAllTools) }

    /// Update All's own Cancel, beside its progress in the workbench header:
    /// live while it waits its turn, or while any copy it claimed can still be
    /// cancelled; greyed once every one left has started its command, saying
    /// "Cancelling…" while a copy its click stopped is still being stopped —
    /// not "can't cancel now" right after a Cancel it took (review,
    /// 2026-10-20). Off the rows' smoothed Cancels, as the popover row's
    /// (`CLIRowSnapshot.updateAllCancel`), so the two change together. Nil when
    /// no Update All runs.
    var updateAllCancel: InstallRowSmoothing<CLIToolID>.GroupCancel? {
        rowSnapshot.updateAllCancel
    }

    /// Update All's Cancel: one still waiting its turn leaves the queue, and
    /// every copy it claimed goes back to its Update. One running cancels each
    /// copy that still can be (`cancel`), the rest finish.
    func cancelUpdateAll() {
        // The queue first, then each copy (`CLIRunEffect.withdrawUpdateAll`).
        send(.cancelUpdateAllClicked)
    }

    /// The popover row's Cancel: one for every copy the row says is updating,
    /// Update All's and a click's of its own alike (`groupCancel`), so a tool
    /// updated from the workbench can be stopped from there too (2026-10-20).
    /// Nil when nothing is left that the row could stop or grey. The row's
    /// head names the copies not queued: when only queued ones can still be
    /// stopped, its help says so.
    var rowCancel: InstallRowSmoothing<CLIToolID>.GroupCancel? {
        rowSnapshot.rowCancel
    }

    /// What every command-line tools surface draws from (`CLIRowSnapshot`):
    /// the popover's row and the workbench's Update All read whether a copy
    /// runs, and what its Cancel says, from here; a sidebar row and a detail
    /// header from `rowTool`, the same facts of their one copy.
    var rowSnapshot: CLIRowSnapshot<CLIToolID> {
        let listed = Set(statuses.map(\.toolID))
        return .live(
            tools: statuses.map { rowTool(id: $0.toolID, status: $0) },
            // Claimed, and gone from the last check's report: still running,
            // still the row's to count and to cancel.
            unlisted: updating.union(batchIDs).subtracting(listed)
                .sorted { $0.tag < $1.tag }.map { rowTool(id: $0, status: nil) },
            hasSightings: !sightings.isEmpty, checked: checked,
            updatingAll: updatingAll, updateAllWaiting: updateAllWaiting, batchIDs: batchIDs,
            updateAllOffered: updateAllOffered, updateAllStartable: updateAllStartable)
    }

    /// One copy's facts for its own sidebar row and detail header, as
    /// `rowSnapshot` holds them. Reads only what that copy's rows need: an
    /// idle copy reads `runState` and its status, error and confirmation —
    /// never `progress` or `cancelRows`, which change with every output line
    /// of any update. `runState` changes only when a copy is claimed, released
    /// or moves to its next phase, or its Cancel moves.
    func rowTool(_ status: CLIToolStatus) -> CLIRowSnapshot<CLIToolID>.Tool {
        rowTool(id: status.toolID, status: status)
    }

    /// The same for `id`, listed or not.
    func rowTool(_ id: CLIToolID) -> CLIRowSnapshot<CLIToolID>.Tool {
        rowTool(id: id, status: status(id))
    }

    private func rowTool(id: CLIToolID, status: CLIToolStatus?) -> CLIRowSnapshot<CLIToolID>.Tool {
        let phase = phase(id)
        let runs = phase != .idle
        return .live(
            id: id, kind: id.kind, phase: phase,
            cancel: runs ? cancelRows.cancels[id] : nil,
            cancelPending: runs && cancelRows.cancelPending.contains(id),
            line: runs ? stageLine(id) : nil,
            state: status?.state ?? .unknown, oneClick: status?.oneClick != nil,
            needsAdministrator: status?.needsAdministrator ?? false, withheld: status?.withheld,
            manualCommand: status.flatMap(CLIToolPresentation.manualCommand),
            hasLatestVersion: status?.latestVersion != nil,
            error: runState.redLines[id].map(Self.redLine), justUpdated: runState.justUpdated[id])
    }

    /// `id`'s phase, as its claim stores it (`CLIRunState.phase`). No longer inferred from a
    /// missing Cancel (`cancelRows`): that also drew a failed run about to be
    /// released, its Cancel already nil, as `.checkingAtTurn`. It draws the
    /// same as `.running` there — the two differ only in a live Cancel
    /// (`CLIRowSnapshot.Tool.countedCancel`), and the smoothing passes a nil
    /// one straight through (`InstallRowSmoothing.update`).
    private func phase(_ id: CLIToolID) -> CLIRunPhase {
        runState.phase(id)
    }

    /// The popover row's Cancel: Update All still waiting its turn leaves the
    /// queue, then each copy claimed that still can be is cancelled (`cancel`);
    /// those past their command finish.
    func cancelRow() {
        if updateAllWaiting { cancelUpdateAll() }
        let cancellable = updating.filter { cancels[$0] == .available }
        Log.app.notice("Other tools row: cancel, \(cancellable.count, privacy: .public) of \(self.updating.count, privacy: .public) copies still cancellable")
        for id in cancellable { cancel(id) }
    }

    /// `updateAll`'s turn: the lanes at once, each tool re-checked when its last
    /// lane is done.
    private func runBatch(_ batch: [(CLIToolStatus, Int)]) async {
        var lanes: [[(CLIToolStatus, Int)]] = []
        var laneOf: [String: Int] = [:]
        for copy in batch {
            let key = Self.lane(of: copy.0)
            if let index = laneOf[key] { lanes[index].append(copy) } else {
                laneOf[key] = lanes.count
                lanes.append([copy])
            }
        }
        let run = BatchRun()
        for lane in lanes {
            for provider in Set(lane.map(\.1)) { run.lanesLeft[provider, default: 0] += 1 }
        }
        // A task per lane, not a task group: Swift 6.4's Release build has
        // miscompiled a group's `for await` before (swift64-release-taskgroup-
        // miscompile), and these need nothing a group adds.
        let tasks = lanes.map { lane in Task { @MainActor in await self.runLane(lane, run) } }
        for task in tasks { await task.value }
    }

    /// What the lanes of one `updateAll` share.
    @MainActor private final class BatchRun {
        /// Per provider, the lanes not yet done that hold one of its copies.
        var lanesLeft: [Int: Int] = [:]
        /// Per provider, its copies whose update ran and wait on its re-check.
        var ran: [Int: [(CLIToolStatus, CLIToolUpdateOutcome)]] = [:]
        /// Per provider, its copies not run at their turn, as clicked, with
        /// why their row said they were not.
        var notRun: [Int: [(CLIToolStatus, CLIRunNotRun)]] = [:]
    }

    private func runLane(_ lane: [(CLIToolStatus, Int)], _ run: BatchRun) async {
        // The generation of the last check started before this lane ran
        // anything; a report newer than it may have read the lane's own work.
        var ranSince: Int?
        for (clicked, provider) in lane {
            // Cancelled while it waited: its row was released then — and may be
            // claimed again by a click of its own, whose "Queued" stays (#1535).
            guard send(.laneTurnCame(clicked.toolID)).contains(.readLaneOffer(clicked.toolID)) else { continue }
            // Its offer as it stands at its turn; not to run, it leaves the
            // batch as a copy cancelled before its command does.
            let readsTheLane = ranSince.map { reportGeneration[provider, default: 0] > $0 } ?? false
            let offer = laneOfferAtTurn(clicked, readsTheLane: readsTheLane)
            guard send(.offerRead(clicked.toolID, offer)).contains(.startCommand(clicked.toolID)),
                  case .run(let status) = offer else {
                if case .notRun(let why)? = runState.redLines[clicked.toolID] {
                    run.notRun[provider, default: []].append((clicked, why))
                }
                release(clicked.toolID)
                continue
            }
            if ranSince == nil { ranSince = refreshGeneration }
            guard let outcome = await self.run(status, with: provider) else {
                release(status.toolID)
                continue
            }
            if Self.needsRecheck(outcome) {
                run.ran[provider, default: []].append((status, outcome))
            } else {
                // A failure is said on the row; nothing to wait for.
                release(status.toolID)
            }
        }
        // A tool is re-checked once no lane is left that holds one of its copies:
        // earlier, its check could read a copy in the middle of its install.
        var ready: [Int] = []
        for provider in Set(lane.map(\.1)) {
            run.lanesLeft[provider, default: 1] -= 1
            if run.lanesLeft[provider] == 0, run.ran[provider] != nil { ready.append(provider) }
        }
        guard !ready.isEmpty else { return }
        for provider in ready {
            send(.recheckStarted((run.ran[provider] ?? []).map(\.0.toolID)))
        }
        await check(ready.sorted())
        for provider in ready {
            for (status, outcome) in run.ran[provider] ?? [] {
                settle(status, outcome)
                release(status.toolID)
            }
            // "Not updated: …" goes with its tool's next check, and this one
            // is the batch's own: said again while it still holds
            // (`CLIRunEvent.notRunRechecked`).
            for (clicked, why) in run.notRun[provider] ?? [] {
                send(.notRunRechecked(clicked.toolID, why, clickedNeedsAdministrator: clicked.needsAdministrator,
                                      now: status(clicked.toolID)))
            }
        }
    }

    /// Copies with the same lane must not update at once; copies in different
    /// lanes may.
    ///
    /// - An npm prefix is one lane, whatever put the package there: npm documents
    ///   no lock for a global install (`NpmActivity`), and its update refuses to
    ///   start while another npm runs in the prefix — Claude Code installed with
    ///   npm included.
    /// - bub is uv's lane: `bub update` runs uv, which `uv self update` replaces.
    /// - Every other tool is a lane of its own: its copies share its updater's
    ///   files (rustup and its toolchains, bun and the packages `bun add -g`
    ///   installed, pnpm's and Yarn's global packages, `claude update` and the
    ///   versions it keeps).
    nonisolated static func lane(of status: CLIToolStatus) -> String {
        switch status.detail {
        case .npm(let package) where package.install.bun == nil && package.install.global == nil:
            return "node:" + Self.canonical(package.install.prefix.path)
        case .claudeCode(let claude) where claude.install.method == .npm:
            if let prefix = claude.install.nodePrefix { return "node:" + Self.canonical(prefix) }
        default:
            break
        }
        return status.kind == .bub ? CLIToolKind.uv.rawValue : status.kind.rawValue
    }

    /// One spelling per directory, so two finders' paths to one prefix meet.
    nonisolated private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: - Release notes

    /// The release notes `status` reads, from its provider, kept for the session —
    /// unless the kept copy predates its `latestVersion`: the channel moved on since
    /// it was fetched, and the one section the reader most wants would be missing.
    func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        let key = status.releaseNotesKey
        if !force, let cached = releaseNotesCache[key],
           status.latestVersion.map({ latest in cached.entries.contains { $0.version == latest } }) ?? true {
            return cached
        }
        guard let provider = providers.first(where: { $0.kind == status.kind }) else { throw NoProvider() }
        let changelog = try await RequestAttribution.withApp(Self.attributionID(status)) {
            try await provider.releaseNotes(for: status, force: force)
        }
        releaseNotesCache[key] = changelog
        return changelog
    }

    /// What one install's requests are filed under in the request log
    /// (`CLITools.attributionID`).
    nonisolated static func attributionID(_ status: CLIToolStatus) -> String {
        CLITools.attributionID(status)
    }

    /// No provider answers for the kind asked about. Unreachable while every
    /// status comes from a provider; kept apart from the provider's own errors so
    /// it cannot read as a network failure or a format drift.
    struct NoProvider: Error {}

    // MARK: - Wording
    //
    // `CLIToolWording`'s, in DuoUpdaterCore since `duo` words the same rows;
    // kept under these names for the call sites. `nonisolated`:
    // `CLIToolPresentation` words the workbench rows with them off the model's
    // actor.

    nonisolated static func vendor(of kind: CLIToolKind) -> String? { CLIToolWording.vendor(of: kind) }

    nonisolated static func reason(_ withheld: CLIToolWithheld, of kind: CLIToolKind) -> String {
        CLIToolWording.reason(withheld, of: kind)
    }

    nonisolated static func reason(_ withheld: CLIToolWithheld, of status: CLIToolStatus) -> String {
        CLIToolWording.reason(withheld, of: status)
    }

    nonisolated static func requirement(_ gap: NpmPackage.RuntimeGap, of label: String) -> String {
        CLIToolWording.requirement(gap, of: label)
    }

    /// Which installer a Claude Code copy came from, as the summary names it:
    /// "native", "npm (node v24)". The installer names are the tools' own, so
    /// untranslated, like the formula names on the brew row.
    nonisolated static func label(_ install: ClaudeCodeInstall) -> String {
        switch install.method {
        case .native: return "native"
        case .npm:
            guard let prefix = install.nodePrefix else { return "npm" }
            let name = URL(fileURLWithPath: prefix).lastPathComponent
            // nvm names each prefix after its node version ("v24.11.0").
            if name.hasPrefix("v"), let major = name.dropFirst().split(separator: ".").first,
               major.allSatisfy(\.isNumber) {
                return "npm (node v\(major))"
            }
            if prefix == "/opt/homebrew" { return "npm (Homebrew)" }
            return "npm"
        case .pnpm: return "pnpm"
        case .bun: return "bun"
        case .unknown: return String(localized: "custom location")
        }
    }

    /// "Claude Code ×2 — native, npm (node v24) · fx": each tool once, in
    /// `CLIToolKind.allCases` order, with how many copies and — for Claude Code,
    /// whose copies differ by installer — which installers.
    nonisolated static func summary(_ statuses: [CLIToolStatus]) -> String {
        summary(statuses.map { status in
            guard case .claudeCode(let claudeCode) = status.detail else { return (status.kind, nil) }
            return (status.kind, label(claudeCode.install))
        })
    }

    /// The same line from the launch scan, before any check: the scan does not
    /// say which installer put a copy there, so it is counts alone —
    /// "Claude Code ×2 · fx".
    nonisolated static func summary(_ sightings: [CLIToolSighting]) -> String {
        summary(sightings.map { ($0.kind, nil) })
    }

    nonisolated private static func summary(_ copies: [(kind: CLIToolKind, label: String?)]) -> String {
        CLIToolKind.allCases.compactMap { kind in
            let mine = copies.filter { $0.kind == kind }
            guard !mine.isEmpty else { return nil }
            let count = mine.count > 1 ? " ×\(mine.count)" : ""
            let labels = mine.compactMap(\.label)
            return kind.displayName + count + (labels.isEmpty ? "" : " — " + labels.joined(separator: ", "))
        }.joined(separator: " · ")
    }
}
