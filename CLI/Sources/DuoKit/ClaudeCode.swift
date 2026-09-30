import Foundation
import DuoUpdaterCore

/// `duo claude-code` — every Claude Code install on this Mac, whether it is behind
/// its own channel, and whether DuoUpdater would offer to update it (and how).
///
/// Read-only: it prints the command a one-click update would run, and runs
/// nothing.
public enum ClaudeCode {

    public struct Options: Sendable {
        public var json = false
        /// Paths the user added by hand, on top of the conventional ones.
        public var userPaths: [String] = []
        public init() {}
    }

    struct Row: Encodable {
        let status: ClaudeCodeStatus
        let settingsSources: [String]
    }

    public static func run(_ options: Options) async -> Int32 {
        // Said out loud rather than dropped: a path the user typed that yields no
        // row would otherwise read as "not found".
        for path in options.userPaths {
            if let app = ClaudeCodeScanner.owningApp(of: path) {
                FileHandle.standardError.write(Data(
                    "skipped \(path): inside \(app.path), which ships and updates it\n".utf8))
            } else if let cask = ClaudeCodeScanner.homebrewCask(of: path) {
                FileHandle.standardError.write(Data(
                    "skipped \(path): installed by the Homebrew cask \(cask), which brew upgrade updates\n".utf8))
            }
        }
        let report = await ClaudeCodeReport.check(userPaths: options.userPaths)
        let (settings, statuses) = (report.settings, report.statuses)

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            for status in statuses {
                let row = Row(status: status, settingsSources: settings.sources)
                if let data = try? encoder.encode(row) { print(String(decoding: data, as: UTF8.self)) }
            }
        } else {
            print("settings: channel \(settings.channel.rawValue)"
                + (settings.minimumVersion.map { ", minimum \($0)" } ?? "")
                + ", auto-update \(settings.autoUpdatesEnabled ? "on" : "off")"
                + (settings.sources.isEmpty ? " (defaults)" : " — from \(settings.sources.joined(separator: ", "))"))
            if statuses.isEmpty { print("no Claude Code install found") }
            for status in statuses { print(""); print(describe(status)) }
        }
        return statuses.contains { $0.state == .updateAvailable } ? 1 : 0
    }

    static func describe(_ status: ClaudeCodeStatus) -> String {
        let install = status.install
        var lines = ["\(install.path)"]
        lines.append("  installed by  \(install.method.rawValue)"
            + (install.origin == .userAdded ? " (added by hand)" : ""))
        lines.append("  version       \(install.version ?? "?")"
            + (status.versionConfirmed == true ? " (matches the release manifest)" : "")
            + (status.versionConfirmed == false ? " (does NOT match the release manifest)" : ""))
        lines.append("  signature     \(install.signature?.rawValue ?? "not checked")")
        lines.append("  channel       \(status.channel.rawValue) → \(status.latestVersion ?? "?")")
        lines.append("  state         \(status.state.rawValue)")
        if let command = status.oneClick { lines.append("  one-click     \(command.display)") }
        if let note = status.note { lines.append("  note          \(note)") }
        return lines.joined(separator: "\n")
    }
}
