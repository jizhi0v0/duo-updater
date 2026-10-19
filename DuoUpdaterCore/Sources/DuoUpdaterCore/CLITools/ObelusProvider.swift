import Foundation

/// Obelus's `obg` and `ob` as one of the app's command-line tools: its own
/// scanner, check and updater (`Obelus*`), seen through `CLIToolProvider`.
/// Its check reads a release download (`SHA256SUMS`), not the GitHub API.
public struct ObelusProvider: CLIToolProvider {
    public var kind: CLIToolKind { .obelus }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { ObelusScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the file the path resolves
    /// to, whether it is a link, whether it may be replaced, and a problem.
    static func sighting(_ install: ObelusInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .obelus, path: install.path, version: install.version,
            state: [install.binary, install.linked ? "linked" : nil,
                    install.writable ? "writable" : "readonly", install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([ObelusInstall], ObelusActivity.Busy?) in
            let installs = ObelusScanner().scan()
            return (installs, installs.isEmpty ? nil : ObelusActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: ObelusCheck())
    }

    /// One `SHA256SUMS` for both rows, asked only when there is a row.
    static func report(installs: [ObelusInstall], busy: ObelusActivity.Busy?, check: ObelusCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        if !installs.isEmpty {
            let published = await check.published()
            statuses = installs.map { check.status(of: $0, busy: busy, published: published) }
        }
        return CLIToolReport(kind: .obelus, statuses: statuses, context: .obelus, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await ObelusUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await ObelusRelease().notes(force: force)
    }
}
