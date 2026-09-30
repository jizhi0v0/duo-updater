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
/// SKELETON: the interface is fixed; the bodies are to be written.
@MainActor
@Observable
final class CLIToolsModel {

    /// Every Claude Code install found, with its verdict. Empty until the first
    /// check returns (`checked`).
    private(set) var claudeCode: [ClaudeCodeStatus] = []
    /// The settings those verdicts were made under — channel, auto-update.
    private(set) var claudeCodeSettings = ClaudeCodeSettings()
    /// Flips true once the first check returns.
    private(set) var checked = false
    /// A check is in flight.
    private(set) var checking = false

    /// Install paths (`ClaudeCodeInstall.path`) DuoUpdater is updating right now.
    private(set) var updating: Set<String> = []
    /// The latest output line of each running update, by install path.
    private(set) var progress: [String: String] = [:]
    /// The last failed update of each install, by path: the row's one line.
    private(set) var errors: [String: String] = [:]
    /// The full output of each failed update, by path: the detail pane's log.
    private(set) var errorLogs: [String: String] = [:]
    /// Installs updated in this session, by path → the version they now read as.
    /// Open sessions keep the old version until restarted, so the row says so.
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

    init() {}

    /// Re-scan and re-check every tool.
    func refresh() async {}

    /// Run the one-click update of the install at `path`.
    func update(path: String) async {}

    /// Update every install in `oneClickable`, one after another.
    func updateAll() async {}
}
