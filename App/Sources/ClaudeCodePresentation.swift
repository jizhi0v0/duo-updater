import Foundation
import DuoUpdaterCore

/// How the workbench words a Claude Code install: its name in the list, who
/// installed it, and — when no update is offered — why, in plain words.
///
/// Foundation only, and no `AppListModel`, so the app test target can compile it
/// (see `DuoUpdaterAppTests` in `App/project.yml`). The views in
/// `CLIToolsWorkbench.swift` only lay these strings out.
enum ClaudeCodePresentation {

    /// The install's identity, shortened for a person.
    ///
    /// The identity is the path (`ClaudeCodeInstall`), but most of a path is noise:
    /// what tells two npm copies apart is which node they live under, and a
    /// package manager's global directory is better said than spelled out. A copy
    /// someone added by hand keeps its path, since that path is how they know it.
    static func title(of install: ClaudeCodeInstall, home: String) -> String {
        switch (install.method, install.origin) {
        case (.npm, _):
            guard let prefix = install.nodePrefix else { return abbreviate(install.path, home: home) }
            // nvm keeps one prefix per node version, `~/.nvm/versions/node/<v>`, and
            // that version is the only thing that differs between its copies.
            let nvm = (home as NSString).appendingPathComponent(".nvm/versions/node")
            let parent = (prefix as NSString).deletingLastPathComponent
            if parent == nvm {
                return "nvm · node \((prefix as NSString).lastPathComponent)"
            }
            return "npm · \(abbreviate(prefix, home: home))"
        case (.pnpm, .conventional):
            return String(localized: "pnpm global")
        case (.bun, .conventional):
            return String(localized: "bun global")
        default:
            return abbreviate(install.path, home: home)
        }
    }

    /// `path` with the home directory written `~`, the way a terminal shows it.
    /// Only a whole leading component matches: `/Users/ann` is not the home of
    /// `/Users/anna/bin/claude`.
    static func abbreviate(_ path: String, home: String) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Who put the copy there, which is also who updates it.
    static func installer(_ method: ClaudeCodeInstall.Method) -> String {
        switch method {
        case .native: String(localized: "Native installer")
        // Tool names, the same in every language.
        case .npm: "npm"
        case .pnpm: "pnpm"
        case .bun: "bun"
        case .unknown: String(localized: "Added by hand")
        }
    }

    /// The installer as a row's caption names it, beside the version. Shorter than
    /// `installer`, which the detail pane uses.
    static func shortInstaller(_ method: ClaudeCodeInstall.Method) -> String {
        method == .native ? String(localized: "Native") : installer(method)
    }

    /// A row's caption when it shows versions: `2.1.274 → 2.1.285` when there is an
    /// update, the versions alone; otherwise `npm · 2.1.285`.
    ///
    /// No installer before the arrow: beside the Update button at the sidebar's
    /// 260 pt, even "Native · 2.1.274 → 2.1.285" cut off the target version — the
    /// one fact the row is there to show (rendered, English). The title already
    /// says where the copy is, and the detail pane says who installed it.
    static func versionCaption(_ status: ClaudeCodeStatus) -> String {
        if status.state == .updateAvailable, let installed = status.install.version,
           let latest = status.latestVersion {
            return "\(installed) → \(latest)"
        }
        return [shortInstaller(status.install.method), status.install.version]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The Claude Code group's header: the channel every install is checked
    /// against, and whether one-click is possible at all.
    static func settingsSummary(_ settings: ClaudeCodeSettings) -> String {
        let channel = settings.channel.rawValue
        if settings.updatesDisabled { return String(localized: "\(channel) · updates off") }
        if settings.autoUpdatesDisabled { return String(localized: "\(channel) · auto-update off") }
        return String(localized: "\(channel) · auto-update on")
    }

    /// The one line a row shows instead of versions when there is no comparison:
    /// a broken copy, or a check that could not finish. nil when there is one.
    static func rowWarning(_ status: ClaudeCodeStatus) -> String? {
        if let problem = status.install.problem {
            switch problem {
            case .executableMissing: return String(localized: "Broken · points at a missing file")
            case .nativeBinaryNotLinked: return String(localized: "Broken · native binary not installed")
            }
        }
        switch status.withheld {
        case .notAnthropic: return String(localized: "Not signed by Anthropic")
        case .versionUnreadable: return String(localized: "Version can’t be read")
        case .channelUnreadable:
            return String(localized: "Couldn’t read the \(status.channel.rawValue) channel")
        default: return nil
        }
    }

    /// Why no update is offered, in a sentence — for the detail pane. nil when one
    /// is offered, or when there is nothing to offer (up to date, ahead).
    static func explanation(_ status: ClaudeCodeStatus) -> String? {
        if let problem = status.install.problem {
            switch problem {
            case .executableMissing:
                return String(localized: "The launcher points at a missing or empty file, so this copy can’t run.")
            case .nativeBinaryNotLinked:
                return String(localized: "The package is installed, but its native binary isn’t: the package manager skipped the install script that puts it in place.")
            }
        }
        switch status.withheld {
        case nil, .broken:
            return nil
        case .notAnthropic:
            return String(localized: "This file isn’t signed by Anthropic, so DuoUpdater neither checks nor updates it.")
        case .versionUnreadable:
            return String(localized: "The version can’t be read from this copy’s files, so it can’t be compared with the channel.")
        case .channelUnreadable:
            return String(localized: "Couldn’t read which version the \(status.channel.rawValue) channel points at, so there is nothing to compare with.")
        case .updatesDisabled:
            return String(localized: "Updates are turned off in Claude Code’s settings (DISABLE_UPDATES), so none is offered.")
        case .autoUpdateOff:
            return String(localized: "Auto-update is off in Claude Code’s settings (DISABLE_AUTOUPDATER), so DuoUpdater reports updates but doesn’t install them.")
        case .busy:
            return String(localized: "An update of this copy is already running, so DuoUpdater won’t start another on top of it.")
        case .versionMismatch:
            let version = status.install.version ?? "?"
            return String(localized: "The file on disk doesn’t match Anthropic’s release manifest for \(version), so DuoUpdater won’t update over it.")
        case .unsupportedInstaller:
            if status.install.method == .unknown {
                return String(localized: "DuoUpdater can’t tell which installer put this copy here, so it only reports updates.")
            }
            let name = Self.installer(status.install.method)
            return String(localized: "Anthropic documents no update command for \(name) installs, so this copy is only reported.")
        case .noOwnNpm:
            let tag = status.channel.rawValue
            return String(localized: "This npm prefix has no node or npm of its own, so DuoUpdater can’t tell which npm installed this copy and only reports updates. To update it, run npm install -g @anthropic-ai/claude-code@\(tag) with the npm that installed it.")
        }
    }

    /// The command the user would run themselves, offered only where DuoUpdater
    /// holds back because they turned auto-update off: the update is theirs to
    /// take, just not ours to start. Every other gate means the command should not
    /// be run (broken, busy, not Anthropic's) or does not exist.
    static func manualCommand(_ status: ClaudeCodeStatus) -> String? {
        guard status.state == .updateAvailable, status.withheld == .autoUpdateOff else { return nil }
        return ClaudeCodeCheck.updateCommand(for: status.install, channel: status.channel)?.display
    }
}
