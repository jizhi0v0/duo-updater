import Foundation

/// mise as one of the app's command-line tools: its own scanner, check and
/// updater (`Mise*`), seen through `CLIToolProvider`.
public struct MiseProvider: CLIToolProvider {
    public var kind: CLIToolKind { .mise }

    let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Runs a copy signed by mise's Team for `--version` (`MiseScanner`).
    public func scan() async -> [CLIToolSighting] {
        await MiseScanner(home: home).scan().map { [Self.sighting($0)] } ?? []
    }

    /// What the verdict rests on besides the version: signature, quarantine,
    /// the folder, a packager's marker and a problem.
    static func sighting(_ install: MiseInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .mise, path: install.path, version: install.version,
            state: [install.signature?.rawValue, install.quarantined ? "quarantined" : nil,
                    install.writable ? nil : "readonly", install.selfUpdateDisabledBy, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        guard let install = await MiseScanner(home: home).scan() else {
            return CLIToolReport(kind: .mise, statuses: [], context: .mise, sightings: [])
        }
        let busy = await offCooperativePool {
            MiseActivity.selfUpdating(mise: install.path, processes: NpmActivity.runningProcesses())
        }
        let status = await MiseCheck().status(of: install, busy: busy)
        return CLIToolReport(kind: .mise, statuses: [status], context: .mise, sightings: [Self.sighting(install)])
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await MiseUpdater().update(status, progress: progress)
    }

    /// mise's GitHub Releases (`MiseChangelog`).
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await MiseChangelog.fetch(force: force)
    }
}
