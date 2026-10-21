import Foundation

/// Biome as one of the app's command-line tools: its own scanner, check and
/// updater (`Biome*`), seen through `CLIToolProvider`.
///
/// Its version source is `latest.txt`, which revalidates by ETag; the GitHub API
/// is asked only for what is not yet remembered (`BiomePublishedDigests`): a new
/// version's digest, once, and the releases' list when a file matches no build
/// known — at most once per new Biome release. So not `readsGitHubAPI`.
public struct BiomeProvider: CLIToolProvider {
    public var kind: CLIToolKind { .biome }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { BiomeScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the file the path resolves
    /// to, its hash, whether it is a link, whether its directory may be written
    /// without `sudo`, and a problem.
    static func sighting(_ install: BiomeInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .biome, path: install.path, version: install.version,
            state: [install.binary, install.sha256, install.linked ? "linked" : nil,
                    install.writable ? "writable" : "readonly", install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([BiomeInstall], BiomeActivity.Busy?) in
            let installs = BiomeScanner().scan()
            return (installs, installs.isEmpty ? nil : BiomeActivity.busy(processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: BiomeCheck())
    }

    static func report(installs: [BiomeInstall], busy: BiomeActivity.Busy?, check: BiomeCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .biome, statuses: statuses, context: .biome, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await BiomeUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await BiomeRelease().notes(force: force)
    }
}
