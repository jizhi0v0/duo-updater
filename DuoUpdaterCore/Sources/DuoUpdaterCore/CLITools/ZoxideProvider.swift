import Foundation

/// zoxide as one of the app's command-line tools: its own scanner, check and
/// updater (`Zoxide*`), seen through `CLIToolProvider`.
public struct ZoxideProvider: CLIToolProvider {
    public var kind: CLIToolKind { .zoxide }
    /// `releases/latest`, on every check (`ZoxideRelease`).
    public var readsGitHubAPI: Bool { true }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { ZoxideScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the file the path resolves
    /// to, its target, whether it is a link, whether it may be replaced without
    /// `sudo`, and a problem.
    static func sighting(_ install: ZoxideInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .zoxide, path: install.path, version: install.version,
            state: [install.binary, install.target, install.linked ? "linked" : nil,
                    install.writable ? "writable" : "readonly", install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([ZoxideInstall], ZoxideActivity.Busy?) in
            let installs = ZoxideScanner().scan()
            return (installs, installs.isEmpty ? nil : ZoxideActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: ZoxideCheck())
    }

    static func report(installs: [ZoxideInstall], busy: ZoxideActivity.Busy?, check: ZoxideCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .zoxide, statuses: statuses, context: .zoxide, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await ZoxideUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await ZoxideRelease().notes(force: force)
    }
}
