import Foundation

/// Atuin as one of the app's command-line tools: its own scanner, check and
/// updater (`Atuin*`), seen through `CLIToolProvider`.
public struct AtuinProvider: CLIToolProvider {
    public var kind: CLIToolKind { .atuin }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { AtuinScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the file the path resolves
    /// to, its target, the receipt's directory, whether it may be replaced,
    /// quarantine, the config's channel and check, and a problem.
    static func sighting(_ install: AtuinInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .atuin, path: install.path, version: install.version,
            state: [install.binary, install.target, install.installDirectory,
                    install.writable ? "writable" : "readonly", install.quarantined ? "quarantined" : nil,
                    install.settings.channel, install.settings.updateCheck ? "check" : "nocheck",
                    install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([AtuinInstall], AtuinActivity.Busy?) in
            let installs = AtuinScanner().scan()
            return (installs, installs.isEmpty ? nil : AtuinActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: AtuinCheck())
    }

    static func report(installs: [AtuinInstall], busy: AtuinActivity.Busy?, check: AtuinCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .atuin, statuses: statuses, context: .atuin, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await AtuinUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await AtuinChangelog.fetch(force: force)
    }
}
