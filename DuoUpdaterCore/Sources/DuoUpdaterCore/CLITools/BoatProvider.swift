import Foundation

/// The Boat CLI as one of the app's command-line tools: its own scanner, check
/// and updater (`Boat*`), seen through `CLIToolProvider`.
public struct BoatProvider: CLIToolProvider {
    public var kind: CLIToolKind { .boat }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await BoatScanner().scan().map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the channel and server the
    /// config names, the signature, quarantine and a problem.
    static func sighting(_ install: BoatInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .boat, path: install.path, version: install.version,
            state: [install.settings.channel, install.settings.customAPI, install.architecture,
                    install.signature?.rawValue, install.quarantined ? "quarantined" : nil, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let installs = await BoatScanner().scan()
        return await Self.report(installs: installs, processes: {
            await offCooperativePool { ClaudeCodeActivity.runningProcesses() }
        }, check: BoatCheck())
    }

    static func report(
        installs: [BoatInstall], processes: () async -> [ClaudeCodeActivity.Process], check: BoatCheck
    ) async -> CLIToolReport {
        let busy = installs.isEmpty ? nil : BoatActivity.busy(processes: await processes())
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .boat, statuses: statuses, context: .boat, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await BoatUpdater().update(status, progress: progress)
    }

    /// Boat publishes no release notes: each `boat-cli-v` release's body is the
    /// one line "Boat CLI release boat-cli-v<version>", the repository holds
    /// only a LICENSE, and docs.boat.dev has no changelog page (2026-10-04). An
    /// empty changelog, which the pane words as "no release notes".
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        Changelog(entries: [])
    }
}
