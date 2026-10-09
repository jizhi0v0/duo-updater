import Foundation

/// Runs the one-click update a flyctl status offers — `<binary> version upgrade`,
/// flyctl's own command on the install's own file — and checks what it left.
///
/// Asked again at the click: a change already running (`FlyctlActivity`); the
/// install — the same file and version, writable, not quarantined, auto-update
/// still on, byte for byte its version's published build (`FlyctlVerifier`,
/// which downloads that release's archive here the first time); and the
/// `latest` track, which must still name a newer version.
///
/// What `flyctl version upgrade` does (`internal/command/version/upgrade.go`,
/// `internal/update/update.go`): it reads the track itself, refuses a binary
/// outside `$FLYCTL_INSTALL` ("cannot update this installation"), then runs
/// `$SHELL -c 'curl -L "https://fly.io/install.sh" | sh'` and finally the new
/// `flyctl version --json`. Before any of that it looks for `brew` on `PATH`
/// to tell a Homebrew install. So the child gets:
/// - `FLYCTL_INSTALL` = the scanned `~/.fly`, and `HOME` = the scanned home,
///   so the installer writes where the scan reads;
/// - `SHELL` = `/bin/sh`, and a `PATH` of a private directory holding only the
///   programs the installer runs (no `sudo`, no `brew`) and a `flyctl` link
///   to the install — with `flyctl` found on `PATH`, the installer skips its
///   shell-profile step;
/// - empty stdin; its stdout is a pipe, so the installer never asks.
///
/// Neither the installer nor flyctl checks the archive's hash, and both run the
/// new binary before this updater looks at it; it is then held to the trust rule
/// like any result: a newer version, byte for byte that version's published build.
public struct FlyctlUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> FlyctlActivity.Busy?

    let busy: BusyCheck
    let scanner: FlyctlScanner
    let check: FlyctlCheck
    let verifier: FlyctlVerifier
    let environment: @Sendable () -> [String: String]
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 archive is ~35 MB, fetched with `curl --retry 5` and no stall
    /// timeout of its own: the deadline is for a child that hangs.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// What `install.sh` runs, and the `sh` that runs it.
    static let defaultTools = [
        "sh": "/bin/sh", "curl": "/usr/bin/curl", "tar": "/usr/bin/tar", "uname": "/usr/bin/uname",
        "mkdir": "/bin/mkdir", "chmod": "/bin/chmod", "mv": "/bin/mv", "rm": "/bin/rm", "ln": "/bin/ln",
        "grep": "/usr/bin/grep",
    ]

    public init() {
        self.init(
            busy: { FlyctlActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: FlyctlScanner(),
            check: FlyctlCheck(),
            verifier: FlyctlVerifier(),
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: FlyctlScanner,
        check: FlyctlCheck,
        verifier: FlyctlVerifier,
        environment: @escaping @Sendable () -> [String: String],
        tools: [String: String] = FlyctlUpdater.defaultTools,
        deadline: ChildProcess.Deadline = FlyctlUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.verifier = verifier
        self.environment = environment
        self.tools = tools
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .flyctl(let install) = status.detail,
              let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.scan().first }), now.path == install.path,
              now.problem == nil, now.version == before, let binary = now.binary, binary == command.executable,
              let target = now.target, !now.quarantined, !now.followsPrerelease
        else {
            return .failed(message: "not run: \(install.path) is no longer the flyctl that was checked", output: "")
        }
        guard now.autoUpdate else { return .notOffered }
        guard now.writable else {
            return .failed(message: "not run: ~/.fly/bin is not writable", output: "")
        }
        do {
            let newest = try await check.latest(target)
            guard VersionComparator.compare(before, newest) == .orderedAscending else {
                return .failed(message: "not run: flyctl's latest release is now \(newest), not newer than \(before)",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read flyctl's latest release: \(error)", output: "")
        }

        progress("Checking \(binary) against flyctl \(before) as Fly.io published it…")
        switch await verifier.verify(binary: binary, version: before, target: target) {
        case .matches:
            break
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }

        let tools = self.tools.merging(["flyctl": binary]) { _, link in link }
        let toolsDirectory: URL
        do {
            toolsDirectory = try await offCooperativePool { try LuvusUpdater.makeToolsDirectory(tools) }
        } catch {
            return .failed(message: "not run: could not prepare the update’s PATH: \(error)", output: "")
        }
        defer { try? FileManager.default.removeItem(at: toolsDirectory) }

        var environment = self.environment()
        environment["HOME"] = scanner.home.path
        environment["FLYCTL_INSTALL"] = scanner.installDirectory
        environment["SHELL"] = "/bin/sh"
        environment["PATH"] = toolsDirectory.path
        let run = await CLIToolCommandRunner.run(
            command, environment: environment, deadline: deadline, standardInput: Data(), progress: progress)
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

        guard let after = await offCooperativePool({ scanner.scan().first }), after.problem == nil,
              let version = after.version, let newBinary = after.binary, let newTarget = after.target
        else {
            return .failed(message: "flyctl version upgrade finished, but \(install.path) no longer reads as flyctl",
                           output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            return .failed(message: "flyctl version upgrade finished, but \(install.path) is still flyctl \(version)",
                           output: run.text)
        }
        switch await verifier.verify(binary: newBinary, version: version, target: newTarget) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "flyctl version upgrade finished, but \(reason)", output: run.text)
        }
    }

    /// flyctl's own `Error: <what>` line (its root command prints errors so; the
    /// installer's are `Error: …` too), else the shared rule; with the exit
    /// status, so the row says how the command ended as well as why.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let line = lines.last(where: { $0.hasPrefix("Error: ") }) {
            return HelmUpdater.withStatus(String(line.dropFirst("Error: ".count)), outcome)
        }
        return HelmUpdater.withStatus(CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline), outcome)
    }
}
