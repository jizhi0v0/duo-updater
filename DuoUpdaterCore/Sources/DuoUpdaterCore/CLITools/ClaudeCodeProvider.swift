import Foundation

/// Claude Code as one of the app's command-line tools: its own scanner, check and
/// updater (`ClaudeCode*`), seen through `CLIToolProvider`.
public struct ClaudeCodeProvider: CLIToolProvider {
    public var kind: CLIToolKind { .claudeCode }

    let userPaths: [String]

    public init(userPaths: [String] = []) {
        self.userPaths = userPaths
    }

    public func scan() async -> [CLIToolSighting] {
        let userPaths = self.userPaths
        return await offCooperativePool { ClaudeCodeScanner().scan(userPaths: userPaths) }
            .map { CLIToolSighting(kind: .claudeCode, path: $0.path, version: $0.version) }
    }

    public func check() async -> CLIToolReport {
        Self.report(await ClaudeCodeReport.check(userPaths: userPaths))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        guard case .claudeCode(let claudeCode) = status.detail else { return .notOffered }
        return Self.outcome(await ClaudeCodeUpdater().update(claudeCode, progress: progress))
    }

    /// Claude Code's own `CHANGELOG.md` (`ClaudeCodeChangelog`).
    public func releaseNotes(force: Bool) async throws -> Changelog {
        var request = URLRequest(url: ClaudeCodeChangelog.source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.http(http.statusCode)
        }
        // Off the caller's actor: 407 sections are tens of milliseconds of parsing
        // (a debug build measured 44 ms), which a window would otherwise stall for.
        let parsed = await offCooperativePool { ClaudeCodeChangelog.parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }

    // MARK: - Mapping

    static func report(_ report: ClaudeCodeReport) -> CLIToolReport {
        CLIToolReport(
            kind: .claudeCode, statuses: report.statuses.map(status), context: .claudeCode(report.settings))
    }

    static func status(_ status: ClaudeCodeStatus) -> CLIToolStatus {
        CLIToolStatus(
            kind: .claudeCode, path: status.install.path, installedVersion: status.install.version,
            latestVersion: status.latestVersion, channel: status.channel.rawValue, state: status.state,
            oneClick: status.oneClick, withheld: status.withheld.map(withheld), note: status.note,
            detail: .claudeCode(status))
    }

    static func withheld(_ withheld: ClaudeCodeStatus.Withheld) -> CLIToolWithheld {
        switch withheld {
        case .broken: return .broken
        case .notAnthropic: return .wrongSigner
        case .versionUnreadable: return .versionUnreadable
        case .channelUnreadable: return .channelUnreadable
        case .updatesDisabled: return .updatesDisabled
        case .autoUpdateOff: return .autoUpdateOff
        case .busy: return .busy
        case .versionMismatch: return .versionMismatch
        case .unsupportedInstaller: return .unsupportedInstaller
        case .noOwnNpm: return .noOwnNpm
        }
    }

    static func outcome(_ outcome: ClaudeCodeUpdater.Outcome) -> CLIToolUpdateOutcome {
        switch outcome {
        case .updated(let version): return .updated(version: version)
        case .busy(let busy): return .busy(busy.description)
        case .notOffered: return .notOffered
        case .failed(let message, let output): return .failed(message: message, output: output)
        }
    }
}
