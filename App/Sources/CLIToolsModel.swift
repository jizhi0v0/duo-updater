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
        // "Not updated: <reason>" said why a click's copy was not offered at its
        // turn. Offered again — also with no check of its tool, as when the
        // GitHub pause lifts — it would read as the reason beside a live Update
        // (review, #1511 round 2). Offered again only: one said beside an Update
        // that stayed (its update now asks for an administrator password) is
        // kept until its tool's next check.
        for id in notRunAtTurn where !wasOffered.contains(id)
            && statuses.contains(where: { $0.toolID == id && $0.oneClick != nil }) {
            notRunAtTurn.remove(id)
            errors[id] = nil
        }
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

    /// Installs DuoUpdater is updating right now, from the click until the re-check
    /// after it has landed — and, under `updateAll`, every copy it will update,
    /// from the start: a copy waiting its turn is claimed, as `installAll` claims
    /// an app row, so it shows "Queued" rather than a live Update.
    private(set) var updating: Set<CLIToolID> = []
    /// The copies `updateAll` has claimed whose turn has not come: the rest of
    /// their lane is still running.
    private(set) var queued: Set<CLIToolID> = []
    /// The copies whose update has run and whose tool's re-check has not landed:
    /// still claimed, so the old verdict's Update does not come back, but no
    /// longer running anything. Under `updateAll` the re-check waits for the
    /// tool's other lanes, so this can last as long as the slowest of them.
    private(set) var awaitingCheck: Set<CLIToolID> = []
    /// Every click in the CLI tab that changes something, Homebrew's included,
    /// run one at a time in the order made (`CLIRunQueue`). Here because the
    /// tools' runs are; `AppListModel` puts Homebrew's in the same one.
    let runQueue = CLIRunQueue<CLIRun>()
    /// True for the whole of `updateAll`, including the re-checks at the end of
    /// each tool's lanes, so the popover row stays in its updating state instead
    /// of flashing back to "Update" between two copies.
    private(set) var updatingAll = false
    /// The Cancel of each copy whose update DuoUpdater runs
    /// (`InstallCancelState`): live while it waits its turn under `updateAll`
    /// or runs what comes before its command, greyed once the command started
    /// (its `InstallCommit`). Cleared with the claim (`release`).
    private(set) var cancels: [CLIToolID: InstallCancelState] = [:] {
        didSet { smoothCancelRows() }
    }
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
    /// Copies cancelled while `updateAll` had them queued: their lane skips them.
    @ObservationIgnored private var cancelledWhileQueued: Set<CLIToolID> = []
    /// The copies the running (or waiting) `updateAll` claimed. Not observed:
    /// it changes only with `updatingAll`, which is.
    @ObservationIgnored private var batchIDs: Set<CLIToolID> = []
    /// The latest output line of each running update. Set through
    /// `setProgress`, which records its stage for the rows (`progressLine`).
    private(set) var progress: [CLIToolID: String] = [:] {
        didSet { smoothCancelRows() }
    }
    /// The last failed update of each install: the row's one line. Also an update
    /// that exited 0 but left the version where it was.
    private(set) var errors: [CLIToolID: String] = [:]
    /// The full output of each failed update: the detail pane's log.
    private(set) var errorLogs: [CLIToolID: String] = [:]
    /// The copies whose `errors` line says a click was not run at its turn
    /// (`offerAtTurn`): about that click only, so gone once a later check of
    /// its tool lands, whatever it says.
    @ObservationIgnored private var notRunAtTurn: Set<CLIToolID> = []
    /// Installs just updated → the version they now read as. Open sessions keep
    /// the old version until restarted, so the row says so.
    ///
    /// A confirmation, not a state: each entry clears itself after
    /// `confirmationWindow`, as an app row's "Updated ✓" does
    /// (`AppListModel.markJustUpdated`). Kept until something changed the copy, it
    /// pinned "Claude Code updated to 2.1.285" on the popover for good — the first
    /// thing the user saw after a real update on 2026-10-01.
    private(set) var justUpdated: [CLIToolID: String] = [:]
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
    /// worth a re-check on the next open. The others (a dev-channel fx, a copy not
    /// signed by its vendor, an editable bub, a broken venv) stay until the scan
    /// sees the disk change — a new version, or a new `CLIToolSighting.state`
    /// for one repaired in place — which `moved` already catches; re-checking them on
    /// every open re-ran every tool's network check for nothing (found in
    /// review, 2026-10-01).
    ///
    /// The three later reasons are disk changes too. `.staged` ends when Junie
    /// applies its update at a launch — a new build and no `pending-update.json`,
    /// both in its sighting. `.unverified` ends with another file or a lifted
    /// quarantine flag: uv's hash verdict, rustup's sha256, an npm prefix's node
    /// signature and quarantine are all in theirs. `.runtimeTooOld` ends with
    /// another node in the prefix (its sighting) or a new release, which the
    /// report's age covers as for any verdict — and it comes with a verdict,
    /// `.updateAvailable`, so it is never among `unchecked` anyway.
    nonisolated static func mayClearByItself(_ status: CLIToolStatus) -> Bool {
        switch status.withheld {
        // A rate limit ends when GitHub's hour does, as `channelUnreadable` did
        // for it before it had a case of its own.
        case nil, .channelUnreadable, .rateLimited, .busy, .versionUnreadable: return true
        case .staged, .unverified, .runtimeTooOld: return false
        default: return false
        }
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
        // An error describes an attempt at an update that is still on offer. Once
        // the copy is no longer behind — updated from a terminal, or gone — it
        // would otherwise sit beside a current install in the workbench. Nor once
        // nothing is offered: openclaw's own update reported a failed check after
        // installing the newest release its node runs (2026-10-02), and the row
        // went on showing that failure where it should say the next release
        // needs a newer Node. Not "Not updated: <reason>", whose copy is not on
        // offer by its nature: it waits for its own tool's check, below — any
        // tool's check took it away (review, 2026-10-20, round 2).
        for id in errors.keys where byID[id]?.state != .updateAvailable || byID[id]?.oneClick == nil {
            if notRunAtTurn.contains(id), !answered.contains(id.kind) { continue }
            errors[id] = nil
            errorLogs[id] = nil
        }
        // "Not updated: <reason>" was true when the click's turn came. Kept by
        // the rule above once its tool is offered again, it read as the reason
        // beside a live Update on every later check (review, #1511 round 1).
        for id in notRunAtTurn where answered.contains(id.kind) {
            notRunAtTurn.remove(id)
            errors[id] = nil
        }
        // "Updated to X" is about the copy as DuoUpdater left it. Something else
        // has changed it since (or it is gone) — the claim no longer holds.
        for (id, version) in justUpdated {
            if byID[id]?.installedVersion != version { justUpdated[id] = nil }
        }
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
        // re-checked since the row was drawn, and `oneClickable` is what carries
        // every gate — auto-update on, nothing else updating, not already ours.
        guard let clicked = oneClickable.first(where: { $0.toolID == id }) else { return }
        updating.insert(id)
        cancels[id] = .available
        // One that asks for an administrator password raises its panel now,
        // beside whatever the queue runs, not when its turn comes — minutes
        // later, holding the whole app until answered. Nothing to clash with:
        // the root shell runs under `env -i` with the system `PATH` and writes
        // only its tool's file (`CLIToolAdministratorRun`); the queue is there
        // for Homebrew against the tools.
        if clicked.needsAdministrator {
            await runClaimed(id, needsAdministrator: true)
            release(id)
            return
        }
        // Behind another click's run, it waits its turn claimed, as a copy
        // under `updateAll` does: "Queued", with its Cancel live. Taken back
        // while it waits, the row is released inside the Cancel (`CLIRunQueue`).
        if runQueue.running != nil {
            queued.insert(id)
            setProgress(id, .queued, String(localized: "Queued"))
        }
        // Held until the re-check below has landed, not just until the command
        // exits: that check waits on the network, and releasing the row earlier
        // shows the old "outdated" verdict with a live Update button for its length.
        let ran = await runQueue.perform(.tool(id), whenCancelled: { self.release(id) }) {
            await self.runClaimed(id, needsAdministrator: false)
        }
        if ran { release(id) }
    }

    /// The update of a copy already claimed (`updating`), at its turn, then its
    /// tool's re-check. The caller releases it. `needsAdministrator` is what
    /// the click decided the copy's route on (`update`).
    private func runClaimed(_ id: CLIToolID, needsAdministrator: Bool) async {
        queued.remove(id)
        guard let status = await offerAtTurn(id, needsAdministrator: needsAdministrator), let provider = provider(of: status) else { return }
        // Cancelled before its command started: nothing ran, nothing to re-check.
        guard let outcome = await run(status, with: provider) else { return }
        if Self.needsRecheck(outcome) {
            setProgress(id, .checking, String(localized: "Checking…"))
            await check([provider])
        }
        settle(status, outcome)
    }

    /// `id`'s offer, read again at its turn: a check while it waited may have
    /// moved it, or taken it away. `outdated`, not `oneClickable`, which leaves
    /// out the copy this click has claimed.
    ///
    /// Taken away, it is asked of its own tool once more before the click is
    /// given up. Checks are not held off while an update runs, and one then can
    /// read the run ahead of it — its npm child in the prefix both share, "npm
    /// is busy" — or leave the copy unanswered; that run re-checks its own tool
    /// only, so the click went away at its turn with nothing run and nothing
    /// said (review, 2026-10-20). Still not offered, the row says so, and why.
    ///
    /// Held back only by the GitHub pause (`gitHubPause`), it is not asked
    /// again: its check would be refused by the same closed budget, and that
    /// answer — no verdict — would replace the "update available" the pause
    /// holds back, so the Update would not come back when the pause lifts
    /// (review, 2026-10-20, round 2).
    ///
    /// Offered, but now asking for an administrator password where the click
    /// queued it as one that did not, or the reverse, it is not run: the click
    /// decided its route (`update`), and the panel raised at its turn would
    /// come minutes after the click, holding the app (review, 2026-10-20,
    /// round 2). The row says to click again.
    private func offerAtTurn(_ id: CLIToolID, needsAdministrator: Bool) async -> CLIToolStatus? {
        let offer = { self.outdated.first { $0.toolID == id && $0.oneClick != nil } }
        var offered = offer()
        let heldByPause = offered == nil
            && checkedStatuses.contains { $0.toolID == id && $0.state == .updateAvailable && $0.oneClick != nil }
        if offered == nil, !heldByPause, let index = providers.firstIndex(where: { $0.kind == id.kind }) {
            // Nothing to cancel while it is asked: the update starts after.
            cancels[id] = nil
            setProgress(id, .checking, String(localized: "Checking…"))
            await check([index])
            offered = offer()
            if offered != nil { cancels[id] = .available }
        }
        if let offered {
            guard offered.needsAdministrator != needsAdministrator else { return offered }
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): not run at its turn, \(offered.needsAdministrator ? "now needs" : "no longer needs", privacy: .public) an administrator password")
            notRunAtTurn.insert(id)
            errors[id] = offered.needsAdministrator
                ? String(localized: "Not updated: it now asks for an administrator password — click Update again")
                : String(localized: "Not updated: it no longer asks for an administrator password — click Update again")
            return nil
        }
        let now = status(id)
        let why = now.flatMap { now in now.withheld.map { Self.reason($0, of: now) } }
        Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): not run at its turn, no longer offered (\(now.map { "\($0.state)" } ?? "gone", privacy: .public)\(why.map { ": \($0)" } ?? "", privacy: .public))")
        // Updated from a terminal meanwhile, or gone: the row says that by itself.
        if let now, now.state == .updateAvailable || now.state == .unknown {
            notRunAtTurn.insert(id)
            errors[id] = why.map { String(localized: "Not updated: \($0)") }
                ?? String(localized: "Not updated: the update is no longer offered")
        }
        return nil
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
        // (review, #1498, rounds 1 and 2).
        batchIDs.remove(id)
        updating.remove(id)
        queued.remove(id)
        awaitingCheck.remove(id)
        progressLines.clear(id)
        progress[id] = nil
        cancels[id] = nil
    }

    /// A copy's Cancel. One `updateAll` has not reached leaves its lane at once;
    /// one running what comes before its command is cancelled through the
    /// registry (`InstallJobs.cancel`), which refuses once the command started —
    /// no error then (§5.8): the registry logs it, and the row says it is
    /// already finishing. Cancelled is not failed: no red line, no re-check.
    func cancel(_ id: CLIToolID) {
        guard cancels[id] == .available else { return }
        // Its own click, waiting behind another's run: out of the queue, its
        // row released by the click's `whenCancelled`.
        if runQueue.cancel(.tool(id)) {
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): cancelled while it waited its turn")
            return
        }
        if queued.contains(id) {
            cancelledWhileQueued.insert(id)
            Log.app.notice("\(id.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public): cancelled before it started")
            release(id)
            // The last copy of an Update All still waiting its turn: nothing is
            // left for it to run.
            if runQueue.isWaiting(.updateAllTools), batchIDs.isEmpty { cancelUpdateAll() }
            return
        }
        cancels[id] = InstallCancelState.after(InstallJobs.cancel(Self.jobID(id)))
    }

    /// The running update's line on its row: the line of the stage the row
    /// shows (`cancelRows`), or "Cancelling…" once that is due.
    func progressLine(_ id: CLIToolID) -> String? {
        if cancelRows.cancels[id] == .cancelling { return String(localized: "Cancelling…") }
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
        guard let state = cancels[id] else { return }
        cancels[id] = state.following(InstallJobs.phase(of: Self.jobID(id)))
    }

    /// The command alone, for a copy already in `updating`: its output goes to the
    /// row, a failure to the row and the log. What it means once the tool is
    /// re-checked is `settle`'s. Nil when its Cancel stopped it before the
    /// command started.
    private func run(_ status: CLIToolStatus, with provider: Int) async -> CLIToolUpdateOutcome? {
        let id = status.toolID
        errors[id] = nil
        errorLogs[id] = nil
        notRunAtTurn.remove(id)
        setProgress(id, .runningCommand(""), String(localized: "Starting…"))
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
                        // Nor over "Cancelling…", which holds until the row settles.
                        guard let self, self.updating.contains(id), self.cancels[id] != .cancelling else { return }
                        self.setProgress(id, .runningCommand(line), line)
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
        if cancels[id] == .available { cancels[id] = nil }
        // Accepted, and it kept a command from starting — the first, or a retry
        // after a refused run (uv's, bun's, mise's rejected token): whatever the
        // provider made of the cancel — "could not start" — is no failure.
        if cancels[id] == .cancelling, cancelStopped {
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
            errors[id] = message
            errorLogs[id] = output
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
        if Self.needsRecheck(outcome) {
            awaitingCheck.insert(id)
            // Said apart from "Checking…": under `updateAll` the check can wait a
            // while on the tool's other lanes, and nothing is checking meanwhile.
            setProgress(id, .checking, String(localized: "Waiting to check"))
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
        // own re-read first, the fresh check's when it had none.
        let after = version ?? self.status(id)?.installedVersion
        if case .updated(let after) = CLITools.settle(before: status.installedVersion, after: after) {
            confirmUpdate(id, version: after)
        } else {
            Log.app.info("\(status.kind.rawValue, privacy: .public) update at \(id.path, privacy: .public) exited 0 but left \(after ?? "an unreadable version", privacy: .public)")
            // Brew's "brew update finished, but Homebrew is still X" rule: a
            // run that changed nothing reads as a failure, not as silence.
            errors[id] = after.map { String(localized: "Still \($0) after the update") }
                ?? String(localized: "Couldn’t read the version after the update")
        }
    }

    /// Show "Updated to X" for `confirmationWindow`, then let the row say what it
    /// says of any current copy. Re-entry restarts the window.
    private func confirmUpdate(_ id: CLIToolID, version: String) {
        justUpdated[id] = version
        confirmationTimers[id]?.cancel()
        let window = confirmationWindow
        confirmationTimers[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: window)
            // A newer window owns the clearing.
            guard !Task.isCancelled, let self else { return }
            self.confirmationTimers[id] = nil
            self.justUpdated[id] = nil
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
        guard !updatingAll else { return }
        let withProvider = { (statuses: [CLIToolStatus]) in
            statuses.compactMap { status in self.provider(of: status).map { (status, $0) } }
        }
        let batch = withProvider(batchable)
        let asking = withProvider(adminBatchable)
        guard !batch.isEmpty || !asking.isEmpty else { return }
        updatingAll = true
        batchIDs = Set((batch + asking).map(\.0.toolID))
        // Every copy is claimed now, not when its turn comes: until then its row
        // says "Queued" instead of offering an Update that would race its lane.
        // That holds while Update All itself waits behind another click's run,
        // and for a copy whose panel waits on the one before it.
        for (status, _) in batch + asking {
            updating.insert(status.toolID)
            queued.insert(status.toolID)
            cancels[status.toolID] = .available
            setProgress(status.toolID, .queued, String(localized: "Queued"))
        }
        var rootRuns: [Task<Void, Never>] = []
        for (status, _) in asking {
            // Cancelled while it waited for the panel before its own.
            if cancelledWhileQueued.remove(status.toolID) != nil { continue }
            rootRuns.append(await startAsking(status.toolID))
        }
        // The lane copies still Update All's: one cancelled while the panels
        // were up is released, and a click of its own may have it now.
        for (status, _) in batch where !batchIDs.contains(status.toolID) {
            cancelledWhileQueued.remove(status.toolID)
        }
        let lanes = batch.filter { batchIDs.contains($0.0.toolID) }
        var ended = false
        if !lanes.isEmpty {
            // Taken back while it waited (`cancelUpdateAll`): nothing of the
            // lanes ran, and every lane copy is released inside the Cancel.
            _ = await runQueue.perform(.updateAllTools, whenCancelled: {
                // The batch's copies as they stand, not as clicked: one cancelled
                // out of it and clicked again waits as a click of its own, and is
                // left to that click.
                for id in self.batchIDs where self.queued.contains(id) { self.release(id) }
                for (status, _) in lanes { self.cancelledWhileQueued.remove(status.toolID) }
                // Over at once unless a copy behind a panel still runs.
                if self.batchIDs.isEmpty {
                    self.endUpdateAll()
                    ended = true
                }
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
            self.release(id)
            // The last copy of an Update All still waiting its turn — its lane
            // copies cancelled while this one ran: nothing is left for that
            // turn to run (review, #1502 round 1).
            if self.runQueue.isWaiting(.updateAllTools), self.batchIDs.isEmpty { self.cancelUpdateAll() }
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

    private func endUpdateAll() {
        updatingAll = false
        batchIDs = []
    }

    /// Whether Update All is waiting behind another click's run.
    var updateAllWaiting: Bool { runQueue.isWaiting(.updateAllTools) }

    /// Update All's own Cancel, beside its progress in the workbench header and
    /// the popover row: live while it waits its turn, or while any copy it
    /// claimed can still be cancelled (`cancels`); greyed once every one left
    /// has started its command, saying "Cancelling…" while a copy its click
    /// stopped is still being stopped — not "can't cancel now" right after a
    /// Cancel it took (review, 2026-10-20). Nil when no Update All runs.
    var updateAllCancel: InstallCancelState? {
        guard updatingAll else { return nil }
        if updateAllWaiting { return .available }
        if batchIDs.contains(where: { cancels[$0] == .available }) { return .available }
        return batchIDs.contains { cancels[$0] == .cancelling } ? .cancelling : .committing
    }

    /// Update All's Cancel: one still waiting its turn leaves the queue, and
    /// every copy it claimed goes back to its Update. One running cancels each
    /// copy that still can be (`cancel`), the rest finish.
    func cancelUpdateAll() {
        if runQueue.cancel(.updateAllTools) {
            Log.app.notice("Update All: cancelled while it waited its turn")
            return
        }
        guard updatingAll else { return }
        let cancellable = batchIDs.filter { cancels[$0] == .available }
        Log.app.notice("Update All: cancel, \(cancellable.count, privacy: .public) of \(self.batchIDs.count, privacy: .public) copies still cancellable")
        for id in cancellable { cancel(id) }
    }

    /// The popover row's Cancel: one for every copy the row says is updating,
    /// Update All's and a click's of its own alike (`groupCancel`), so a tool
    /// updated from the workbench can be stopped from there too (2026-10-20).
    /// Nil when nothing is left that the row could stop or grey. The row's
    /// head names the copies not queued: when only queued ones can still be
    /// stopped, its help says so.
    var rowCancel: InstallRowSmoothing<CLIToolID>.GroupCancel? {
        cancelRows.groupCancel(of: updating, running: updating.subtracting(queued))
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
    }

    private func runLane(_ lane: [(CLIToolStatus, Int)], _ run: BatchRun) async {
        for (status, provider) in lane {
            // Cancelled while it waited: its row was released then — and may be
            // claimed again by a click of its own, whose "Queued" stays.
            if cancelledWhileQueued.remove(status.toolID) != nil { continue }
            queued.remove(status.toolID)
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
            for (status, _) in run.ran[provider] ?? [] {
                setProgress(status.toolID, .checking, String(localized: "Checking…"))
            }
        }
        await check(ready.sorted())
        for provider in ready {
            for (status, outcome) in run.ran[provider] ?? [] {
                settle(status, outcome)
                release(status.toolID)
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
