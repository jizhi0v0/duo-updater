import Foundation

/// terminal-mac as one of the app's command-line tools: its own scanner, check
/// and updater (`TerminalMac*`), seen through `CLIToolProvider`.
///
/// The check asks `api.github.com/repos/govijr/terminal-mac/releases/latest` for
/// the version and the archive's digest, so it reads the GitHub API and follows
/// the app's budget rule (`readsGitHubAPI`). The updater downloads from
/// `github.com/.../releases/download/<tag>/`, which is not the API; the check's
/// request is the only one that spends the budget.
///
/// The vendor publishes no release notes: the bodies of `v0.2.0-4`, `-5` and
/// `-6` are empty, and the repository has no changelog file. So a row has no
/// release notes to show; the provider says so by answering with an empty
/// changelog rather than inventing entries from commit titles.
public struct TerminalMacProvider: CLIToolProvider {
    public var kind: CLIToolKind { .terminalMac }

    public var readsGitHubAPI: Bool { true }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { TerminalMacScanner().scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: the executable the launcher
    /// resolves to, the prefix, whether it may be written without `sudo`, and a
    /// problem.
    static func sighting(_ install: TerminalMacInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .terminalMac, path: install.path, version: install.displayVersion,
            state: [install.binary, install.prefix, install.linked ? "linked" : nil,
                    install.writable ? "writable" : "readonly", install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let (installs, busy) = await offCooperativePool { () -> ([TerminalMacInstall], TerminalMacActivity.Busy?) in
            let installs = TerminalMacScanner().scan()
            return (installs,
                    installs.isEmpty ? nil : TerminalMacActivity.busy(
                        prefix: installs.first?.prefix, processes: ClaudeCodeActivity.runningProcesses()))
        }
        return await Self.report(installs: installs, busy: busy, check: TerminalMacCheck())
    }

    static func report(installs: [TerminalMacInstall], busy: TerminalMacActivity.Busy?,
                       check: TerminalMacCheck) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        if !installs.isEmpty {
            let published = await check.published()
            statuses = installs.map { check.status(of: $0, busy: busy, published: published) }
        }
        return CLIToolReport(kind: .terminalMac, statuses: statuses, context: .terminalMac,
                             sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await TerminalMacUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        Changelog(entries: [])
    }
}
