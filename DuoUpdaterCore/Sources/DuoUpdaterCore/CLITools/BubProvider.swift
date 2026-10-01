import Foundation

/// bub as one of the app's command-line tools: its own scanner, check and
/// updater (`Bub*`), seen through `CLIToolProvider`.
public struct BubProvider: CLIToolProvider {
    public var kind: CLIToolKind { .bub }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { BubScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: a problem, where the package
    /// came from, and the state of bub's project.
    static func sighting(_ install: BubInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .bub, path: install.path, version: install.version,
            state: [install.method.rawValue, install.problem?.rawValue, install.directSource?.rawValue,
                    install.project?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let installs = await offCooperativePool { BubScanner().scan() }
        let processes = installs.isEmpty ? [] : await offCooperativePool { ClaudeCodeActivity.runningProcesses() }
        let statuses = await BubCheck().statuses(of: installs) { BubActivity.busy($0, processes: processes) }
        return CLIToolReport(kind: .bub, statuses: statuses, context: .bub, sightings: installs.map(Self.sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await BubUpdater().update(status, progress: progress)
    }

    /// bub's GitHub Releases (`BubChangelog`).
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await BubChangelog.fetch(force: force)
    }
}
