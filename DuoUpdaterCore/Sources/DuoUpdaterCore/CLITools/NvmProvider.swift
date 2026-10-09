import Foundation

/// nvm as one of the app's command-line tools (`Nvm*`), seen through
/// `CLIToolProvider`; its one-click is the newer tag's installer (`NvmUpdater`).
public struct NvmProvider: CLIToolProvider {
    public var kind: CLIToolKind { .nvm }
    /// `releases/latest`, on every check (`NvmRelease`).
    public var readsGitHubAPI: Bool { true }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { NvmScanner().scan() }.map(Self.sighting)
    }

    static func sighting(_ install: NvmInstall) -> CLIToolSighting {
        CLIToolSighting(kind: .nvm, path: install.path, version: install.version,
                        state: [install.layout.rawValue, install.writable ? "writable" : "readonly", install.problem?.rawValue]
                            .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([NvmInstall], NvmActivity.Busy?) in
            let installs = NvmScanner().scan()
            return (installs, installs.isEmpty ? nil : NvmActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: NvmCheck())
    }

    static func report(installs: [NvmInstall], busy: NvmActivity.Busy?, check: NvmCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .nvm, statuses: statuses, context: .nvm, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await NvmUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await NvmRelease().notes(force: force)
    }
}
