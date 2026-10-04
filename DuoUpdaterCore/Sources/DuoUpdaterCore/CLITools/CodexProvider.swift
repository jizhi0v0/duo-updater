import Foundation

/// OpenAI's standalone Codex CLI as one of the app's command-line tools: its own
/// scanner, check and updater (`Codex*`), seen through `CLIToolProvider`.
public struct CodexProvider: CLIToolProvider {
    public var kind: CLIToolKind { .codex }

    public init() {}

    /// Files only: no signature (`CodexInstall.signature`), nothing run.
    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { CodexScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the target, quarantine and a
    /// problem.
    static func sighting(_ install: CodexInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .codex, path: install.path, version: install.version,
            state: [install.target, install.quarantined ? "quarantined" : nil, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let scanner = CodexScanner()
        let (installs, settings, busy) = await offCooperativePool {
            let installs = scanner.scan().map(scanner.withSignature)
            return (installs, CodexSettings.read(home: scanner.home),
                    installs.isEmpty ? nil : CodexActivity.busy(root: scanner.root))
        }
        return await Self.report(installs: installs, settings: settings, busy: busy, check: CodexCheck())
    }

    static func report(
        installs: [CodexInstall], settings: CodexSettings, busy: CodexActivity.Busy?, check: CodexCheck
    ) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, settings: settings, busy: busy))
        }
        return CLIToolReport(kind: .codex, statuses: statuses, context: .codex(settings), sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await CodexUpdater().update(status, progress: progress)
    }

    /// The GitHub Releases of the stable versions around the install's own
    /// (`CodexChangelog`).
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await CodexChangelog.fetch(installed: status.installedVersion, latest: status.latestVersion, force: force)
    }
}
