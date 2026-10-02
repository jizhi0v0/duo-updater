import Foundation

/// The Junie CLI as one of the app's command-line tools: its own scanner, check and
/// updater (`Junie*`), seen through `CLIToolProvider`.
public struct JunieProvider: CLIToolProvider {
    public var kind: CLIToolKind { .junie }

    public init() {}

    /// Files only: no signature (`JunieInstall.signature`), nothing run.
    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { JunieScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the channel, the bundle's own
    /// version, a staged update, a problem, the shim's generation.
    static func sighting(_ install: JunieInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .junie, path: install.path, version: install.version,
            state: [install.channel, install.bundleVersion, install.pendingUpdate, install.problem?.rawValue,
                    install.shim.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let scanner = JunieScanner()
        let (installs, settings, processes) = await offCooperativePool {
            let installs = scanner.scan().map(scanner.withSignature)
            return (installs, JunieSettings.read(), installs.isEmpty ? [] : ClaudeCodeActivity.runningProcesses())
        }
        return await Self.report(installs: installs, settings: settings, processes: processes, check: JunieCheck())
    }

    static func report(
        installs: [JunieInstall], settings: JunieSettings, processes: [ClaudeCodeActivity.Process], check: JunieCheck
    ) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            let busy = await offCooperativePool { JunieActivity.busy(install, processes: processes) }
            statuses.append(await check.status(of: install, settings: settings, busy: busy))
        }
        return CLIToolReport(kind: .junie, statuses: statuses, context: .junie(settings), sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await JunieUpdater().update(status, progress: progress)
    }

    /// The GitHub Releases of the builds the install's channel lists around its
    /// own (`JunieChangelog`).
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        guard let channel = status.channel else { throw CLIToolReleaseNotesError.noSections }
        let builds: [String]
        do {
            builds = try await JunieRelease().builds(channel: channel, force: force).map(\.version)
        } catch JunieRelease.Failure.http(let code) {
            throw CLIToolReleaseNotesError.http(code)
        }
        return try await JunieChangelog.fetch(
            builds: builds, installed: status.installedVersion, latest: status.latestVersion, force: force,
            fetch: { try await JunieChangelog.get($0, force: $1) })
    }
}
