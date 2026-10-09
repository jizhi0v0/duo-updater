import Foundation

/// The Lorca CLI as one of the app's command-line tools: its own scanner, check
/// and updater (`Lorca*`), seen through `CLIToolProvider`.
public struct LorcaProvider: CLIToolProvider {
    public var kind: CLIToolKind { .lorca }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { LorcaScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the file the path resolves
    /// to, its target, whether it may be replaced, quarantine, the auto-update
    /// setting and a problem.
    static func sighting(_ install: LorcaInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .lorca, path: install.path, version: install.version,
            state: [install.binary, install.target, install.writable ? "writable" : "readonly",
                    install.quarantined ? "quarantined" : nil, install.autoUpdate ? nil : "auto-off",
                    install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([LorcaInstall], LorcaActivity.Busy?) in
            let installs = LorcaScanner().scan()
            return (installs, installs.isEmpty ? nil : LorcaActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: LorcaCheck())
    }

    static func report(installs: [LorcaInstall], busy: LorcaActivity.Busy?, check: LorcaCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .lorca, statuses: statuses, context: .lorca, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await LorcaUpdater().update(status, progress: progress)
    }

    /// None to show: the CLI's GitHub releases carry only the install commands
    /// (cli-v0.1.1 to 0.1.11, read 2026-10-09), and the repository's
    /// `CHANGELOG.md` is the Mac app's, by the app's version.
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        Changelog(entries: [])
    }
}
