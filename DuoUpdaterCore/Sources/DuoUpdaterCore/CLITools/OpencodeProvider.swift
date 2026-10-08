import Foundation

/// OpenCode as one of the app's command-line tools: its own scanner, check and
/// updater (`Opencode*`), seen through `CLIToolProvider`.
public struct OpencodeProvider: CLIToolProvider {
    public var kind: CLIToolKind { .opencode }
    /// `OpencodeRelease` asks the GitHub API for the newest release on every check.
    public var readsGitHubAPI: Bool { true }

    public init() {}

    /// The file read for its version, not run, and not hashed.
    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { OpencodeScanner().scan() }.map { [Self.sighting($0)] } ?? []
    }

    static func sighting(_ install: OpencodeInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .opencode, path: install.path, version: install.version,
            state: [install.architecture, install.problem?.rawValue].map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let scanner = OpencodeScanner()
        let (install, settings, busy) = await offCooperativePool { () -> (OpencodeInstall?, OpencodeSettings, OpencodeActivity.Busy?) in
            guard let install = scanner.scan().map(scanner.withSignature) else { return (nil, OpencodeSettings(), nil) }
            let busy = OpencodeActivity.busy(
                processes: NpmActivity.runningProcesses(), temporaryDirectories: OpencodeActivity.temporaryDirectories)
            return (install, OpencodeSettings.read(home: scanner.home), busy)
        }
        return await Self.report(install: install, settings: settings, busy: busy, check: OpencodeCheck())
    }

    static func report(
        install: OpencodeInstall?, settings: OpencodeSettings, busy: OpencodeActivity.Busy?, check: OpencodeCheck
    ) async -> CLIToolReport {
        guard let install else {
            return CLIToolReport(kind: .opencode, statuses: [], context: .opencode(settings), sightings: [])
        }
        let status = await check.status(of: install, settings: settings, busy: busy)
        return CLIToolReport(kind: .opencode, statuses: [status], context: .opencode(settings), sightings: [sighting(install)])
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await OpencodeUpdater().update(status, progress: progress)
    }

    /// The newest page of OpenCode's GitHub Releases (`OpencodeRelease.notes`).
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await OpencodeRelease().notes(force: force)
    }
}
