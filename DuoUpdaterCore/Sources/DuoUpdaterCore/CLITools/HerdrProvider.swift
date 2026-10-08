import Foundation

/// herdr as one of the app's command-line tools: its own scanner, check and
/// updater (`Herdr*`), seen through `CLIToolProvider`.
public struct HerdrProvider: CLIToolProvider {
    public var kind: CLIToolKind { .herdr }
    /// Only when herdr's manifests do not name the installed build, which is not
    /// known before the check: then its GitHub releases are read
    /// (`HerdrRelease.resolve`).
    public var readsGitHubAPI: Bool { true }

    public init() {}

    public func scan() async -> [CLIToolSighting] {
        await HerdrScanner().scan().map(Self.sighting)
    }

    /// What a verdict rests on: the file (which inode, size and time — a `herdr
    /// update` in a terminal renames a new one in), the config, quarantine and a
    /// problem. The scan reads no version (`HerdrInstall`).
    static func sighting(_ install: HerdrInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .herdr, path: install.path, version: nil,
            state: [install.identity, install.target, install.settings.channel,
                    install.settings.versionCheck ? nil : "no-version-check", install.quarantined ? "quarantined" : nil,
                    install.linkTarget, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let installs = await HerdrScanner().scan()
        return await Self.report(installs: installs, processes: {
            await offCooperativePool { ClaudeCodeActivity.runningProcesses() }
        }, check: HerdrCheck())
    }

    static func report(
        installs: [HerdrInstall], processes: () async -> [ClaudeCodeActivity.Process], check: HerdrCheck
    ) async -> CLIToolReport {
        let running = installs.isEmpty ? [] : await processes()
        var statuses: [CLIToolStatus] = []
        for install in installs {
            let directory = URL(fileURLWithPath: install.path).deletingLastPathComponent()
            let busy = await offCooperativePool { HerdrActivity.busy(directory: directory, processes: running) }
            statuses.append(await check.status(of: install, busy: busy))
        }
        return CLIToolReport(kind: .herdr, statuses: statuses, context: .herdr, sightings: installs.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await HerdrUpdater().update(status, progress: progress)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await HerdrChangelog.fetch(force: force)
    }
}
