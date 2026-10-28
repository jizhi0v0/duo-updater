import Foundation

/// One manager's items as one of the app's command-line tools: an adapter seen
/// through `CLIToolProvider`, so the app's scheduling, lanes, Update All,
/// announcements, rate-limit pause, `duo`'s `list`/`check`/`install` and the UI
/// see nothing new. One per adapter (`ManagerRegistry.providers`); all of
/// kind `.managed`, told apart by `id` ("managed:<manager>").
public struct ManagedProvider: CLIToolProvider {
    public var kind: CLIToolKind { .managed }
    public var id: String { adapter.descriptor.providerID }
    public var attributionName: String { adapter.descriptor.displayName }

    public let adapter: any ManagerAdapter
    let home: URL
    /// The proxy variables a GUI app lacks (`SystemProxyEnvironment`); the rest
    /// of the child's environment is built here, never inherited.
    let proxyEnvironment: @Sendable () -> [String: String]
    let processes: @Sendable () -> [NpmActivity.Process]
    let token: CLIToolGitHubToken.Source
    let runner: Runner
    /// How the vendor's command is run when it may be stopped (D15,
    /// `ManagerAdapter.interruption`). Production: `interruptibleRunner`.
    let stoppableRunner: Runner

    /// How the vendor's command is run. Production: `CLIToolCommandRunner.run`,
    /// with its commit point; a test's double answers without spawning.
    public typealias Runner = @Sendable (
        _ command: CLIToolCommand, _ environment: [String: String], _ workingDirectory: URL,
        _ deadline: ChildProcess.Deadline, _ progress: @escaping @Sendable (String) -> Void
    ) async -> RunResult

    public struct RunResult: Sendable, Equatable {
        public let succeeded: Bool
        /// The row's line when it failed (`CLIToolCommandRunner.failureMessage`'s rule).
        public let failureMessage: String?
        public let lines: [String]
        /// The command started and was stopped — by the caller's cancel or its
        /// deadline — and no process of it is left: what it changed may be
        /// put back.
        public let stopped: Bool
        /// The command was stopped, but some of its processes outlived the
        /// ladder: nothing may be put back under them.
        public let stuck: Bool
        /// The command exited by itself and some process it started is still
        /// running: a later cancel may not put anything back under it.
        public let leftovers: Bool

        public init(
            succeeded: Bool, failureMessage: String?, lines: [String], stopped: Bool = false, stuck: Bool = false,
            leftovers: Bool = false
        ) {
            self.succeeded = succeeded
            self.failureMessage = failureMessage
            self.lines = lines
            self.stopped = stopped
            self.stuck = stuck
            self.leftovers = leftovers
        }
    }

    public init(_ adapter: any ManagerAdapter, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(
            adapter, home: home,
            proxyEnvironment: { SystemProxyEnvironment.applied(to: [:]) },
            processes: { NpmActivity.runningProcesses() },
            token: CLIToolGitHubToken.app,
            runner: Self.commandRunner, stoppableRunner: Self.interruptibleRunner)
    }

    /// Every seam injected: what a test drives.
    public init(
        _ adapter: any ManagerAdapter, home: URL,
        proxyEnvironment: @escaping @Sendable () -> [String: String],
        processes: @escaping @Sendable () -> [NpmActivity.Process],
        token: @escaping @Sendable () async -> String?,
        runner: @escaping Runner,
        stoppableRunner: Runner? = nil
    ) {
        self.adapter = adapter
        self.home = home
        self.proxyEnvironment = proxyEnvironment
        self.processes = processes
        self.token = token
        self.runner = runner
        self.stoppableRunner = stoppableRunner ?? runner
    }

