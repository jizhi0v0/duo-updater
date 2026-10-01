import Foundation

/// Runs the one-click update a bub status offers — `bub update bub`, by the
/// install's own `bin/bub` — and reports how it went.
///
/// It runs exactly `status.oneClick`, never a command of its own: which command
/// is allowed for which install is `BubCheck`'s decision. The one gate asked
/// again here is "is something already changing this venv", because that one
/// can change between the check and the click.
///
/// Measured end to end on 2026-10-01 in a scratch HOME (bub 0.4.4 installed the
/// way the official installer does, uv 0.9.18 at `~/.local/bin/uv`, a
/// launchd-like environment plus the system proxy, `PATH` built as below):
/// - with no `~/.bub/bub-project`, `bub update bub` created it (`uv init`, then
///   `uv add --active --no-sync bub`), synced and moved bub 0.4.4 → 0.5.0, exit 0;
/// - with a plugin in the project (`bub-web-search` 0.0.2, 0.1.0 available on
///   PyPI), bub went 0.4.4 → 0.5.0 and the plugin stayed at 0.0.2. The one other
///   package that moved was `inquirer-textual` 0.6.1 → 0.8.1, which bub 0.5.0
///   requires (`>=0.8.0`).
public struct BubUpdater: Sendable {

    /// Is something already changing this venv? Injected so tests never read the
    /// host's process table.
    typealias BusyCheck = @Sendable (BubInstall) -> BubActivity.Busy?

    let busy: BusyCheck
    /// Re-reads the install after a successful run.
    let scanner: BubScanner
    /// The child's environment before `PATH` is set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// `bub update bub` downloads bub's wheel (175 KB for 0.5.0) and whatever new
    /// dependencies the release needs; a first run also resolves the whole
    /// project (62 packages, ~1.4 s, measured). Minutes only on a link that has
    /// stopped making progress, so 15 of them is a hang, not a slow download.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(15 * 60), killAfter: .seconds(15 * 60 + 30))

    public init() {
        self.init(
            busy: { BubActivity.busy($0, processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: BubScanner(),
            // A GUI app launched by launchd has no proxy variables, and uv reads
            // them: through an unresolvable `https_proxy` the sync failed on
            // `https://pypi.org/simple/bub/` with "dns error" (measured
            // 2026-10-01), so it does use them. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: BubScanner,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = BubUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.environment = environment
        self.deadline = deadline
    }

    /// - Parameter progress: each new line of the command's output, as it arrives.
    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .bub(let install) = status.detail else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running.description)
        }

        var environment = self.environment()
        // The uv `BubCheck` found, first: bub's `_find_uv` falls back to `PATH`
        // for a uv outside the venv and `~/.local/bin`.
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        let run = await CLIToolCommandRunner.run(
            command, environment: environment, deadline: deadline, progress: progress)
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
        let scanner = self.scanner
        let after = await offCooperativePool { scanner.install(at: URL(fileURLWithPath: install.path), method: install.method) }
        // Exit 0 is not proof that bub moved. A project left without bub (see
        // `BubInstall.Project.missingBub`) syncs nothing and exits 0, and so does
        // a plugin that caps bub below the release. Reporting "updated" to the
        // version it already had would read as success on a row that will offer
        // the same update again.
        if let before = install.version, let now = after?.version,
           VersionComparator.compare(before, now) == .orderedSame {
            return .failed(message: "bub update bub finished, but bub is still \(now)", output: run.text)
        }
        return .updated(version: after?.version)
    }

    /// The line the row shows when the command failed.
    ///
    /// bub runs uv and, when uv fails, ends with its own wrapper — `Command 'uv
    /// sync --active --inexact --upgrade-package bub' failed with exit code 2.` —
    /// which says which step failed but not why, so it is the reason only when
    /// nothing else is. The why is uv's, in one of two
    /// shapes (uv 0.9.18, measured 2026-10-01):
    ///
    ///     error: Failed to fetch: `https://pypi.org/simple/bub/`
    ///       Caused by: Request failed after 3 retries
    ///       …
    ///       Caused by: dns error
    ///       Caused by: failed to lookup address information: nodename nor servname provided, or not known
    ///
    /// where the last `Caused by:` is the root cause, and a resolver diagnostic,
    /// wrapped at 80 columns:
    ///
    ///       × No solution found when resolving dependencies:
    ///       ╰─▶ Because only bub<=0.5.0 is available and your project depends on bub>99,
    ///           we can conclude that your project's requirements are unsatisfiable.
    ///
    /// where the `╰─▶` cause and its continuation lines are the reason. Anything
    /// else falls to the last line with a letter in it — which for a missing uv
    /// is the line after Python's traceback box, `FileNotFoundError: uv
    /// executable not found in PATH or scripts directory.` (exit 1).
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if outcome.timedOut {
            return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        }
        let reasons = lines.filter { !isBubWrapper($0) }
        if let cause = reasons.last(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(causedBy) }) {
            return String(cause.trimmingCharacters(in: .whitespaces).dropFirst(causedBy.count))
        }
        if let diagnostic = resolverCause(reasons) { return diagnostic }
        if let error = reasons.last(where: { $0.hasPrefix("error: ") }) {
            return String(error.dropFirst("error: ".count))
        }
        // The wrapper still beats a bare exit status when uv said nothing else.
        let fallback = reasons.contains(where: CLIToolCommandRunner.isMeaningful) ? reasons : lines
        return CLIToolCommandRunner.failureMessage(fallback, outcome, deadline: deadline)
    }

    static let causedBy = "Caused by: "

    /// `Command 'uv …' failed with exit code N.`, which `bub` prints after uv's
    /// own error (`_uv` in `bub/builtin/cli.py`).
    static func isBubWrapper(_ line: String) -> Bool {
        line.range(of: #"^Command 'uv .*' failed with exit code \d+\.$"#, options: .regularExpression) != nil
    }

    /// The last `╰─▶` cause with the lines wrapped under it, joined.
    static func resolverCause(_ lines: [String]) -> String? {
        guard let start = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("╰─▶") })
        else { return nil }
        let indent = lines[start].prefix { $0 == " " }.count
        var parts = [lines[start].trimmingCharacters(in: .whitespaces).dropFirst("╰─▶".count)
            .trimmingCharacters(in: .whitespaces)]
        for line in lines[(start + 1)...] {
            guard line.prefix(while: { $0 == " " }).count > indent else { break }
            parts.append(line.trimmingCharacters(in: .whitespaces))
        }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
