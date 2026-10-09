import Foundation

/// Helm as one of the app's command-line tools (`Helm*`), seen through
/// `CLIToolProvider`.
public struct HelmProvider: CLIToolProvider {
    public var kind: CLIToolKind { .helm }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { HelmScanner().scan() }.map(Self.sighting)
    }

    static func sighting(_ install: HelmInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .helm, path: install.path, version: install.version,
            state: [install.binary, install.target, install.writable ? "writable" : "readonly",
                    install.quarantined ? "quarantined" : nil, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([HelmInstall], HelmActivity.Busy?) in
            let installs = HelmScanner().scan()
            return (installs, installs.isEmpty ? nil : HelmActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: HelmCheck())
    }

    static func report(installs: [HelmInstall], busy: HelmActivity.Busy?, check: HelmCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .helm, statuses: statuses, context: .helm, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await HelmUpdater().update(status, progress: progress)
    }

    /// The install's own line's notes; a file whose version could not be read
    /// has no line, and gets none.
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        guard case .helm(let install) = status.detail, let major = install.major else { return Changelog(entries: []) }
        return try await HelmChangelog.fetch(major: major, force: force)
    }
}
