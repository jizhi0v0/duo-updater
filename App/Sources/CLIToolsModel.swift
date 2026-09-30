import Foundation
import Observation
import DuoUpdaterCore

/// Command-line tools that are not Homebrew's — today Claude Code — as the
/// popover's "command-line tools" row and the workbench CLI tab show them.
///
/// Its own model rather than more of `AppListModel`: each tool has its own rules
/// (Claude Code's channel and auto-update switch live in Claude Code's settings,
/// not ours), and a later tool adds a group here without touching the app list.
///
/// Free of SwiftUI and of `AppListModel` on purpose: the app test target compiles
/// this file on its own and drives it with an injected check and updater, so no
/// test reaches the network or runs an installer.
@MainActor
@Observable
final class CLIToolsModel {

    /// One full check: scan, settings, process table, channel. The seam tests use.
    typealias Check = @Sendable () async -> ClaudeCodeReport
    /// The local half of a check alone — no network. See `scanInstalls`.
    typealias Scan = @Sendable () async -> [ClaudeCodeInstall]
    /// Runs a status's one-click update, forwarding each output line.
    typealias Update = @Sendable (
        ClaudeCodeStatus, _ progress: @escaping @Sendable (String) -> Void
    ) async -> ClaudeCodeUpdater.Outcome

    /// Every Claude Code install found, with its verdict. Empty until the first
    /// check returns (`checked`).
    private(set) var claudeCode: [ClaudeCodeStatus] = []
    /// The settings those verdicts were made under — channel, auto-update.
    private(set) var claudeCodeSettings = ClaudeCodeSettings()
    /// Flips true once the first check returns.
    private(set) var checked = false
    /// A check is in flight.
    private(set) var checking = false

    /// Every install the last look found — the local scan's answer until the first
    /// check lands, the check's own installs after. Known long before the verdicts
    /// (the scan is local; the check waits on the network), which is what lets the
    /// popover reserve its row before the check lands, like `brewInstalled` does
    /// for the brew row.
    private(set) var claudeCodeInstalls: [ClaudeCodeInstall] = []

    /// Install paths (`ClaudeCodeInstall.path`) DuoUpdater is updating right now.
    private(set) var updating: Set<String> = []
    /// True for the whole of `updateAll`, including the re-checks between
    /// installs, so the popover row stays in its updating state instead of
    /// flashing back to "Update" between two copies.
    private(set) var updatingAll = false
    /// The latest output line of each running update, by install path.
    private(set) var progress: [String: String] = [:]
    /// The last failed update of each install, by path: the row's one line. Also
    /// an update that exited 0 but left the version where it was.
    private(set) var errors: [String: String] = [:]
    /// The full output of each failed update, by path: the detail pane's log.
    private(set) var errorLogs: [String: String] = [:]
    /// Installs just updated, by path → the version they now read as. Open
    /// sessions keep the old version until restarted, so the row says so.
    ///
    /// A confirmation, not a state: each entry clears itself after
    /// `confirmationWindow`, as an app row's "Updated ✓" does
    /// (`AppListModel.markJustUpdated`). Kept until something changed the copy, it
    /// pinned "Claude Code updated to 2.1.285" on the popover for good — the first
    /// thing the user saw after a real update on 2026-10-01.
    private(set) var justUpdated: [String: String] = [:]

    /// Installs with an update on their own channel.
    var outdated: [ClaudeCodeStatus] { claudeCode.filter { $0.state == .updateAvailable } }
    /// The outdated installs one click may update: every gate passed and
    /// DuoUpdater is not already updating it.
    var oneClickable: [ClaudeCodeStatus] {
        outdated.filter { $0.oneClick != nil && !updating.contains($0.install.path) }
    }
    /// Whether this Mac has anything for the CLI surface to show at all.
    var hasAnything: Bool { !claudeCode.isEmpty }

    /// Installs whose check gave no verdict — broken, not Anthropic's, version
    /// unreadable, or the channel unreachable. While any is here the row must not
    /// claim "up to date", the same rule the brew row keeps for unchecked packages.
    var unchecked: [ClaudeCodeStatus] { claudeCode.filter { $0.state == .unknown } }

    @ObservationIgnored private let check: Check
    @ObservationIgnored private let scan: Scan
    @ObservationIgnored private let runUpdate: Update
    /// The clock `refreshOnOpen` measures a report's age by. Injected so the
    /// interval can be tested without waiting it out.
    @ObservationIgnored private let now: @Sendable () -> Date
    /// How long an "Updated to X" confirmation stays. Injected so tests can end it
    /// without waiting.
    @ObservationIgnored private let confirmationWindow: Duration
    /// The running confirmation window per path, so a second update restarts it.
    @ObservationIgnored private var confirmationTimers: [String: Task<Void, Never>] = [:]

