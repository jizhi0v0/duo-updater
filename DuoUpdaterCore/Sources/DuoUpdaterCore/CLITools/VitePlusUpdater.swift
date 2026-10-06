import Foundation

/// Runs the one-click update a Vite+ status offers — `vp upgrade <version>`,
/// Vite+'s own command on the install's own binary — and checks what it left.
///
/// Asked again here, because each can change between the check and the click:
/// - a change already running (`VitePlusActivity`);
/// - the install: the same root, version and binary, not shadowed, not
///   quarantined, and trusted — found byte for byte its version's npm package
///   (`VitePlusVerifier`, which downloads that package here, the first time);
/// - `vite-plus@latest`, which must still name the version the click pins.
///
/// After it ran, the same rule is asked of what it left: `current` must be the
/// pinned version, and its `vp` byte for byte that version's package. Anything
/// else is a failure, not "updated".
///
/// Measured 2026-10-06 in scratch HOMEs, with only `/usr/bin:/bin` on `PATH`:
/// 0.3.3 (split) and 0.2.9 (single root) each went to 1.0.0 with `vp upgrade
/// 1.0.0` in 9 s, printing `✓ Updated vite-plus from 0.3.3 → 1.0.0`. It
/// rewrote only its own `env` files and shims under its roots — no shell
/// profile — and left the old version beside the new for `--rollback`.
public struct VitePlusUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> VitePlusActivity.Busy?

    let busy: BusyCheck
    let scanner: VitePlusScanner
    let check: VitePlusCheck
    let verifier: VitePlusVerifier
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The platform package is ~4.5 MB, and `vp upgrade` then has pnpm install
    /// `vite-plus` and its dependencies. The deadline is for a child that hangs,
    /// not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// What would point `vp upgrade` at another root or registry than the ones
    /// checked: a terminal-run `duo` may carry them, a GUI app has none.
    static let overrides = [
        "VP_HOME", "VP_BIN_DIR", "VP_DATA_DIR", "VP_CACHE_DIR",
        "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME",
        "NPM_CONFIG_REGISTRY", "npm_config_registry",
    ]

    public init() {
        let scanner = VitePlusScanner()
        self.init(
            busy: { VitePlusActivity.busy(processes: NpmActivity.runningProcesses()) },
            scanner: scanner,
            check: VitePlusCheck(),
            verifier: VitePlusVerifier(),
            // `vp` and the pnpm it runs read the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: VitePlusScanner,
        check: VitePlusCheck,
        verifier: VitePlusVerifier,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = VitePlusUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.verifier = verifier
        self.environment = environment
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .vitePlus(let install) = status.detail,
              let before = install.version, let target = command.arguments.last
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.reread(install) }), now.problem == nil,
              now.version == before, let binary = now.binary, binary == command.executable,
              let platform = now.platform, !now.quarantined
        else {
            return .failed(message: "not run: \(install.path) is no longer the Vite+ that was checked", output: "")
        }
        let latest: String
        do {
            latest = try await check.latest()
        } catch {
            return .failed(message: "not run: could not read vite-plus@latest: \(error)", output: "")
        }
        guard latest == target, VersionComparator.compare(before, target) == .orderedAscending else {
            return .failed(message: "not run: vite-plus@latest is now \(latest), not \(target)", output: "")
        }

        // The trust rule, at the click.
        switch now.hashVerdict {
        case .matches?:
            break
        case .differs?:
            return .failed(message: "not run: \(binary) is not the vp VoidZero published for \(before)", output: "")
        case nil:
            progress("Checking \(binary) against vite-plus \(before) as npm publishes it…")
            switch await verifier.verify(binary: binary, version: before, platform: platform) {
            case .matches:
                break
            case .differs(let reason), .couldNotVerify(let reason):
                return .failed(message: "not run: \(reason)", output: reason)
            }
        }
        // Asked again: the check above downloads a package, long enough for a
        // `vp upgrade` started in a terminal to be under way.
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }

        var environment = self.environment()
        for key in Self.overrides { environment[key] = nil }
        environment["HOME"] = scanner.home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        environment["NO_COLOR"] = "1"
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

        // The trust rule again, on the file the update left.
        guard let after = await offCooperativePool({ scanner.reread(install) }), after.problem == nil,
              let version = after.version, let newBinary = after.binary, let newPlatform = after.platform
        else {
            return .failed(message: "vp upgrade finished, but \(install.path) no longer reads as Vite+", output: run.text)
        }
        guard version == target else {
            return .failed(message: "vp upgrade finished, but Vite+ is \(version), not \(target)", output: run.text)
        }
        switch await verifier.verify(binary: newBinary, version: version, platform: newPlatform) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "vp upgrade finished, but \(reason)", output: run.text)
        }
    }

    /// The line the row shows when `vp upgrade` failed: its own `error: <what>`
    /// (`vp_shared::output::error`), without the prefix; anything else falls to
    /// the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let error = lines.last(where: { $0.hasPrefix("error: ") }) {
            return String(error.dropFirst("error: ".count))
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
