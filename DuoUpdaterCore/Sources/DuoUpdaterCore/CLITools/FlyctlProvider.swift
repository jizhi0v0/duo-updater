import Foundation

/// Fly.io's flyctl as one of the app's command-line tools (`Flyctl*`), seen
/// through `CLIToolProvider`.
public struct FlyctlProvider: CLIToolProvider {
    public var kind: CLIToolKind { .flyctl }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { FlyctlScanner().scan() }.map(Self.sighting)
    }

    static func sighting(_ install: FlyctlInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .flyctl, path: install.path, version: install.version,
            state: [install.binary, install.target, install.writable ? "writable" : "readonly",
                    install.quarantined ? "quarantined" : nil, install.channel,
                    install.autoUpdate ? nil : "auto-off", install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([FlyctlInstall], FlyctlActivity.Busy?) in
            let installs = FlyctlScanner().scan()
            return (installs, installs.isEmpty ? nil : FlyctlActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: FlyctlCheck())
    }

    static func report(installs: [FlyctlInstall], busy: FlyctlActivity.Busy?, check: FlyctlCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .flyctl, statuses: statuses, context: .flyctl, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await FlyctlUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await FlyctlChangelog.fetch(force: force)
    }
}
