import Foundation

/// Deno as one of the app's command-line tools: its own scanner, check and
/// updater (`Deno*`), seen through `CLIToolProvider`.
public struct DenoProvider: CLIToolProvider {
    public var kind: CLIToolKind { .deno }

    let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan() async -> [CLIToolSighting] {
        let home = self.home
        return await offCooperativePool { DenoScanner(home: home).scan().map { [Self.sighting($0)] } ?? [] }
    }

    /// What the verdict rests on besides the version: the revision, the folder,
    /// quarantine and a problem.
    static func sighting(_ install: DenoInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .deno, path: install.path, version: install.version,
            state: [install.revision, install.writable ? nil : "readonly", install.quarantined ? "quarantined" : nil,
                    install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let scanner = DenoScanner(home: home)
        guard let found = await offCooperativePool({ scanner.scan() }) else {
            return CLIToolReport(kind: .deno, statuses: [], context: .deno, sightings: [])
        }
        let install = await scanner.checked(found)
        let busy = await offCooperativePool {
            DenoActivity.upgrading(deno: install.path, processes: NpmActivity.runningProcesses())
        }
        let status = await DenoCheck().status(of: install, busy: busy)
        return CLIToolReport(kind: .deno, statuses: [status], context: .deno, sightings: [Self.sighting(install)])
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await DenoUpdater().update(status, progress: progress)
    }

    /// Deno's GitHub Releases (`DenoChangelog`).
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await DenoChangelog.fetch(force: force)
    }
}
