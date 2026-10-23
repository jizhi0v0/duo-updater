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

        public init(succeeded: Bool, failureMessage: String?, lines: [String]) {
            self.succeeded = succeeded
            self.failureMessage = failureMessage
            self.lines = lines
        }
    }

    public init(_ adapter: any ManagerAdapter, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(
            adapter, home: home,
            proxyEnvironment: { SystemProxyEnvironment.applied(to: [:]) },
            processes: { NpmActivity.runningProcesses() },
            token: CLIToolGitHubToken.app,
            runner: Self.commandRunner)
    }

    /// Every seam injected: what a test drives.
    public init(
        _ adapter: any ManagerAdapter, home: URL,
        proxyEnvironment: @escaping @Sendable () -> [String: String],
        processes: @escaping @Sendable () -> [NpmActivity.Process],
        token: @escaping @Sendable () async -> String?,
        runner: @escaping Runner
    ) {
        self.adapter = adapter
        self.home = home
        self.proxyEnvironment = proxyEnvironment
        self.processes = processes
        self.token = token
        self.runner = runner
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
        var run = await runner(command, environment, directory, deadline, progress)
        // mise's handoff, shared (`ManagedTokenRetry`): once more with the
        // app's token, only after the vendor said it found none of its own.
        if let retry = adapter.tokenRetry, retry.applies(failed: !run.succeeded, lines: run.lines) {
            if let token = await token() {
                environment[retry.variable] = token
                run = await runner(command, environment, directory, deadline, progress)
            } else if Task.isCancelled {
                // The row's Cancel cut the token lookup short: the retry it
                // would have started is what the click stopped
                // (`InstallJobs.cancelStoppedSomething`).
                InstallJobs.noteRefusedCommit(InstallJobs.currentID)
            }
        }
        guard run.succeeded else {
            return .failed(message: run.failureMessage ?? "\(adapter.descriptor.displayName): the update failed",
                           output: run.lines.joined(separator: "\n"))
        }
        return .updated(version: await adapter.reread(item))
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        guard case .managed(let item) = status.detail else { return Changelog(entries: []) }
        return try await adapter.releaseNotes(for: item, force: force)
    }
}
