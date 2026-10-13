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
///
/// A package of bun's global install runs the same way, with bun's gates: the
/// bun is read again at the click and must still carry Oven's Team ID, the node
/// is asked only when the command runs it (`openclaw update`), and the child gets
/// `BUN_INSTALL` set to the install that was checked.
///
/// `bun add -g <name>@<version>` also writes `<version>` over the user's own
/// specifier in the global `package.json` — `^6.0.0` becomes `7.0.0` (bun
/// 1.4.3, measured 2026-10-13) — and `bun update -g` holds an exact specifier
/// where it is, so one click would quietly pin the package against the user's
/// own updates. The specifier is read before the command and put back in the
/// user's style after it (`restoredSpecifier`).
public struct NpmUpdater: Sendable {

    /// Is something already changing this prefix? Injected so tests never read
    /// the host's process table.
    typealias BusyCheck = @Sendable (NpmInstall) -> NpmActivity.Busy?

    let busy: BusyCheck
    /// Whether the prefix's node may still be run, asked again at the click: the
    /// node a check trusted can be replaced before it (`NpmRuntime.nodeIsTrusted`).
    let trustsNode: @Sendable (NpmInstall) -> Bool
    /// Whether the package's bun may still be run, asked again at the click.
    let trustsBun: @Sendable (BunManager) -> Bool
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
            trustsBun: { NpmUpdater.bunIsTrustedNow($0) },
            // A GUI app launched by launchd has no proxy variables; npm honours
            // `https_proxy` & co. when its own `https-proxy` is unset (npm 11's
            // `config.md`). See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        trustsNode: @escaping @Sendable (NpmInstall) -> Bool = { _ in true },
        trustsBun: @escaping @Sendable (BunManager) -> Bool = { _ in true },
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = NpmUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.trustsNode = trustsNode
        self.trustsBun = trustsBun
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
        if let bun = install.bun {
            let trustsBun = self.trustsBun
            guard await offCooperativePool({ trustsBun(bun) }) else {
                return .failed(message: "not run: \(bun.path) is no longer a bun DuoUpdater may run", output: "")
            }
        }
        // npm's commands run the prefix's node; of bun's, only openclaw's does.
        if install.bun == nil || command.executable == install.runtime.node {
            let trustsNode = self.trustsNode
            guard await offCooperativePool({ trustsNode(install) }) else {
                return .failed(
                    message: "not run: \(install.runtime.node ?? "this prefix's node") is no longer a node DuoUpdater may run",
                    output: "")
            }
        }

        let manifest = install.bun.map { _ in
            URL(fileURLWithPath: install.prefix.path).appendingPathComponent("package.json")
        }
        let specifier = await offCooperativePool { manifest.flatMap { Self.specifier(of: install.name, in: $0) } }

        let run = await Self.run(
            command, environment: Self.childEnvironment(self.environment(), command: command, bun: install.bun),
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
        if let manifest, let specifier {
            _ = await offCooperativePool { Self.restoreSpecifier(specifier, of: install.name, at: target, in: manifest) }
        }
        return .updated(version: after)
    }

    /// The prefix's node read again from disk: its signature, quarantine and keg.
    /// The keg is asked of the prefix the node is in (`<prefix>/bin/node`), which
    /// for npm is the package's own and for bun's global install is not — its
    /// node is Homebrew's (`BunPackages.knownNode`).
    static func nodeIsTrustedNow(_ install: NpmInstall) -> Bool {
        guard let node = install.runtime.node else { return false }
        let nodePrefix = URL(fileURLWithPath: node).deletingLastPathComponent().deletingLastPathComponent()
        let resolved = URL(fileURLWithPath: node).resolvingSymlinksInPath()
        return NpmRuntime(
            node: node, npm: install.runtime.npm, npmVersion: install.runtime.npmVersion,
            nodeSignature: CLIToolTrust.signature(of: resolved, teamIdentifier: NpmScanner.nodeTeamIdentifier),
            nodeQuarantined: CLIToolTrust.hasQuarantine(resolved), nodeVersion: install.runtime.nodeVersion,
            homebrewKeg: NodePrefixes.homebrewKeg(ofNode: resolved, prefix: nodePrefix)
        ).nodeIsTrusted
    }

    // MARK: - Environment

    /// The base environment with `PATH` set to the command's prefix first, and
    /// without the variables that would send the install somewhere else: npm
    /// reads `npm_config_prefix` in any case (`NPM_CONFIG_PREFIX`), and openclaw's
    /// `OPENCLAW_UPDATE_PACKAGE_SPEC` replaces the version `--tag` names. Neither
    /// is in a launchd-started app's environment; `duo` run from a shell can
    /// inherit them.
    ///
    /// For a package of bun's global install, `BUN_INSTALL` is the directory the
    /// bun lives in (`~/.bun`), so `bun add -g` writes where the scan read.
    static func childEnvironment(
        _ base: [String: String], command: CLIToolCommand, bun: BunManager? = nil
    ) -> [String: String] {
        var environment = base.filter {
            $0.key.lowercased() != "npm_config_prefix" && $0.key != "OPENCLAW_UPDATE_PACKAGE_SPEC"
        }
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        if let bun {
            environment["BUN_INSTALL"] = URL(fileURLWithPath: bun.path)
                .deletingLastPathComponent().deletingLastPathComponent().path
        }
        return environment
    }

