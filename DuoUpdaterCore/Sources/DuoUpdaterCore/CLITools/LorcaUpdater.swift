import Foundation

/// Runs the one-click update a Lorca status offers — `<binary> update`, Lorca's
/// own command on the install's own file — and checks what it left.
///
/// Asked again here, because each can change between the check and the click:
/// - a change already running (`LorcaActivity`);
/// - the install: the same path and file, the version that was checked, a
///   folder it can write to, not quarantined, `auto_update` still on, and byte
///   for byte its version's published build (`LorcaVerifier`, which downloads
///   that release's archive here the first time);
/// - the signed manifest, which must still name a version newer than the file.
///
/// `lorca update` works one of two ways (`main.rs`, `update`, at cli-v0.1.11):
/// - **No `lorca serve` answers** on its port: it installs here, over this
///   binary, and prints `Installed lorca <version>.` once the file is in place.
/// - **A `lorca serve` answers**: it asks it to (`device.update`) and exits at
///   once with `Installing lorca <version>; lorca serve restarts into it once no
///   bot is at work.` The serve downloads, checks and renames the file itself a
///   moment later: its `check` runs `put_in_place` (download, verify, rename)
///   before it spawns `restart_when_idle`, so a serve whose bots are busy holds
///   back only its own restart, not the file. So when the output says so, the
///   file is watched until it reads newer, for up to `settle`.
///
/// After it ran, the same rule is asked of what it left: a version newer than
/// the one it replaced, byte for byte that version's published build. Anything
/// else is a failure, not "updated".
public struct LorcaUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> LorcaActivity.Busy?

    let busy: BusyCheck
    let scanner: LorcaScanner
    let check: LorcaCheck
    let verifier: LorcaVerifier
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline
    /// How long a `lorca serve` that took the update may take to put the file in place.
    let settle: Duration
    let pollInterval: Duration
    let isListening: @Sendable (Int) -> Bool

    /// The arm64 archive is 17.8 MB (0.1.11), fetched with a 15-minute timeout of
    /// lorca's own. The deadline is for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// `LORCA_DOWNLOAD_URL` stands for the releases page in `lorca update` as in
    /// the install script, `LORCA_HOME` moves its settings and `LORCA_PORT` the
    /// serve it hands the update to: a
    /// terminal-run `duo` may carry them, a GUI app has none, and the check
    /// read neither.
    static let overrides = ["LORCA_DOWNLOAD_URL", "LORCA_HOME", "LORCA_PORT"]

    /// What `lorca update` prints when it handed the work to a running `lorca serve`.
    static let handedToServe = "lorca serve restarts into it"

    public init() {
        self.init(
            busy: { LorcaActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: LorcaScanner(),
            check: LorcaCheck(),
            verifier: LorcaVerifier(),
            // lorca's HTTP client reads the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: LorcaScanner,
        check: LorcaCheck,
        verifier: LorcaVerifier,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = LorcaUpdater.defaultDeadline,
        settle: Duration = .seconds(5 * 60),
        pollInterval: Duration = .seconds(1),
        isListening: @escaping @Sendable (Int) -> Bool = LorcaCheck.isListening
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.verifier = verifier
        self.environment = environment
        self.deadline = deadline
        self.settle = settle
        self.pollInterval = pollInterval
        self.isListening = isListening
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .lorca(let install) = status.detail,
              let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.reread(install.path) }), now.problem == nil,
              now.version == before, let binary = now.binary, binary == command.executable,
              now.hasUpdateCommand, let target = now.target, !now.quarantined
        else {
            return .failed(message: "not run: \(install.path) is no longer the lorca that was checked", output: "")
        }
        guard now.writable else {
            return .failed(message: "not run: lorca update cannot write beside \(binary)", output: "")
        }
        guard now.autoUpdate else {
            return .failed(message: "not run: auto_update is now off in ~/.lorca/settings.json", output: "")
        }
        // Never toward an older version: what `lorca update` installs is what the
        // manifest names now.
        do {
            let newest = try await check.latest().version
            guard VersionComparator.compare(before, newest) == .orderedAscending else {
                return .failed(message: "not run: lorca-cli.json now names \(newest), not a version newer than \(before)",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read lorca-cli.json: \(error)", output: "")
        }

        // The trust rule, at the click.
        progress("Checking \(binary) against lorca \(before) as Lorca published it…")
        switch await verifier.verify(binary: binary, version: before, target: target) {
        case .matches:
            break
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }
        // Asked again: the check above may have downloaded an archive, long
        // enough for a `lorca update` started in a terminal to be under way.
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        // The port the check named to get past the Mac app's `lorca serve` must
        // still have nothing on it: whatever answered there would be handed the update.
        if let port = LorcaActivity.port(of: [binary] + command.arguments), port != LorcaActivity.defaultPort {
            let isListening = self.isListening
            if await offCooperativePool({ isListening(port) }) {
                return .failed(message: "not run: something now listens on port \(port)", output: "")
            }
        }

        var environment = self.environment()
        for key in Self.overrides { environment[key] = nil }
        // lorca's folder is `$HOME/.lorca`: the one the scanner read the setting from.
        environment["HOME"] = scanner.home.path
        environment["PATH"] = CLIToolCommandRunner.systemPath
        let run = await CLIToolCommandRunner.run(command, environment: environment, deadline: deadline, progress: progress)
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

        var after = await offCooperativePool({ scanner.reread(install.path) })
        if after?.version == before, run.text.contains(Self.handedToServe) {
            progress("lorca serve is installing it…")
            let clock = ContinuousClock()
            let end = clock.now.advanced(by: settle)
            while after?.version == before, clock.now < end {
                try? await Task.sleep(for: pollInterval)
                after = await offCooperativePool({ scanner.reread(install.path) })
            }
        }

        // The trust rule again, on the file the update left.
        guard let after, after.problem == nil, let version = after.version, let newBinary = after.binary,
              let newTarget = after.target
        else {
            return .failed(message: "lorca update finished, but \(install.path) no longer reads as lorca", output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still lorca \(version)" : "went from lorca \(before) to \(version)"
            return .failed(message: "lorca update finished, but \(install.path) \(what)", output: run.text)
        }
        switch await verifier.verify(binary: newBinary, version: version, target: newTarget) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "lorca update finished, but \(reason)", output: run.text)
        }
    }

    /// The line the row shows when `lorca update` failed: its `Error: <what>`
    /// line (anyhow's report from `main`); anything else falls to the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        LuvusUpdater.failureMessage(lines, outcome, deadline: deadline)
    }
}
