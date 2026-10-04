import Foundation

/// Cursor's command-line agent as one of the app's command-line tools: its own
/// scanner, check and updater (`CursorAgent*`), seen through `CLIToolProvider`.
public struct CursorAgentProvider: CLIToolProvider {
    public var kind: CLIToolKind { .cursorAgent }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { CursorAgentScanner().scan() }.map { [Self.sighting($0)] } ?? []
    }

    static func sighting(_ install: CursorAgentInstall) -> CLIToolSighting {
        CLIToolSighting(kind: .cursorAgent, path: install.path, version: install.version,
                        state: install.problem?.rawValue ?? "-")
    }

    public func check() async -> CLIToolReport {
        let scanner = CursorAgentScanner()
        let (install, settings, busy) = await offCooperativePool {
            () -> (CursorAgentInstall?, CursorAgentSettings, CursorAgentActivity.Busy?) in
            guard let install = scanner.scan() else { return (nil, CursorAgentSettings(), nil) }
            return (install, CursorAgentSettings.read(home: scanner.home),
                    CursorAgentActivity.busy(root: scanner.root, processes: NpmActivity.runningProcesses()))
        }
        return await Self.report(install: install, settings: settings, busy: busy, check: CursorAgentCheck())
    }

    static func report(
        install: CursorAgentInstall?, settings: CursorAgentSettings, busy: CursorAgentActivity.Busy?,
        check: CursorAgentCheck
    ) async -> CLIToolReport {
        guard let install else {
            return CLIToolReport(kind: .cursorAgent, statuses: [], context: .cursorAgent(settings), sightings: [])
        }
        let status = await check.status(of: install, settings: settings, busy: busy)
        return CLIToolReport(kind: .cursorAgent, statuses: [status], context: .cursorAgent(settings),
                             sightings: [sighting(install)])
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await CursorAgentUpdater().update(status, progress: progress)
    }

    /// Cursor publishes the CLI's notes only as a web page (cursor.com/changelog,
    /// mixed with the editor's), not with its releases; an empty changelog, which
    /// the pane words as such.
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        Changelog(entries: [])
    }
}
