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
    /// (`checked`).
    private(set) var statuses: [CLIToolStatus] = []
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
    /// True for the whole of `updateAll`, including the re-checks at the end of
    /// each tool's lanes, so the popover row stays in its updating state instead
    /// of flashing back to "Update" between two copies.
    private(set) var updatingAll = false
    /// The latest output line of each running update.
    private(set) var progress: [CLIToolID: String] = [:]
    /// The last failed update of each install: the row's one line. Also an update
    /// that exited 0 but left the version where it was.
    private(set) var errors: [CLIToolID: String] = [:]
    /// The full output of each failed update: the detail pane's log.
    private(set) var errorLogs: [CLIToolID: String] = [:]
    /// Installs just updated → the version they now read as. Open sessions keep
    /// the old version until restarted, so the row says so.
    ///
    /// A confirmation, not a state: each entry clears itself after
    /// `confirmationWindow`, as an app row's "Updated ✓" does
    /// (`AppListModel.markJustUpdated`). Kept until something changed the copy, it
    /// pinned "Claude Code updated to 2.1.285" on the popover for good — the first
    /// thing the user saw after a real update on 2026-10-01.
    private(set) var justUpdated: [CLIToolID: String] = [:]

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

    /// When the report on screen was taken; nil until a check has completed.
    @ObservationIgnored private var lastChecked: Date?
    /// How old a report may get before an open of the popover checks again.
    static let recheckInterval: TimeInterval = 15 * 60

    /// Bumped by every check; a check applies a tool's report only if it is still
    /// the latest one started for that tool (`latestCheck`). Reads overlap — a
    /// popover open can start one, and each update ends with one — and a check
    /// started before an update finished must not land after the re-check that
    /// follows it and put the stale "outdated" verdict back.
    /// `refreshBrewFormulae`'s rule, per tool: an update re-checks only its own.
    @ObservationIgnored private var refreshGeneration = 0
    /// Per provider (by index in `providers`), the generation of the latest check
    /// started that asks it.
    @ObservationIgnored private var latestCheck: [Int: Int] = [:]
    /// Per provider, the report on screen.
    @ObservationIgnored private var reports: [Int: CLIToolReport] = [:]
    /// Checks started and not yet returned; `checking` while any is out.
    @ObservationIgnored private var checksInFlight = 0

    /// Each document's whole release notes, fetched once and kept for the session:
    /// every install's pane reads the same document (Claude Code's is ~860 KB, 407
    /// sections on 2026-09-30), so switching between installs should not fetch and
    /// parse it again. By `CLIToolStatus.releaseNotesKey`, since a tool can have
    /// several (rustup's and Rust's; one per npm package).
    @ObservationIgnored private var releaseNotesCache: [String: Changelog] = [:]

    init(
        providers: [any CLIToolProvider] = [
            ClaudeCodeProvider(), BubProvider(), FxProvider(), UvProvider(), JunieProvider(), RustProvider(), NpmProvider(),
            BoatProvider(), CodexProvider(), BunProvider(), OpencodeProvider(), CursorAgentProvider(), AmpProvider(),
        ],
        now: @escaping @Sendable () -> Date = { Date() },
        confirmationWindow: Duration = .seconds(2)
    ) {
        let order = CLIToolKind.allCases
        self.providers = providers.enumerated().sorted {
            let (a, b) = (order.firstIndex(of: $0.element.kind)!, order.firstIndex(of: $1.element.kind)!)
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
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

    /// What an open of the popover does: a local scan, and the networked check
    /// only when the report on screen may be wrong — the app list's rule (a full
    /// check on the first open, a local rescan on later ones) applied here. Checks
    /// when there is no completed report yet, when it is older than
    /// `recheckInterval`, when the scan disagrees with it (a copy of any tool
    /// appeared or went, or its version moved — a `claude update` in a terminal),
    /// or when it left a copy unanswered. An update re-checks by itself and does
    /// not go through here.
    ///
    /// One decision for every tool, because one check covers every tool
    /// (`refresh`): a reason to re-check any of them re-checks all.
    func refreshOnOpen() async {
        guard let lastChecked else { return await refresh() }
        let found = await scanAll()
        let stale = now().timeIntervalSince(lastChecked) >= Self.recheckInterval
        // What the scan can see change without a check: which copies of which
        // tool there are, the version each one reads as, and the rest of what its
        // verdict rests on (`CLIToolSighting.state`) — held against what the last
        // check's own scan saw, built by the same rule.
        let moved = Set(found) != Set(checkedSightings)
        guard stale || moved || unchecked.contains(where: Self.mayClearByItself) else { return }
        await refresh()
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
        case nil, .channelUnreadable, .busy, .versionUnreadable: return true
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
        checksInFlight += 1
        checking = true
        let answers = await inProviderOrder(indices) { await $0.check() }
        checksInFlight -= 1
        checking = checksInFlight > 0
        let current = answers.filter { latestCheck[$0.0] == generation }
        guard !current.isEmpty else { return }
        apply(current, whole: indices.count == providers.count)
    }

    private func scanAll() async -> [CLIToolSighting] {
        await inProviderOrder(Array(providers.indices)) { await $0.scan() }.flatMap { $0.1 }
    }

    /// `work` run on the providers at `indices` at once, each answer with its
    /// provider's index, in `providers` order.
    private func inProviderOrder<T: Sendable>(
        _ indices: [Int], _ work: @escaping @Sendable (any CLIToolProvider) async -> T
    ) async -> [(Int, T)] {
        await withTaskGroup(of: (Int, T).self) { group in
            for index in indices {
                let provider = providers[index]
                group.addTask { (index, await work(provider)) }
            }
            var answers: [(Int, T)] = []
            for await answer in group { answers.append(answer) }
            return answers.sorted { $0.0 < $1.0 }
        }
    }

    /// Put `answers` on screen in place of their providers' last reports. `whole`:
    /// the check asked every provider, so the report as a whole is that recent.
    private func apply(_ answers: [(Int, CLIToolReport)], whole: Bool) {
        for (index, report) in answers { reports[index] = report }
        let ordered = reports.keys.sorted().compactMap { reports[$0] }
        contexts = Dictionary(ordered.map { ($0.kind, $0.context) }, uniquingKeysWith: { a, _ in a })
        statuses = ordered.flatMap(\.statuses)
        checkedSightings = ordered.flatMap(\.sightings)
        sightings = checkedSightings
        checked = true
        // A one-tool re-check leaves the others' verdicts as old as they were:
        // only a check of all of them restarts the clock `refreshOnOpen` reads.
        if whole { lastChecked = now() }
        let byID = Dictionary(statuses.map { ($0.toolID, $0) }, uniquingKeysWith: { a, _ in a })
        // An error describes an attempt at an update that is still on offer. Once
        // the copy is no longer behind — updated from a terminal, or gone — it
        // would otherwise sit beside a current install in the workbench. Nor once
        // nothing is offered: openclaw's own update reported a failed check after
        // installing the newest release its node runs (2026-10-02), and the row
        // went on showing that failure where it should say the next release
        // needs a newer Node.
        for id in errors.keys where byID[id]?.state != .updateAvailable || byID[id]?.oneClick == nil {
            errors[id] = nil
            errorLogs[id] = nil
        }
        // "Updated to X" is about the copy as DuoUpdater left it. Something else
        // has changed it since (or it is gone) — the claim no longer holds.
        for (id, version) in justUpdated {
            if byID[id]?.installedVersion != version { justUpdated[id] = nil }
        }
    }

    /// Run the one-click update of the install `id` names, with its own tool's
    /// provider and no other, then re-check that tool.
    func update(_ id: CLIToolID) async {
        // Re-read here, not trusted from the click: the list may have been
        // re-checked since the row was drawn, and `oneClickable` is what carries
        // every gate — auto-update on, nothing else updating, not already ours.
        guard let status = oneClickable.first(where: { $0.toolID == id }),
              let provider = provider(of: status)
        else { return }
        updating.insert(id)
        // Held until the re-check below has landed, not just until the command
        // exits: that check waits on the network, and releasing the row earlier
        // shows the old "outdated" verdict with a live Update button for its length.
        defer { release(id) }
        let outcome = await run(status, with: provider)
        if Self.needsRecheck(outcome) {
            progress[id] = String(localized: "Checking…")
            await check([provider])
        }
        settle(status, outcome)
    }

    /// The index in `providers` of `status`'s own tool, never another's: each
    /// provider's command is the one its vendor documents for its own installs.
    private func provider(of status: CLIToolStatus) -> Int? {
        providers.firstIndex { $0.kind == status.kind }
    }

    private func release(_ id: CLIToolID) {
        updating.remove(id)
        queued.remove(id)
        awaitingCheck.remove(id)
        progress[id] = nil
    }

    /// The command alone, for a copy already in `updating`: its output goes to the
    /// row, a failure to the row and the log. What it means once the tool is
    /// re-checked is `settle`'s.
    private func run(_ status: CLIToolStatus, with provider: Int) async -> CLIToolUpdateOutcome {
        let id = status.toolID
        errors[id] = nil
        errorLogs[id] = nil
        progress[id] = String(localized: "Starting…")
        let outcome = await providers[provider].update(status) { [weak self] line in
            Task { @MainActor in
                // A line can arrive after the update has finished and its progress
                // been cleared; writing it then would pin a stale line on the row.
                guard let self, self.updating.contains(id) else { return }
                self.progress[id] = line
            }
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
        }
        if Self.needsRecheck(outcome) {
            awaitingCheck.insert(id)
            // Said apart from "Checking…": under `updateAll` the check can wait a
            // while on the tool's other lanes, and nothing is checking meanwhile.
            progress[id] = String(localized: "Waiting to check")
        }
        return outcome
    }

    /// A failure is on the row already; anything else changed, or may have, what
    /// the tool's check says.
    nonisolated private static func needsRecheck(_ outcome: CLIToolUpdateOutcome) -> Bool {
        if case .failed = outcome { return false }
        return true
    }

    /// What a finished update says, once its tool's re-check has landed.
    private func settle(_ status: CLIToolStatus, _ outcome: CLIToolUpdateOutcome) {
        guard case .updated(let version) = outcome else { return }
        let id = status.toolID
        // Exit 0 is not proof of an update: measured, `claude update` exits 0
        // having stayed put ("… predates release-signature enforcement; staying
        // on X"), and the updater then reports the version it left. Only a
        // version other than the one clicked on counts — the updater's own
        // re-read first, the fresh check's when it had none.
        let before = status.installedVersion
        let after = version ?? self.status(id)?.installedVersion
        if let after, after != before {
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

    /// Update every install in `oneClickable`, whatever its tool: the lanes
    /// (`lane(of:)`) at once, the copies of one lane one after another, and each
    /// tool re-checked once, as soon as the last lane holding any of its copies
    /// is done.
    ///
    /// One copy at a time across every tool, as it was, took the sum of every
    /// installer — Junie's alone downloads ~330 MB — plus a re-check of every
    /// tool after each copy.
    func updateAll() async {
        guard !updatingAll else { return }
        let batch = oneClickable.compactMap { status in provider(of: status).map { (status, $0) } }
        guard !batch.isEmpty else { return }
        updatingAll = true
        defer { updatingAll = false }
        // Every copy is claimed now, not when its turn comes: until then its row
        // says "Queued" instead of offering an Update that would race its lane.
        for (status, _) in batch {
            updating.insert(status.toolID)
            queued.insert(status.toolID)
            progress[status.toolID] = String(localized: "Queued")
        }
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
            queued.remove(status.toolID)
            let outcome = await self.run(status, with: provider)
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
            for (status, _) in run.ran[provider] ?? [] { progress[status.toolID] = String(localized: "Checking…") }
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
    ///   installed, `claude update` and the versions it keeps).
    nonisolated static func lane(of status: CLIToolStatus) -> String {
        switch status.detail {
        case .npm(let package) where package.install.bun == nil:
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
        let changelog = try await provider.releaseNotes(for: status, force: force)
        releaseNotesCache[key] = changelog
        return changelog
    }

    /// No provider answers for the kind asked about. Unreachable while every
    /// status comes from a provider; kept apart from the provider's own errors so
    /// it cannot read as a network failure or a format drift.
    struct NoProvider: Error {}

    // MARK: - Wording
    //
    // Pure functions of their arguments, so `nonisolated`: `CLIToolPresentation`
    // words the workbench rows with them off the model's actor.

    /// Who signs `kind`'s releases, as `wrongSigner` names them; nil for a tool
    /// whose releases carry no signature to check (bub, a Python package).
    ///
    /// uv's builds from 0.12.12 carry the certificate of "OpenAI OpCo, LLC"
    /// (`UvInstall`); the short reason still names Astral, whose tool it is, and
    /// the detail pane's signature fact says who signed it. rustup is only ever
    /// ad hoc or unsigned — trusted by its published sha256 — and an npm
    /// package by the registry's integrity hash. Boat is only ever ad hoc, and
    /// trusted by its release's `SHA256SUMS`. Codex is signed by OpenAI OpCo, LLC —
    /// the certificate uv's builds carry too, here under its own vendor's name.
    nonisolated static func vendor(of kind: CLIToolKind) -> String? {
        switch kind {
        case .claudeCode: return "Anthropic"
        case .fx: return "Vercel"
        case .uv: return "Astral"
        case .junie: return "JetBrains"
        case .codex: return "OpenAI"
        case .bun: return "Oven"
        case .opencode: return "Anomaly"
        case .cursorAgent: return "Anysphere"
        case .amp: return "Amp Frontier"
        case .bub, .rust, .npm, .boat: return nil
        }
    }

    /// Why an install has no one-click, in the user's terms rather than the gate's.
    nonisolated static func reason(_ withheld: CLIToolWithheld, of kind: CLIToolKind) -> String {
        let tool = kind.displayName
        switch withheld {
        case .autoUpdateOff:
            return String(localized: "Auto-update is off in \(tool)’s settings")
        case .updatesDisabled:
            return String(localized: "Updates are turned off in \(tool)’s settings")
        case .busy:
            return String(localized: "\(tool) is already being updated")
        case .versionMismatch:
            return String(localized: "Can’t confirm which version is installed")
        case .unsupportedInstaller:
            return String(localized: "No one-click update for this kind of install")
        case .noOwnNpm:
            return String(localized: "Can’t tell which npm installed it")
        case .updaterMissing:
            // Today only bub's: `bub update` runs uv, which the GUI may not find.
            return kind == .bub
                ? String(localized: "bub updates with uv, and uv wasn’t found")
                : String(localized: "The program that updates it wasn’t found")
        case .broken:
            return String(localized: "An install is broken")
        case .channelUnsigned:
            guard let vendor = vendor(of: kind) else {
                return String(localized: "Builds on this channel aren’t signed by its developer")
            }
            return String(localized: "Builds on this channel aren’t signed by \(vendor)")
        case .unverified:
            switch kind {
            case .rust:
                // The rustup row's; a toolchain's is worded from its status.
                return String(localized: "Not a published rustup build")
            case .npm:
                // What is run is the prefix's node: trusted when the Node.js
                // Foundation signed it or a Homebrew keg installed it
                // (`NpmRuntime.nodeIsTrusted`). A quarantined one is worded from
                // its status.
                return String(localized: "Its node is neither Node.js’s nor Homebrew’s")
            default:
                guard let vendor = vendor(of: kind) else {
                    return String(localized: "Not the build its developer published")
                }
                return String(localized: "Not the build \(vendor) published")
            }
        case .runtimeTooOld:
            return String(localized: "Needs a newer Node")
        case .staged:
            return String(localized: "\(tool) installs its downloaded update at its next launch")
        case .projectIncomplete:
            return String(localized: "\(tool)’s project doesn’t list \(tool)")
        case .wrongSigner:
            guard let vendor = vendor(of: kind) else {
                return String(localized: "Not signed by its developer")
            }
            return String(localized: "Not signed by \(vendor)")
        case .versionUnreadable:
            return String(localized: "Couldn’t read the installed version")
        case .channelUnreadable:
            return String(localized: "Couldn’t reach \(tool)’s release channel")
        }
    }

    /// Why `status` has no one-click, with what its own tool's payload adds: the
    /// version Junie staged, the Node a newer npm release needs, which row of the
    /// Rust group, where an npm package came from. Every other case is the
    /// tool-wide wording above.
    nonisolated static func reason(_ withheld: CLIToolWithheld, of status: CLIToolStatus) -> String {
        let quarantined = String(localized: "Quarantined, so not run")
        switch (withheld, status.detail) {
        case (.staged, .junie(let junie)):
            if let pending = junie.pendingUpdate {
                return String(localized: "Junie installs the downloaded \(pending) at its next launch")
            }
        case (.runtimeTooOld, .npm(let package)):
            if let gap = package.gap { return requirement(gap, of: "\(package.install.name) \(gap.version)") }
        case (.unverified, .rust(let item)):
            switch item.kind {
            // A rustup whose hash did match carries its version: only the
            // quarantine flag held it back (`RustCheck.rustupStatus`).
            case .rustup where item.version != nil: return quarantined
            case .rustup: break
            // Its rustup matched nothing published, is broken or quarantined —
            // the rustup row says which.
            case .toolchain: return String(localized: "Its rustup isn’t verified")
            }
        // A package of bun's global install: bun installs it, and its node is the
        // one found on disk (`NpmCheck.bunGate`).
        case (.unverified, .npm(let package)) where package.install.bun?.quarantined == true:
            return String(localized: "Its bun is quarantined, so not run")
        case (.wrongSigner, .npm(let package)) where package.install.bun != nil:
            let vendor = "Oven"
            return String(localized: "Its bun isn’t signed by \(vendor)")
        case (.versionUnreadable, .npm(let package)) where package.install.bun != nil && package.install.runtime.node == nil:
            return String(localized: "No node found to check its engines against")
        case (.busy, .npm(let package)) where package.install.bun != nil:
            return String(localized: "bun is already changing its global packages")
        case (.unverified, .npm(let package)) where package.install.runtime.nodeQuarantined:
            return String(localized: "Its node is quarantined, so not run")
        case (.wrongSigner, .npm):
            return String(localized: "Its node isn’t signed by the Node.js Foundation")
        case (.versionUnreadable, .uv(let uv)) where uv.quarantined:
            return quarantined
        case (.unverified, .boat(let boat)) where boat.quarantined:
            return quarantined
        case (.unverified, .codex(let codex)) where codex.quarantined:
            return quarantined
        case (.unverified, .bun(let bun)) where bun.quarantined:
            return quarantined
        case (.unsupportedInstaller, .bun):
            // A canary: `bun upgrade` installs the newest canary, with no version.
            return String(localized: "A canary build, which has no version to compare")
        // Which part of Codex's standalone install is missing, rather than "An
        // install is broken": seen on 2026-10-06, `current` was a directory left
        // by a removed Codex.app, and the codex on PATH was Homebrew's, unharmed.
        case (.broken, .codex(let codex)) where codex.problem == .noCurrent:
            return String(localized: "Its standalone install has no current release")
        case (.broken, .codex(let codex)) where codex.problem == .binaryMissing:
            let version = codex.version ?? "?"
            return String(localized: "Codex \(version) is missing its program file")
        case (.autoUpdateOff, .codex):
            // Codex has no auto-update to turn off: its `check_for_update_on_startup`
            // is the prompt, set false "only if your Codex updates are centrally managed".
            return String(localized: "Codex’s update check is off in its config")
        case (.updaterMissing, .rust):
            return String(localized: "No rustup in ~/.cargo/bin")
        case (.autoUpdateOff, .rust):
            // Only the rustup row: its `auto_self_update`.
            let rustup = "rustup"
            return String(localized: "Auto-update is off in \(rustup)’s settings")
        case (.autoUpdateOff, .npm(let package)):
            // openclaw's own `update.auto.enabled`.
            return String(localized: "Auto-update is off in \(package.install.name)’s settings")
        case (.busy, .rust):
            // One gate for every Rust row (`RustActivity`).
            return String(localized: "rustup is already running")
        case (.busy, .npm):
            // Attributed by the node running it (`NpmActivity`): any package of
            // the prefix, or the package's own updater, which runs npm too.
            return String(localized: "npm is busy in this prefix")
        case (.unsupportedInstaller, .uv(let uv)):
            switch uv.layout {
            case .link: return String(localized: "A uv tool or pipx link")
            case .unreceipted: return String(localized: "Not the copy uv’s installer recorded")
            case .standalone: break
            }
        case (.unsupportedInstaller, .junie(let junie)):
            // Only `experimental` today: release, eap and nightly have installers.
            if let channel = junie.channel { return String(localized: "The \(channel) channel has no installer") }
        case (.unsupportedInstaller, .npm(let package)):
            return origin(of: package)
        case (.unsupportedInstaller, .boat):
            // Its config's `api_url` names another server than boat.dev.
            return String(localized: "Boat’s config points at another server")
        case (.unsupportedInstaller, .codex):
            // `~/.local/bin/codex` is not the standalone install's launcher.
            let launcher = "~/.local/bin/codex"
            return String(localized: "\(launcher) isn’t this install’s launcher")
        default:
            break
        }
        return reason(withheld, of: status.kind)
    }

    /// Where an npm package that is only reported came from, in `NpmCheck`'s
    /// order. The registry's two answers — no such package, no such version —
    /// leave nothing in the payload apart, and both mean the same thing here.
    nonisolated private static func origin(of package: NpmPackage) -> String {
        let install = package.install
        if install.linkTarget != nil {
            return String(localized: "Linked to a local folder")
        }
        if let manifest = install.manifestName, manifest != install.name {
            return String(localized: "Installed as an alias of \(manifest)")
        }
        if install.customRegistry != nil {
            return String(localized: "From a registry other than npm’s")
        }
        if case .openclaw(let settings) = install.ownUpdate, settings.effectiveChannel == "dev" {
            return String(localized: "openclaw is on its dev channel")
        }
        return String(localized: "Not a release from the npm registry")
    }

    /// "openclaw 2026.9.7 needs Node ≥ 24.16.0": what a newer npm release asks of
    /// the runtime, `label` naming the release. The lowest Node above the
    /// prefix's when the range has one; else the range as written, or npm's.
    nonisolated static func requirement(_ gap: NpmPackage.RuntimeGap, of label: String) -> String {
        if let minimum = gap.minimumNode { return String(localized: "\(label) needs Node ≥ \(minimum)") }
        if let node = gap.node { return String(localized: "\(label) needs Node \(node)") }
        if let npm = gap.npm { return String(localized: "\(label) needs npm \(npm)") }
        return String(localized: "\(label) needs a newer Node")
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
