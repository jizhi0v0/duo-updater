import Foundation

/// Runs the one-click update a global npm package's status offers and reports
/// how it went.
///
/// It runs exactly `status.oneClick`, never a command of its own: which command
/// is allowed for which package is `NpmCheck`'s decision. The one gate asked
/// again here is "is something already changing this prefix", because that one
/// can change between the check and the click.
///
/// Success is exit 0 **and** the package's `package.json` reading the version
/// the check chose. openclaw's `update` exits 0 having changed nothing when it
/// cannot tell which package manager installed it ("skipped", 2026.3.28), and a
/// version left as it was would read as success on a row that offers the same
/// update again.
///
/// npm replaces the package directory whole (a new inode each time). A copy of
/// the CLI that is running while that happens can load files of both versions —
/// seen once on this Mac — and nothing here can tell such a process from an idle
/// one, so there is no gate for it.
public struct NpmUpdater: Sendable {

    /// Is something already changing this prefix? Injected so tests never read
    /// the host's process table.
    typealias BusyCheck = @Sendable (NpmInstall) -> NpmActivity.Busy?

    let busy: BusyCheck
    /// Whether the prefix's node may still be run, asked again at the click: the
    /// node a check trusted can be replaced before it (`NpmRuntime.nodeIsTrusted`).
    let trustsNode: @Sendable (NpmInstall) -> Bool
    /// The child's environment before `PATH` is set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// openclaw's own update allows each of its steps 20 minutes (its
    /// `--timeout` default, 1200 s) — the install, then doctor, then its plugin
    /// sync. 30 minutes for the whole run, as for Claude Code's npm update, is a
    /// hang, not a slow link; the grace lets npm clean up its staging directory.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(30 * 60), killAfter: .seconds(30 * 60 + 30))

    public init() {
        self.init(
            busy: { NpmActivity.busy($0, processes: NpmActivity.runningProcesses()) },
            trustsNode: { NpmUpdater.nodeIsTrustedNow($0) },
            // A GUI app launched by launchd has no proxy variables; npm honours
            // `https_proxy` & co. when its own `https-proxy` is unset (npm 11's
            // `config.md`). See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        trustsNode: @escaping @Sendable (NpmInstall) -> Bool = { _ in true },
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = NpmUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.trustsNode = trustsNode
        self.environment = environment
        self.deadline = deadline
    }

    /// - Parameter progress: each new line of the command's output, as it arrives.
    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .npm(let package) = status.detail,
              let target = package.offered else { return .notOffered }
        let install = package.install
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running.description)
        }
        let trustsNode = self.trustsNode
        guard await offCooperativePool({ trustsNode(install) }) else {
            return .failed(
                message: "not run: \(install.runtime.node ?? "this prefix's node") is no longer a node DuoUpdater may run",
                output: "")
        }

        let run = await Self.run(
            command, environment: Self.childEnvironment(self.environment(), command: command),
            deadline: deadline, progress: progress)
        let outcome: ChildProcess.Outcome
        switch run.result {
        case .couldNotStart(let error):
            return .failed(message: "could not run \(command.executable): \(error)", output: run.text)
        case .finished(let finished):
            outcome = finished
        }
        guard outcome.succeeded else {
            return .failed(message: Self.failureMessage(run.lines, outcome, deadline: deadline), output: run.text)
        }
        let after = await offCooperativePool { Self.installedVersion(at: install.path) }
        guard after == target else {
            return .failed(
                message: "the update finished, but \(install.name) is \(after ?? "unreadable"), not \(target)",
                output: run.text)
        }
        return .updated(version: after)
    }

    /// The prefix's node read again from disk: its signature, quarantine and keg.
    static func nodeIsTrustedNow(_ install: NpmInstall) -> Bool {
        guard let node = install.runtime.node else { return false }
        let resolved = URL(fileURLWithPath: node).resolvingSymlinksInPath()
        return NpmRuntime(
            node: node, npm: install.runtime.npm, npmVersion: install.runtime.npmVersion,
            nodeSignature: CLIToolTrust.signature(of: resolved, teamIdentifier: NpmScanner.nodeTeamIdentifier),
            nodeQuarantined: CLIToolTrust.hasQuarantine(resolved), nodeVersion: install.runtime.nodeVersion,
            homebrewKeg: NodePrefixes.homebrewKeg(ofNode: resolved, prefix: install.prefix.url)
        ).nodeIsTrusted
    }

    // MARK: - Environment

    /// The base environment with `PATH` set to the command's prefix first, and
    /// without the variables that would send the install somewhere else: npm
    /// reads `npm_config_prefix` in any case (`NPM_CONFIG_PREFIX`), and openclaw's
    /// `OPENCLAW_UPDATE_PACKAGE_SPEC` replaces the version `--tag` names. Neither
    /// is in a launchd-started app's environment; `duo` run from a shell can
    /// inherit them.
    static func childEnvironment(_ base: [String: String], command: CLIToolCommand) -> [String: String] {
        var environment = base.filter {
            $0.key.lowercased() != "npm_config_prefix" && $0.key != "OPENCLAW_UPDATE_PACKAGE_SPEC"
        }
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        return environment
    }

    /// `CLIToolCommandRunner.run`, with standard input an empty pipe instead of
    /// this process's. openclaw asks its questions only when `stdin.isTTY`
    /// (shell completion, a downgrade, doctor's repairs), and `duo` run in a
    /// terminal would otherwise hand it that terminal.
    static func run(
        _ command: CLIToolCommand, environment: [String: String], deadline: ChildProcess.Deadline,
        progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolCommandRunner.Run {
        let log = CLIToolCommandRunner.OutputLog(onLine: progress)
        let result: CLIToolCommandRunner.Run.Result
        do {
            result = .finished(try await ChildProcess.run(
                command.executable, command.arguments, environment: environment, standardInput: Data(),
                standardOutput: .discard, standardError: .mergeIntoOutput,
                deadline: deadline, onCancel: .runToCompletion,
                onOutputChunk: { log.append($0) }))
        } catch {
            result = .couldNotStart("\(error)")
        }
        log.finish()
        return CLIToolCommandRunner.Run(result: result, lines: log.lines)
    }

    // MARK: - Afterwards

    /// The version `package.json` at `path` reads as — nil when it cannot be
    /// read, or when the directory is now a link (not what npm installs).
    static func installedVersion(at path: String) -> String? {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) == nil,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["version"] as? String
    }

    /// npm's reason (`ClaudeCodeUpdater.npmReason`: the first `npm error` line
    /// that is not a field) — openclaw prints the npm step's stderr tail too —
    /// else the last line with a letter in it.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let npm = ClaudeCodeUpdater.npmReason(lines) { return npm }
        if !outcome.timedOut, let openclaw = openclawReason(lines) { return openclaw }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }

    /// The reason in the summary `openclaw update` ends with: `Update Result:
    /// ERROR`, `  Reason: global install verify`, its steps, then `Total time:
    /// 25.41s` — the line the shared rule would have shown (the first real
    /// one-click, 2026-10-02, where openclaw 2026.3.28's own check failed after
    /// npm had installed 2026.6.35 whole).
    static func openclawReason(_ lines: [String]) -> String? {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let result = trimmed.lastIndex(where: { $0.hasPrefix("Update Result:") }),
              let reason = trimmed[result...].first(where: { $0.hasPrefix("Reason: ") })
        else { return nil }
        return "openclaw update: " + reason.dropFirst("Reason: ".count)
    }
}
