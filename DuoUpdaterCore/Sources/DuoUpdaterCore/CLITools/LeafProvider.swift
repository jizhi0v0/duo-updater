import Foundation

public struct LeafProvider: CLIToolProvider {
    public var kind: CLIToolKind { .leaf }
    public init() {}

    static func sighting(_ install: LeafInstall) -> CLIToolSighting {
        CLIToolSighting(kind: .leaf, path: install.path, version: install.version,
                       state: [install.binary ?? "-", install.target ?? "-",
                               install.quarantined ? "quarantined" : "clear",
                               install.writable ? "writable" : "readonly"].joined(separator: "|"))
    }

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { LeafScanner().scan() }.map(Self.sighting)
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool {
            let installs = LeafScanner().scan()
            return (installs, installs.isEmpty ? false : LeafActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: LeafCheck())
    }

    static func report(installs: [LeafInstall], busy: Bool, check: LeafCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        if !installs.isEmpty {
            let published = await check.published()
            for install in installs { statuses.append(await check.status(of: install, busy: busy, published: published)) }
        }
        return CLIToolReport(kind: .leaf, statuses: statuses, context: .leaf, sightings: installs.map(sighting))
    }

    public func update(_ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void) async -> CLIToolUpdateOutcome {
        await LeafUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await LeafChangelog.fetch(force: force, version: status.latestVersion)
    }
}
