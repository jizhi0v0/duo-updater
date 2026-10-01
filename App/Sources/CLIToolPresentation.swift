import Foundation
import DuoUpdaterCore

/// How the workbench words one install of any command-line tool: its name in the
/// list, its caption, and why no update is offered.
///
/// Claude Code keeps its own wording (`ClaudeCodePresentation`), which knows its
/// installers and signatures; every other tool is worded from `CLIToolStatus`'s
/// shared fields alone, so a new tool shows up sensibly before it has any wording
/// of its own.
///
/// Foundation only, and no `AppListModel`, so the app test target can compile it
/// (see `DuoUpdaterAppTests` in `App/project.yml`). The views in
/// `CLIToolsWorkbench.swift` only lay these strings out.
enum CLIToolPresentation {

    /// The install's name in the list: Claude Code's own title, otherwise its path
    /// with the home directory written `~`.
    static func title(of status: CLIToolStatus, home: String) -> String {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.title(of: claudeCode.install, home: home)
        }
        return ClaudeCodePresentation.abbreviate(status.path, home: home)
    }

    /// A row's caption when it shows versions: `0.4.2 → 0.5.0` when there is an
    /// update, the installed version otherwise.
    static func versionCaption(_ status: CLIToolStatus) -> String {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.versionCaption(claudeCode)
        }
        if status.state == .updateAvailable, let installed = status.installedVersion,
           let latest = status.latestVersion {
            return "\(installed) → \(latest)"
        }
        return status.installedVersion ?? String(localized: "Version can’t be read")
    }

    /// The one line a row shows instead of versions when the check gave no
    /// verdict. nil when it did.
    static func rowWarning(_ status: CLIToolStatus) -> String? {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.rowWarning(claudeCode)
        }
        guard status.state == .unknown, let withheld = status.withheld else { return nil }
        return CLIToolsModel.reason(withheld, of: status.kind)
    }

    /// Why no update is offered — for the detail pane and the row's tooltip. nil
    /// when one is offered, or when there is nothing to offer (up to date, ahead).
    static func explanation(_ status: CLIToolStatus) -> String? {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.explanation(claudeCode)
        }
        guard status.oneClick == nil, let withheld = status.withheld else { return nil }
        return CLIToolsModel.reason(withheld, of: status.kind)
    }

    /// The command to copy beside an update the user turned the tool's auto-update
    /// off for — the same command a one-click would run. nil otherwise: every
    /// other gate means it should not be run now, or it is DuoUpdater's to run.
    static func manualCommand(_ status: CLIToolStatus) -> String? {
        if case .claudeCode(let claudeCode) = status.detail {
            return ClaudeCodePresentation.manualCommand(claudeCode)
        }
        guard status.state == .updateAvailable, status.withheld == .autoUpdateOff else { return nil }
        return status.manualCommand?.display
    }

    /// The channel a tool's group header names, read off its installs: one name
    /// when they agree, each when they do not. nil for a tool without channels.
    static func channels(of statuses: [CLIToolStatus]) -> String? {
        var seen: [String] = []
        for channel in statuses.compactMap(\.channel) where !seen.contains(channel) {
            seen.append(channel)
        }
        return seen.isEmpty ? nil : seen.joined(separator: ", ")
    }
}
