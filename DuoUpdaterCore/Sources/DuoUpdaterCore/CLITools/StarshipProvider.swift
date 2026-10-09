import Foundation

/// Starship as one of the app's command-line tools (`Starship*`), seen through
/// `CLIToolProvider`.
public struct StarshipProvider: CLIToolProvider {
    public var kind: CLIToolKind { .starship }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { StarshipScanner().scan() }.map(Self.sighting)
    }

    static func sighting(_ install: StarshipInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .starship, path: install.path, version: install.version,
            state: [install.binary, install.target, install.writable ? "writable" : "readonly",
                    install.quarantined ? "quarantined" : nil, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([StarshipInstall], StarshipActivity.Busy?) in
            let installs = StarshipScanner().scan()
            return (installs, installs.isEmpty ? nil : StarshipActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: StarshipCheck())
    }

    static func report(installs: [StarshipInstall], busy: StarshipActivity.Busy?, check: StarshipCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .starship, statuses: statuses, context: .starship, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await StarshipUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await StarshipChangelog.fetch(force: force)
    }
}
