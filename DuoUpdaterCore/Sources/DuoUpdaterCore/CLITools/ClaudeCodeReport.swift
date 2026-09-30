import Foundation

/// One full look at Claude Code on this Mac: every install, the settings that
/// govern them, and each one's verdict. What `duo claude-code` prints and what the
/// app's CLI surface shows are this same answer.
public struct ClaudeCodeReport: Sendable, Equatable {
    public let settings: ClaudeCodeSettings
    public let statuses: [ClaudeCodeStatus]

    public init(settings: ClaudeCodeSettings, statuses: [ClaudeCodeStatus]) {
        self.settings = settings
        self.statuses = statuses
    }

    /// Scans, reads the settings and the process table, then checks each install
    /// against its channel. The blocking parts run off the cooperative pool.
    public static func check(userPaths: [String] = [], check: ClaudeCodeCheck = ClaudeCodeCheck()) async -> ClaudeCodeReport {
        let (installs, settings) = await offCooperativePool {
            (ClaudeCodeScanner().scan(userPaths: userPaths), ClaudeCodeSettings.read())
        }
        let processes = await offCooperativePool { ClaudeCodeActivity.runningProcesses() }
        var statuses: [ClaudeCodeStatus] = []
        for install in installs {
            let busy = ClaudeCodeActivity.busy(install, processes: processes)
            statuses.append(await check.status(of: install, settings: settings, busy: busy))
        }
        return ClaudeCodeReport(settings: settings, statuses: statuses)
    }
}
