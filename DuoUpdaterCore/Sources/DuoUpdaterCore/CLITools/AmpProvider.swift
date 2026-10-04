import Foundation

/// Amp as one of the app's command-line tools: its own scanner, check and updater
/// (`Amp*`), seen through `CLIToolProvider`.
public struct AmpProvider: CLIToolProvider {
    public var kind: CLIToolKind { .amp }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { AmpScanner().scan() }.map { [Self.sighting($0)] } ?? []
    }

    static func sighting(_ install: AmpInstall) -> CLIToolSighting {
        CLIToolSighting(kind: .amp, path: install.path, version: install.version, state: install.problem?.rawValue ?? "-")
    }

    public func check() async -> CLIToolReport {
        let scanner = AmpScanner()
        let (install, settings, busy) = await offCooperativePool { () -> (AmpInstall?, AmpSettings, AmpActivity.Busy?) in
            guard let install = scanner.scan().map(scanner.withSignature) else { return (nil, AmpSettings(), nil) }
            return (install, AmpSettings.read(home: scanner.home),
                    AmpActivity.busy(root: scanner.root, processes: NpmActivity.runningProcesses()))
        }
        return await Self.report(install: install, settings: settings, busy: busy, check: AmpCheck())
    }

    static func report(install: AmpInstall?, settings: AmpSettings, busy: AmpActivity.Busy?, check: AmpCheck) async -> CLIToolReport {
        guard let install else { return CLIToolReport(kind: .amp, statuses: [], context: .amp(settings), sightings: []) }
        let status = await check.status(of: install, settings: settings, busy: busy)
        return CLIToolReport(kind: .amp, statuses: [status], context: .amp(settings), sightings: [sighting(install)])
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await AmpUpdater().update(status, progress: progress)
    }

    /// Amp publishes no per-release notes — several builds a day, and posts on
    /// ampcode.com/news — so its row has an empty changelog.
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        Changelog(entries: [])
    }
}
