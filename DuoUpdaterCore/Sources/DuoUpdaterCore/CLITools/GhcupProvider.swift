import Foundation

/// ghcup as one of the app's command-line tools: its own scanner, check and
/// updater (`Ghcup*`), seen through `CLIToolProvider`.
public struct GhcupProvider: CLIToolProvider {
    public var kind: CLIToolKind { .ghcup }

    public init() {}

    /// Hashes the file only when it changed since it was last read (`GhcupFileFacts`).
    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { GhcupScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the file's sha256, target,
    /// whether it may be replaced, quarantine and a problem.
    static func sighting(_ install: GhcupInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .ghcup, path: install.path, version: install.version,
            state: [install.sha256, install.target, install.writable ? "writable" : "readonly",
                    install.quarantined ? "quarantined" : nil, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([GhcupInstall], GhcupActivity.Busy?) in
            let installs = GhcupScanner().scan()
            return (installs, installs.isEmpty ? nil : GhcupActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: GhcupCheck())
    }

    static func report(installs: [GhcupInstall], busy: GhcupActivity.Busy?, check: GhcupCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .ghcup, statuses: statuses, context: .ghcup, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await GhcupUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await GhcupChangelog.fetch(force: force)
    }
}
