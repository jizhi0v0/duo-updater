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

    /// Installs DuoUpdater is updating right now.
    private(set) var updating: Set<CLIToolID> = []
    /// True for the whole of `updateAll`, including the re-checks between
    /// installs, so the popover row stays in its updating state instead of
    /// flashing back to "Update" between two copies.
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

    /// When the report on screen was taken; nil until a check has completed.
    @ObservationIgnored private var lastChecked: Date?
    /// How old a report may get before an open of the popover checks again.
    static let recheckInterval: TimeInterval = 15 * 60

    /// Bumped by every `refresh`; a check applies its reports only if it is still
    /// the latest one started. Reads overlap — a popover open can start one, and
    /// each update ends with one — and a check started before an update finished
    /// must not land after the re-check that follows it and put the stale
    /// "outdated" verdict back. `refreshBrewFormulae`'s rule.
    @ObservationIgnored private var refreshGeneration = 0

    /// Each tool's whole release notes, fetched once and kept for the session:
    /// every install's pane reads the same document (Claude Code's is ~860 KB, 407
    /// sections on 2026-09-30), so switching between installs should not fetch and
    /// parse it again. By kind, since each tool has its own.
    @ObservationIgnored private var releaseNotesCache: [CLIToolKind: Changelog] = [:]

    init(
        providers: [any CLIToolProvider] = [ClaudeCodeProvider(), BubProvider(), FxProvider()],
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
        // tool there are, and the version each one reads as.
        let moved = Set(found) != Set(statuses.map {
            CLIToolSighting(kind: $0.kind, path: $0.path, version: $0.installedVersion)
        })
        guard stale || moved || !unchecked.isEmpty else { return }
        await refresh()
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
        refreshGeneration += 1
        let generation = refreshGeneration
        checking = true
        let reports = await checkAll()
        guard generation == refreshGeneration else { return }
        checking = false
        apply(reports)
    }

    private func checkAll() async -> [CLIToolReport] {
        await inProviderOrder { await $0.check() }
    }

    private func scanAll() async -> [CLIToolSighting] {
        await inProviderOrder { await $0.scan() }.flatMap { $0 }
    }

    /// `work` run on every provider at once, the answers in `providers` order.
    private func inProviderOrder<T: Sendable>(
        _ work: @escaping @Sendable (any CLIToolProvider) async -> T
    ) async -> [T] {
        await withTaskGroup(of: (Int, T).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await work(provider)) }
            }
            var answers: [(Int, T)] = []
            for await answer in group { answers.append(answer) }
            return answers.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func apply(_ reports: [CLIToolReport]) {
        contexts = Dictionary(reports.map { ($0.kind, $0.context) }, uniquingKeysWith: { a, _ in a })
        statuses = reports.flatMap(\.statuses)
        sightings = statuses.map { CLIToolSighting(kind: $0.kind, path: $0.path, version: $0.installedVersion) }
        checked = true
        lastChecked = now()
        let byID = Dictionary(statuses.map { ($0.toolID, $0) }, uniquingKeysWith: { a, _ in a })
        // An error describes an attempt at an update that is still on offer. Once
        // the copy is no longer behind — updated from a terminal, or gone — it
        // would otherwise sit beside a current install in the workbench.
        for id in errors.keys where byID[id]?.state != .updateAvailable {
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
    /// provider and no other.
    func update(_ id: CLIToolID) async {
        // Re-read here, not trusted from the click: the list may have been
        // re-checked since the row was drawn, and `oneClickable` is what carries
        // every gate — auto-update on, nothing else updating, not already ours.
        guard let status = oneClickable.first(where: { $0.toolID == id }),
              // The status's own tool, never another's: each provider's command is
              // the one its vendor documents for its own installs.
              let provider = providers.first(where: { $0.kind == status.kind })
        else { return }
        updating.insert(id)
        errors[id] = nil
        errorLogs[id] = nil
        progress[id] = String(localized: "Starting…")
        // Held until the re-check below has landed, not just until the command
        // exits: that check waits on the network, and releasing the row earlier
        // shows the old "outdated" verdict with a live Update button for its length.
        defer {
            updating.remove(id)
            progress[id] = nil
        }
        let outcome = await provider.update(status) { [weak self] line in
            Task { @MainActor in
                // A line can arrive after the update has finished and its progress
                // been cleared; writing it then would pin a stale line on the row.
                guard let self, self.updating.contains(id) else { return }
                self.progress[id] = line
            }
        }
        let tool = status.kind.rawValue
        switch outcome {
        case .updated(let version):
            progress[id] = String(localized: "Checking…")
            await refresh()
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
                Log.app.info("\(tool, privacy: .public) update at \(id.path, privacy: .public) exited 0 but left \(after ?? "an unreadable version", privacy: .public)")
                // Brew's "brew update finished, but Homebrew is still X" rule: a
                // run that changed nothing reads as a failure, not as silence.
                errors[id] = after.map { String(localized: "Still \($0) after the update") }
                    ?? String(localized: "Couldn’t read the version after the update")
            }
        case .failed(let message, let output):
            Log.app.info("\(tool, privacy: .public) update failed at \(id.path, privacy: .public): \(message, privacy: .public)")
            errors[id] = message
            errorLogs[id] = output
        case .busy, .notOffered:
            // Nothing ran. Something changed between the check and the click — an
            // update started elsewhere, or the offer went away — so re-check and let
            // the row say what is true now.
            await refresh()
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

    /// Update every install in `oneClickable`, whatever its tool, one after another.
    ///
    /// One at a time, not in parallel: two npm prefixes could run side by side,
    /// but every update ends in a re-check of every tool's copies, and the row
    /// reads one live line.
    func updateAll() async {
        guard !updatingAll else { return }
        updatingAll = true
        defer { updatingAll = false }
        for id in oneClickable.map(\.toolID) {
            // Each update ends in a re-check, which can withdraw the offer for the
            // rest (auto-update switched off meanwhile); `update` re-reads it.
            await update(id)
        }
    }

    // MARK: - Release notes

    /// `kind`'s whole release notes from its provider, kept for the session —
    /// unless the kept copy predates `latest`: the channel moved on since it was
    /// fetched, and the one section the reader most wants would be missing.
    func releaseNotes(of kind: CLIToolKind, covering latest: String?, force: Bool) async throws -> Changelog {
        if !force, let cached = releaseNotesCache[kind],
           latest.map({ latest in cached.entries.contains { $0.version == latest } }) ?? true {
            return cached
        }
        guard let provider = providers.first(where: { $0.kind == kind }) else { throw NoProvider() }
        let changelog = try await provider.releaseNotes(force: force)
        releaseNotesCache[kind] = changelog
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
    nonisolated static func vendor(of kind: CLIToolKind) -> String? {
        switch kind {
        case .claudeCode: return "Anthropic"
        case .fx: return "Vercel"
        case .bub: return nil
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
