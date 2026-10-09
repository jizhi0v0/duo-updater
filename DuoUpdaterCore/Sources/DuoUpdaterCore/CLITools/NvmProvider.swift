import Foundation

/// nvm as one of the app's command-line tools (`Nvm*`), seen through
/// `CLIToolProvider`. It offers no one-click (`NvmCheck`).
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
                        state: [install.layout.rawValue, install.problem?.rawValue].map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let installs = await offCooperativePool { NvmScanner().scan() }
        return await Self.report(installs: installs, check: NvmCheck())
    }

    static func report(installs: [NvmInstall], check: NvmCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install))
        }
        return CLIToolReport(kind: .nvm, statuses: statuses, context: .nvm, sightings: installs.map(sighting))
    }

    /// Never offered: `NvmCheck` gives no one-click.
    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        .notOffered
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await NvmRelease().notes(force: force)
    }
}