    /// When the report on screen was taken; nil until a check has completed.
    @ObservationIgnored private var lastChecked: Date?
    /// How old a report may get before an open of the popover checks again.
    static let recheckInterval: TimeInterval = 15 * 60

    /// Bumped by every `refresh`; a check applies its report only if it is still
    /// the latest one started. Reads overlap — a popover open can start one, and
    /// each update ends with one — and a check started before an update finished
    /// must not land after the re-check that follows it and put the stale
    /// "outdated" verdict back. `refreshBrewFormulae`'s rule.
    @ObservationIgnored private var refreshGeneration = 0

    init(
        check: @escaping Check = { await ClaudeCodeReport.check() },
        scan: @escaping Scan = { await offCooperativePool { ClaudeCodeScanner().scan() } },
        update: @escaping Update = { await ClaudeCodeUpdater().update($0, progress: $1) },
        now: @escaping @Sendable () -> Date = { Date() },
        confirmationWindow: Duration = .seconds(2)
    ) {
        self.check = check
        self.scan = scan
        self.runUpdate = update
        self.now = now
        self.confirmationWindow = confirmationWindow
    }

    /// Find the installs without checking them — local and network-free — so the
    /// row's space is known before any check. Run once at launch; a check that has
    /// already landed is newer and wins, so this never overwrites it.
    func scanInstalls() async {
        let installs = await scan()
        guard !checked else { return }
        claudeCodeInstalls = installs
    }

    /// What an open of the popover does: a local scan, and the networked check
    /// only when the report on screen may be wrong — the app list's rule (a full
    /// check on the first open, a local rescan on later ones) applied here. Checks
    /// when there is no completed report yet, when it is older than
    /// `recheckInterval`, when the scan disagrees with it (a copy appeared or went,
    /// or its version moved — a `claude update` in a terminal), or when it left a
    /// copy unanswered. An update re-checks by itself and does not go through here.
    func refreshOnOpen() async {
        guard let lastChecked else { return await refresh() }
        let installs = await scan()
        let stale = now().timeIntervalSince(lastChecked) >= Self.recheckInterval
        let moved = Self.identity(installs) != Self.identity(claudeCode.map(\.install))
        guard stale || moved || !unchecked.isEmpty else { return }
        await refresh()
    }

    /// What the scan can see change without a check: which copies there are, and
    /// the version each one's layout names.
    private static func identity(_ installs: [ClaudeCodeInstall]) -> Set<String> {
        Set(installs.map { "\($0.path)\u{0}\($0.version ?? "")" })
    }

