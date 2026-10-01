import Foundation

/// bub as one of the app's command-line tools: its own scanner, check and
/// updater (`Bub*`), seen through `CLIToolProvider`.
public struct BubProvider: CLIToolProvider {
    public var kind: CLIToolKind { .bub }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { BubScanner().scan() }
            .map { CLIToolSighting(kind: .bub, path: $0.path, version: $0.version) }
    }

    public func check() async -> CLIToolReport {
        let installs = await offCooperativePool { BubScanner().scan() }
        let processes = installs.isEmpty ? [] : await offCooperativePool { ClaudeCodeActivity.runningProcesses() }
        let statuses = await BubCheck().statuses(of: installs) { BubActivity.busy($0, processes: processes) }
        return CLIToolReport(kind: .bub, statuses: statuses, context: .bub)
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await BubUpdater().update(status, progress: progress)
    }

    /// bub's GitHub Releases (`BubChangelog`).
    public func releaseNotes(force: Bool) async throws -> Changelog {
        try await BubChangelog.fetch(force: force)
    }
}
