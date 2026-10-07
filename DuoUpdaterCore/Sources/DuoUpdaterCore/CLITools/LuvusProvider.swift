import Foundation

/// Luvus as one of the app's command-line tools: its own scanner, check and
/// updater (`Luvus*`), seen through `CLIToolProvider`.
public struct LuvusProvider: CLIToolProvider {
    public var kind: CLIToolKind { .luvus }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { LuvusScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the file the path resolves
    /// to, its target, whether it may be replaced without `sudo`, quarantine and
    /// a problem.
    static func sighting(_ install: LuvusInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .luvus, path: install.path, version: install.version,
            state: [install.binary, install.target, install.writable ? "writable" : "readonly",
                    install.quarantined ? "quarantined" : nil, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([LuvusInstall], LuvusActivity.Busy?) in
            let installs = LuvusScanner().scan()
            return (installs, installs.isEmpty ? nil : LuvusActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: LuvusCheck())
    }

    static func report(installs: [LuvusInstall], busy: LuvusActivity.Busy?, check: LuvusCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .luvus, statuses: statuses, context: .luvus, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await LuvusUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await LuvusChangelog.fetch(force: force)
    }
}
