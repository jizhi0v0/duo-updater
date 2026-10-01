import Foundation

/// fx as one of the app's command-line tools: its own scanner, check and updater
/// (`Fx*`), seen through `CLIToolProvider`.
public struct FxProvider: CLIToolProvider {
    public var kind: CLIToolKind { .fx }

    let userPaths: [String]

    public init(userPaths: [String] = []) {
        self.userPaths = userPaths
    }

    /// Runs each Vercel-signed copy's `--version` (`FxScanner`): nothing else
    /// says which version a copy is.
    public func scan() async -> [CLIToolSighting] {
        await FxScanner().scan(userPaths: userPaths)
            .map { CLIToolSighting(kind: .fx, path: $0.path, version: $0.version) }
    }

    public func check() async -> CLIToolReport {
        let userPaths = self.userPaths
        let installs = await FxScanner().scan(userPaths: userPaths)
        let (settings, processes) = await offCooperativePool {
            (FxSettings.read(), ClaudeCodeActivity.runningProcesses())
        }
        return await Self.report(installs: installs, settings: settings, processes: processes, check: FxCheck())
    }

    static func report(
        installs: [FxInstall], settings: FxSettings, processes: [ClaudeCodeActivity.Process], check: FxCheck
    ) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        for install in installs {
            let busy = FxActivity.busy(install, processes: processes)
            statuses.append(await check.status(of: install, settings: settings, busy: busy))
        }
        return CLIToolReport(kind: .fx, statuses: statuses, context: .fx(settings))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await FxUpdater().update(status, progress: progress)
    }

    /// fx's own `CHANGELOG.md` (`FxChangelog`).
    public func releaseNotes(force: Bool) async throws -> Changelog {
        var request = URLRequest(url: FxChangelog.source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.http(http.statusCode)
        }
        let parsed = await offCooperativePool { FxChangelog.parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
