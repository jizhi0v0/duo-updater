import Foundation

/// uv as one of the app's command-line tools: its own scanner, check and updater
/// (`Uv*`), seen through `CLIToolProvider`.
public struct UvProvider: CLIToolProvider {
    public var kind: CLIToolKind { .uv }

    public init() {}

    /// Runs each copy signed by Astral's Team for `--version` (`UvScanner`); an
    /// unsigned one is read from its receipt and never run.
    public func scan() async -> [CLIToolSighting] {
        await UvScanner().scan().map(Self.sighting)
    }

    /// What a verdict rests on besides the version: layout, signatures,
    /// quarantine, a problem, the receipt's version, a click's hash verdict and
    /// which file the path resolves to.
    static func sighting(_ install: UvInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .uv, path: install.path, version: install.version,
            state: [install.layout.rawValue, install.signature?.rawValue, install.uvxSignature?.rawValue,
                    install.quarantined ? "quarantined" : nil, install.problem?.rawValue, install.receiptVersion,
                    install.hashVerdict?.rawValue, install.executable]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let installs = await UvScanner().scan()
        return await Self.report(installs: installs, processes: {
            await offCooperativePool { ClaudeCodeActivity.runningProcesses() }
        }, check: UvCheck())
    }

    static func report(
        installs: [UvInstall], processes: () async -> [ClaudeCodeActivity.Process], check: UvCheck
    ) async -> CLIToolReport {
        let busy = installs.isEmpty ? nil : UvActivity.busy(processes: await processes())
        let statuses = await check.statuses(of: installs, busy: busy)
        return CLIToolReport(kind: .uv, statuses: statuses, context: .uv, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await UvUpdater().update(status, progress: progress)
    }

    /// uv's own `CHANGELOG.md`, and the older series' files the install's
    /// version needs (`UvChangelog`).
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await UvChangelog.fetch(installed: status.installedVersion, force: force)
    }
}