    /// The bun read again from disk: Oven's Team ID, no quarantine.
    static func bunIsTrustedNow(_ bun: BunManager) -> Bool {
        let resolved = URL(fileURLWithPath: bun.path).resolvingSymlinksInPath()
        return BunManager(
            path: bun.path, signature: CLIToolTrust.signature(of: resolved, teamIdentifier: BunScanner.teamIdentifier),
            quarantined: CLIToolTrust.hasQuarantine(resolved)
        ).isTrusted
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
        if case .finished(let outcome) = result { CLIToolExit.report(command, outcome) }
        return CLIToolCommandRunner.Run(result: result, lines: log.lines)
    }

    // MARK: - Afterwards

    /// The specifier the global `package.json`'s `dependencies` gives `name`;
    /// nil when it cannot be read or names none.
    static func specifier(of name: String, in manifest: URL) -> String? {
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = json["dependencies"] as? [String: Any]
        else { return nil }
        return dependencies[name] as? String
    }

    /// What goes back over the exact `version` bun wrote, given the user's
    /// `specifier` from before; nil to leave bun's.
    ///
    /// - `^` and `~` move to the new version (`^6.0.0` → `^7.0.0`), as bun's own
    ///   `update --latest` rewrites them.
    /// - An exact version was the user's pin: the new exact one stays.
    /// - Any other range the new version satisfies (`*`, `>=1`, `1.x`) goes back
    ///   as written; one it does not satisfy would make bun's next install
    ///   resolve the package again, so bun's exact version stays.
    static func restoredSpecifier(_ specifier: String, at version: String) -> String? {
        let trimmed = specifier.trimmingCharacters(in: .whitespaces)
        guard trimmed != version, let installed = NpmVersion(version), let range = NpmRange(trimmed) else { return nil }
        if let first = trimmed.first, first == "^" || first == "~" { return "\(first)\(version)" }
        if NpmVersion(trimmed) != nil { return nil }
        return range.satisfies(installed) ? specifier : nil
    }

    /// Puts the user's style of specifier back for `name`, only where the entry
    /// reads exactly the `version` bun wrote, and only by editing that one value
    /// in place — the rest of the file stays byte for byte as bun left it. bun's
    /// `bun.lock` still names the exact version; its next install brings the lock
    /// in line without moving the package (measured, bun 1.4.3). A failure here
    /// leaves bun's exact version, which is the state before this existed.
    @discardableResult
    static func restoreSpecifier(_ specifier: String, of name: String, at version: String, in manifest: URL) -> Bool {
        guard let replacement = restoredSpecifier(specifier, at: version) else { return false }
        func json(_ string: String) -> String? {
            (try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        guard self.specifier(of: name, in: manifest) == version,
              let text = try? String(contentsOf: manifest, encoding: .utf8),
              let key = json(name), let value = json(version), let newValue = json(replacement),
              let regex = try? NSRegularExpression(
                pattern: "(" + NSRegularExpression.escapedPattern(for: key) + #"\s*:\s*)"#
                    + NSRegularExpression.escapedPattern(for: value))
        else { return false }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let range = Range(matches[0].range, in: text) else {
            Log.install.error("bun specifier: \(matches.count) matches for \(name, privacy: .public) in package.json, left as \(version, privacy: .public)")
            return false
        }
        let restored = text.replacingCharacters(
            in: range, with: regex.replacementString(
                for: matches[0], in: text, offset: 0, template: "$1" + NSRegularExpression.escapedTemplate(for: newValue)))
        do {
            try Data(restored.utf8).write(to: manifest, options: .atomic)
        } catch {
            Log.install.error("bun specifier: could not write \(manifest.path, privacy: .public): \(error)")
            return false
        }
        return self.specifier(of: name, in: manifest) == replacement
    }

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
    ///
    /// 2026.9's staged update ends differently: `⚠️ OpenClaw update failed:
    /// source-rollback-failed.`, a `Failed: <step> — <why>` line per failed step,
    /// then triage output whose last line is a command to run (a scratch-HOME run
    /// of 2026.9.7 → 2026.9.8 through bun, 2026-10-04). The headline's code and
    /// the first failed step are the reason.
    static func openclawReason(_ lines: [String]) -> String? {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        if let result = trimmed.lastIndex(where: { $0.hasPrefix("Update Result:") }),
           let reason = trimmed[result...].first(where: { $0.hasPrefix("Reason: ") }) {
            return "openclaw update: " + reason.dropFirst("Reason: ".count)
        }
        let marker = "OpenClaw update failed: "
        guard let headline = trimmed.lastIndex(where: { $0.contains(marker) }),
              let range = trimmed[headline].range(of: marker)
        else { return nil }
        var code = String(trimmed[headline][range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if code.hasSuffix(".") { code.removeLast() }
        let step = trimmed[headline...].first { $0.hasPrefix("Failed: ") }
            .flatMap { $0.dropFirst("Failed: ".count).components(separatedBy: " — ").first }
        return "openclaw update: \(code)" + (step.map { " (\($0) failed)" } ?? "")
    }
}