    /// Re-scan and re-check every tool.
    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        checking = true
        let report = await check()
        guard generation == refreshGeneration else { return }
        checking = false
        apply(report)
    }

    private func apply(_ report: ClaudeCodeReport) {
        claudeCodeSettings = report.settings
        claudeCode = report.statuses
        claudeCodeInstalls = report.statuses.map(\.install)
        checked = true
        lastChecked = now()
        let byPath = Dictionary(report.statuses.map { ($0.install.path, $0) }, uniquingKeysWith: { a, _ in a })
        // An error describes an attempt at an update that is still on offer. Once
        // the copy is no longer behind — updated from a terminal, or gone — it
        // would otherwise sit beside a current install in the workbench.
        for path in errors.keys where byPath[path]?.state != .updateAvailable {
            errors[path] = nil
            errorLogs[path] = nil
        }
        // "Updated to X" is about the copy as DuoUpdater left it. Something else
        // has changed it since (or it is gone) — the claim no longer holds.
        for (path, version) in justUpdated {
            if byPath[path]?.install.version != version { justUpdated[path] = nil }
        }
    }

    /// Run the one-click update of the install at `path`.
    func update(path: String) async {
        // Re-read here, not trusted from the click: the list may have been
        // re-checked since the row was drawn, and `oneClickable` is what carries
        // every gate — auto-update on, nothing else updating, not already ours.
        guard let status = oneClickable.first(where: { $0.install.path == path }) else { return }
        updating.insert(path)
        errors[path] = nil
        errorLogs[path] = nil
        progress[path] = String(localized: "Starting…")
        // Held until the re-check below has landed, not just until the command
        // exits: that check waits on the network, and releasing the row earlier
        // shows the old "outdated" verdict with a live Update button for its length.
        defer {
            updating.remove(path)
            progress[path] = nil
        }
        let outcome = await runUpdate(status) { [weak self] line in
            Task { @MainActor in
                // A line can arrive after the update has finished and its progress
                // been cleared; writing it then would pin a stale line on the row.
                guard let self, self.updating.contains(path) else { return }
                self.progress[path] = line
            }
        }
        switch outcome {
        case .updated(let version):
            progress[path] = String(localized: "Checking…")
            await refresh()
            // Exit 0 is not proof of an update: measured, `claude update` exits 0
            // having stayed put ("… predates release-signature enforcement; staying
            // on X"), and the updater then reports the version it left. Only a
            // version other than the one clicked on counts — the updater's own
            // re-read first, the fresh scan's when it had none.
            let before = status.install.version
            let after = version ?? claudeCode.first { $0.install.path == path }?.install.version
            if let after, after != before {
                confirmUpdate(path, version: after)
            } else {
                Log.app.info("claude-code update at \(path, privacy: .public) exited 0 but left \(after ?? "an unreadable version", privacy: .public)")
                // Brew's "brew update finished, but Homebrew is still X" rule: a
                // run that changed nothing reads as a failure, not as silence.
                errors[path] = after.map { String(localized: "Still \($0) after the update") }
                    ?? String(localized: "Couldn’t read the version after the update")
            }
        case .failed(let message, let output):
            Log.app.info("claude-code update failed at \(path, privacy: .public): \(message, privacy: .public)")
            errors[path] = message
            errorLogs[path] = output
        case .busy, .notOffered:
            // Nothing ran. Something changed between the check and the click — an
            // update started elsewhere, or the offer went away — so re-check and let
            // the row say what is true now.
            await refresh()
        }
    }

    /// Show "Updated to X" for `confirmationWindow`, then let the row say what it
    /// says of any current copy. Re-entry restarts the window.
    private func confirmUpdate(_ path: String, version: String) {
        justUpdated[path] = version
        confirmationTimers[path]?.cancel()
        let window = confirmationWindow
        confirmationTimers[path] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: window)
            // A newer window owns the clearing.
            guard !Task.isCancelled, let self else { return }
            self.confirmationTimers[path] = nil
            self.justUpdated[path] = nil
        }
    }

    /// Update every install in `oneClickable`, one after another.
    ///
    /// One at a time, not in parallel: two npm prefixes could run side by side,
    /// but a native `claude update` and an npm install both end in a re-check of
    /// every copy, and the row reads one live line.
    func updateAll() async {
        guard !updatingAll else { return }
        updatingAll = true
        defer { updatingAll = false }
        for path in oneClickable.map(\.install.path) {
            // Each update ends in a re-check, which can withdraw the offer for the
            // rest (auto-update switched off meanwhile); `update` re-reads it.
            await update(path: path)
        }
    }

    // MARK: - Wording

    /// Why an install has no one-click, in the user's terms rather than the gate's.
    static func reason(_ withheld: ClaudeCodeStatus.Withheld) -> String {
        switch withheld {
        case .autoUpdateOff:
            return String(localized: "Auto-update is off in Claude Code’s settings")
        case .updatesDisabled:
            return String(localized: "Updates are turned off in Claude Code’s settings")
        case .busy:
            return String(localized: "Claude Code is already being updated")
        case .versionMismatch:
            return String(localized: "Can’t confirm which version is installed")
        case .unsupportedInstaller:
            return String(localized: "No one-click update for this kind of install")
        case .noOwnNpm:
            return String(localized: "Can’t tell which npm installed it")
        case .broken:
            return String(localized: "An install is broken")
        case .notAnthropic:
            return String(localized: "Not signed by Anthropic")
        case .versionUnreadable:
            return String(localized: "Couldn’t read the installed version")
        case .channelUnreadable:
            return String(localized: "Couldn’t reach Claude Code’s release channel")
        }
    }

    /// Which installer a copy came from, as the summary names it: "native",
    /// "npm (node v24)". The installer names are the tools' own, so untranslated,
    /// like the formula names on the brew row.
    static func label(_ install: ClaudeCodeInstall) -> String {
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

    /// "Claude Code ×2 — native, npm (node v24)".
    static func summary(_ installs: [ClaudeCodeInstall]) -> String {
        let count = installs.count > 1 ? " ×\(installs.count)" : ""
        return "Claude Code\(count) — " + installs.map(label).joined(separator: ", ")
    }
}