    /// `CLIToolCommandRunner.run`: stdout and stderr merged, the command's
    /// launch the commit point, run to completion once started.
    static let commandRunner: Runner = { command, environment, workingDirectory, deadline, progress in
        let run = await CLIToolCommandRunner.run(
            command, environment: environment, deadline: deadline, workingDirectory: workingDirectory, progress: progress)
        switch run.result {
        case .couldNotStart(let error):
            return RunResult(succeeded: false, failureMessage: "could not run \(command.executable): \(error)", lines: run.lines)
        case .finished(let outcome):
            guard !outcome.succeeded else { return RunResult(succeeded: true, failureMessage: nil, lines: run.lines) }
            let reason = CLIToolCommandRunner.failureMessage(run.lines, outcome, deadline: deadline)
            let message = outcome.timedOut || outcome.uncaughtSignal ? reason : "\(reason) (exit \(outcome.terminationStatus))"
            return RunResult(succeeded: false, failureMessage: message, lines: run.lines)
        }
    }

    /// D15: the vendor's command outside any commit, so a Cancel reaches it
    /// while it runs. A cancel sends SIGINT to its process group, as a
    /// terminal's Ctrl-C (`ManagedStop`); the run returns once no process of
    /// that group is left — never before, since the snapshot is put back
    /// under it. A deadline stops it the same way.
    static let interruptibleRunner: Runner = stoppableRunner()

    /// `interruptibleRunner` with the ladder's steps given: for a test.
    static func stoppableRunner(
        termAfter: Duration = ManagedStop.termAfter, killAfter: Duration = ManagedStop.killAfter,
        giveUpAfter: Duration = ManagedStop.giveUpAfter
    ) -> Runner { { command, environment, workingDirectory, deadline, progress in
        let log = CLIToolCommandRunner.OutputLog(onLine: progress)
        let stop = ManagedStop(termAfter: termAfter, killAfter: killAfter, giveUpAfter: giveUpAfter)
        guard !Task.isCancelled else {
            return RunResult(succeeded: false, failureMessage: "not run: cancelled", lines: [])
        }
        let outcome: ChildProcess.Outcome
        do {
            outcome = try await withTaskCancellationHandler {
                // `.runToCompletion`: the stop is ours (`ManagedStop`), sent to
                // every group of the child's session, and the call returns
                // only once the child has exited, cancelled caller or not.
                try await ChildProcess.run(
                    command.executable, command.arguments, environment: environment,
                    workingDirectory: workingDirectory, standardOutput: .discard, standardError: .mergeIntoOutput,
                    deadline: deadline, onCancel: .runToCompletion,
                    onOutputChunk: { log.append($0) }, onLaunch: { stop.launched($0) }, newSession: true)
            } onCancel: {
                stop.interrupt()
            }
        } catch {
            log.finish()
            stop.finish()
            return RunResult(succeeded: false, failureMessage: "could not run \(command.executable): \(error)", lines: log.lines)
        }
        log.finish()
        CLIToolExit.report(command, outcome)
        guard stop.wasInterrupted || outcome.timedOut else {
            let leftovers = await offCooperativePool { stop.alive() }
            stop.finish()
            return Self.result(outcome, log.lines, deadline, leftovers: leftovers)
        }
        // A deadline's SIGTERM reached the child alone; its group goes too.
        if outcome.timedOut { stop.interrupt() }
        let gone = await stop.waitUntilGone()
        let reason = outcome.timedOut
            ? CLIToolCommandRunner.failureMessage(log.lines, outcome, deadline: deadline) : "stopped"
        return RunResult(
            succeeded: false,
            failureMessage: gone ? reason : "\(reason); some of its processes are still running",
            lines: log.lines, stopped: gone, stuck: !gone)
    } }

    /// A run that ended by itself, as `commandRunner` words it.
    private static func result(
        _ outcome: ChildProcess.Outcome, _ lines: [String], _ deadline: ChildProcess.Deadline, leftovers: Bool
    ) -> RunResult {
        guard !outcome.succeeded else { return RunResult(succeeded: true, failureMessage: nil, lines: lines, leftovers: leftovers) }
        let reason = CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        let message = outcome.uncaughtSignal ? reason : "\(reason) (exit \(outcome.terminationStatus))"
        return RunResult(succeeded: false, failureMessage: message, lines: lines, leftovers: leftovers)
    }

    // MARK: - CLIToolProvider

