import Foundation

/// Vite+ as one of the app's command-line tools: its own scanner, check and
/// updater (`VitePlus*`), seen through `CLIToolProvider`.
public struct VitePlusProvider: CLIToolProvider {
    public var kind: CLIToolKind { .vitePlus }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { VitePlusScanner().scan() }.map(Self.sighting)
    }

    static func sighting(_ install: VitePlusInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .vitePlus, path: install.path, version: install.version,
            state: [install.problem?.rawValue ?? "-", install.binary ?? "-", install.hashVerdict?.rawValue ?? "-",
                    install.quarantined ? "quarantined" : "-"].joined(separator: " "))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([VitePlusInstall], VitePlusActivity.Busy?) in
            let installs = VitePlusScanner().scan()
            return (installs, installs.isEmpty ? nil : VitePlusActivity.busy(processes: NpmActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: VitePlusCheck())
    }

    static func report(installs: [VitePlusInstall], busy: VitePlusActivity.Busy?, check: VitePlusCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .vitePlus, statuses: statuses, context: .vitePlus, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await VitePlusUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await VitePlusChangelog.fetch(force: force)
    }
}