    /// Disk only (`ManagerAdapter.scan`): one sighting per item, by identity.
    public func scan() async -> [CLIToolSighting] {
        await adapter.scan().sightings()
    }

    public func check() async -> CLIToolReport {
        let found = await adapter.scan()
        // The sightings stay the scan's own, so the next scan compares equal
        // to this report while the disk is unchanged (`CLIToolsModel.onOpen`).
        var scan = found
        if !found.items.isEmpty { scan = await adapter.resolve(found) }
        let context = CLIToolReport.Context.managed(ManagerContext(descriptor: adapter.descriptor, roots: scan.roots))
        guard !scan.items.isEmpty else {
            return CLIToolReport(kind: .managed, statuses: [], context: context, sightings: [])
        }
        let verdicts = await adapter.check(scan)
        let statuses = verdicts.map { verdict in
            let root = scan.root(of: verdict.item)
            return ManagedCheck.status(
                verdict, root: root,
                upgrade: root.flatMap { adapter.upgrade(verdict.item, root: $0)?.command },
                unpin: root.flatMap { adapter.unpin(verdict.item, root: $0) })
        }
        return CLIToolReport(kind: .managed, statuses: statuses, context: context, sightings: found.sightings())
    }

    /// Runs `status.oneClick` — the adapter's upgrade command — and nothing
    /// else, re-asking every gate that can change between the check and the
    /// click: the item still there at the version checked, its root's binary
    /// still runnable, the manager not already moving it.
    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .managed(let checked) = status.detail else { return .notOffered }
        let scan = await adapter.scan()
        guard let item = await adapter.current(checked, in: scan) else {
            return .failed(message: "not run: \(checked.name) is no longer under \(checked.root)", output: "")
        }
        guard item.installed == checked.installed else {
            return .failed(
                message: "not run: \(item.name) is \(item.installed ?? "unreadable") now, not the \(checked.installed ?? "unreadable") that was checked",
                output: "")
        }
        guard let root = scan.root(of: item), root.runnable else {
            return .failed(message: "not run: \(adapter.descriptor.displayName)'s program under \(item.root) may no longer be run", output: "")
        }
        guard let upgrade = adapter.upgrade(item, root: root), upgrade.command == command else {
            return .failed(message: "not run: \(item.name)'s update command is no longer the one that was checked", output: "")
        }
        let processes = self.processes
        let busy = await offCooperativePool { adapter.busy(item, root: root, processes: processes()) }
        if let busy { return .busy(busy) }

        var environment = proxyEnvironment()
        environment["HOME"] = home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        environment["NO_COLOR"] = "1"
        for (key, value) in upgrade.environment { environment[key] = value }
        let deadline = adapter.descriptor.deadline
        let directory = adapter.workingDirectory(home: home)
        // D15: an upgrade whose writes are known runs where a Cancel reaches
        // it, over a snapshot of them; any other runs to completion. A
        // snapshot that cannot be taken (no clones on that volume) means the
        // latter, as before D15.
        var snapshot: ManagedSnapshot?
        let plan = adapter.interruption(item, root: root)
        if let plan {
            do {
                snapshot = try ManagedSnapshot.take(plan.paths, created: plan.created)
            } catch {
                Log.install.notice("managed \(item.identity, privacy: .public): no snapshot (\(String(describing: error), privacy: .public)); runs to completion")
            }
        }
        if let taken = snapshot {
            Log.install.info("managed \(item.identity, privacy: .public): snapshot of \(taken.entries.count, privacy: .public) paths in \(taken.directory, privacy: .public)")
        }
        // Kept when a stop could not end every process: the state before the
        // update is then the user's only way back, and the row names it.
        var keepSnapshot = false
        defer { if !keepSnapshot { snapshot?.discard() } }
        let run = { [runner, stoppableRunner] (environment: [String: String]) async -> RunResult in
            await (snapshot == nil ? runner : stoppableRunner)(command, environment, directory, deadline, progress)
        }
        var result = await run(environment)
        // mise's handoff, shared (`ManagedTokenRetry`): once more with the
        // app's token, only after the vendor said it found none of its own.
        // Not after a stop of any kind: a stuck one's snapshot is the way back.
        // Not while the first run's processes still run either: a stop of
        // the second would put back under them (local adversarial review).
        if !result.stopped, !result.stuck, !result.leftovers, let retry = adapter.tokenRetry, retry.applies(failed: !result.succeeded, lines: result.lines) {
            if let token = await token() {
                environment[retry.variable] = token
                result = await run(environment)
            } else if Task.isCancelled {
                // The row's Cancel cut the token lookup short: the retry it
                // would have started is what the click stopped
                // (`InstallJobs.cancelStoppedSomething`).
                InstallJobs.noteRefusedCommit(InstallJobs.currentID)
            }
        }
        if result.stopped, let snapshot {
            return Self.putBack(snapshot, result, manager: adapter.descriptor.displayName, identity: item.identity)
        }
        if result.stuck, let snapshot {
            keepSnapshot = true
            let message = "\(result.failureMessage ?? "stopped"), so nothing was put back; "
                + "what was there before is kept in \(snapshot.directory)"
            Log.install.error("managed \(item.identity, privacy: .public): \(message, privacy: .public)")
            return .stopped(message: message, output: result.lines.joined(separator: "\n"), complete: false)
        }
        guard result.succeeded else {
            return .failed(message: result.failureMessage ?? "\(adapter.descriptor.displayName): the update failed",
                           output: result.lines.joined(separator: "\n"))
        }
        if let snapshot {
            let result = result
            // Done: from here the update is the result (`InstallCommit`), and
            // the row's Cancel greys. A cancel that came first still applies,
            // and puts it back like a stop.
            do {
                return try await InstallCommit.run("\(adapter.descriptor.displayName) update") {
                    await self.settled(item, result)
                }
            } catch {
                // A cancel that came before the result was taken. Put back —
                // unless something the command started still runs, which could
                // write under the put-back (review): then the update stands,
                // the snapshot is kept, and the row says so.
                if result.leftovers {
                    keepSnapshot = true
                    let message = "\(adapter.descriptor.displayName) had finished and some of its processes were still running, "
                        + "so nothing was put back; what was there before is kept in \(snapshot.directory)"
                    Log.install.error("managed \(item.identity, privacy: .public): \(message, privacy: .public)")
                    return .stopped(message: message, output: result.lines.joined(separator: "\n"), complete: false)
                }
                return Self.putBack(snapshot, result, manager: adapter.descriptor.displayName, identity: item.identity)
            }
        }
        return await settled(item, result)
    }

    /// The stopped command's changes put back (`ManagedSnapshot.restore`).
    static func putBack(
        _ snapshot: ManagedSnapshot, _ result: RunResult, manager: String, identity: String
    ) -> CLIToolUpdateOutcome {
        let failed = snapshot.restore()
        let reason = result.failureMessage ?? "stopped"
        let message = failed.isEmpty
            ? "\(reason); \(manager)'s changes were put back"
            : "\(reason); could not put back: \(failed.joined(separator: "; "))"
        Log.install.notice("managed \(identity, privacy: .public): \(message, privacy: .public)")
        return .stopped(message: message, output: result.lines.joined(separator: "\n"), complete: failed.isEmpty)
    }

    /// What the command left, re-read: the updater's own verdict.
    private func settled(_ item: ManagedItem, _ run: RunResult) async -> CLIToolUpdateOutcome {
        let version = await adapter.reread(item)
        // A run that ended well but moved nothing is not an update: mise, with
        // its versions host off and GitHub refusing, printed "All tools are up
        // to date" and exited 0 with aqua's jq still 1.6 (2026-10-24, §12 item 2).
        // The row keeps its update and its button, and says why.
        if let version, let installed = item.installed, version == installed {
            return .failed(
                message: "not updated: \(item.name) is still \(installed); \(adapter.descriptor.displayName) finished without installing a newer version",
                output: run.lines.joined(separator: "\n"))
        }
        return .updated(version: version)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        guard case .managed(let item) = status.detail else { return Changelog(entries: []) }
        return try await adapter.releaseNotes(for: item, force: force)
    }
}
