import Foundation

/// Runs the one-click update a uv status offers — `<dir>/uv self update`, uv's
/// own command on its own file — and reports how it went.
///
/// It runs exactly `status.oneClick`; whether one is offered is `UvCheck`'s
/// decision. Asked again here, because each can change between the check and
/// the click:
/// - an update already running (`UvActivity`);
/// - the file and its receipt: still the standalone copy the receipt names, no
///   quarantine flag, and trusted — signed by Astral's Team, or found byte for
///   byte the published release (`UvVerifier`, which downloads that release
///   here, at the click, the first time an unsigned copy is updated).
///
/// After it ran, the same rule is asked of what it left: the new `uv` and `uvx`
/// must carry Astral's Team ID (every release from 0.12.12 does, and the
/// newest release is what `self update` installs), and the version they report
/// must be the one the rewritten receipt names. Anything else is a failure, not
/// "updated".
///
/// Measured end to end on 2026-10-02 in a scratch HOME (uv 0.9.18 installed by
/// its own `install.sh`, receipt `modify_path: true`, the profile lines that
/// install wrote removed first), driven through this type with the app's
/// environment: the click downloaded the 0.9.18 archive and found `uv` and
/// `uvx` byte for byte the release, then `uv self update` printed
///
///     info: Checking for updates...
///     success: Upgraded uv from v0.9.18 to v0.12.21! https://github.com/astral-sh/uv/releases/tag/0.12.21
///
/// and exited 0 after 6 s. Both files were new inodes signed by Team
/// `2DC432GLL2`, the receipt said 0.12.21 (and cargo-dist 0.32.0), and no shell
/// profile was created — the installer saw its directory on `PATH`. uv 0.9.18
/// itself asks `api.github.com/repos/astral-sh/uv/releases` (axoupdater) rather
/// than the versions manifest uv 0.12 reads.
public struct UvUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> UvActivity.Busy?

    let busy: BusyCheck
    /// Re-reads the install before the run and after it.
    let scanner: UvScanner
    let verifier: UvVerifier
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The archive is ~17 MB (0.12.21 arm64: 17,001,427 bytes) and the installer
    /// fetches it with curl; ten minutes is ~230 kbit/s for the whole file. The
    /// deadline is for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    public init() {
        self.init(
            busy: { UvActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: UvScanner(),
            verifier: UvVerifier(),
            // uv and the installer's curl both read the proxy variables, which a
            // GUI app launched by launchd does not have. See
            // `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: UvScanner,
        verifier: UvVerifier,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = UvUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.verifier = verifier
        self.environment = environment
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .uv(let install) = status.detail else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        guard let current = await scanner.reread(install), current.layout == .standalone, !current.quarantined,
              current.path == command.executable
        else {
            return .failed(
                message: "not run: \(install.path) is no longer the standalone uv that was checked", output: "")
        }
        // The trust rule, at the click.
        if current.isVendorSigned {
            guard current.version != nil, current.version == current.receiptVersion else {
                return .failed(message: "not run: \(install.path) no longer reads as the uv its receipt names",
                               output: "")
            }
        } else if current.needsHash {
            guard let receipt = current.receiptVersion,
                  VersionComparator.compare(receipt, UvScanner.firstSignedVersion) == .orderedAscending
            else {
                return .failed(message: "not run: \(install.path) is not signed by Astral", output: "")
            }
            switch current.hashVerdict {
            case .matches:
                break
            case .differs:
                return .failed(
                    message: "not run: \(install.path) is not byte for byte the uv \(receipt) Astral published",
                    output: "")
            case nil:
                progress("Checking \(install.path) against uv \(receipt) as Astral published it…")
                switch await verifier.verify(current) {
                case .matches:
                    break
                case .differs(let reason):
                    return .failed(message: "not run: \(reason)", output: reason)
                case .couldNotVerify(let reason):
                    return .failed(message: "not run: \(reason)", output: reason)
                }
            }
        } else {
            return .failed(message: "not run: \(install.path) is not signed by Astral", output: "")
        }

        var environment = self.environment()
        // The receipt `UvCheck` read is `$HOME/.config/uv/uv-receipt.json`: the
        // child must read the same one. `XDG_CONFIG_HOME` (when its `uv`
        // directory exists) and the two `AXOUPDATER_CONFIG_*` variables would
        // point it elsewhere; a GUI process has none of them, a terminal-run
        // `duo` may.
        environment["HOME"] = scanner.home.path
        for key in ["XDG_CONFIG_HOME", "AXOUPDATER_CONFIG_PATH", "AXOUPDATER_CONFIG_WORKING_DIR"] {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
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

        // The trust rule again, on the files the update left.
        guard let after = await scanner.reread(install), after.layout == .standalone else {
            return .failed(message: "uv self update finished, but \(install.path) is no longer the standalone install",
                           output: run.text)
        }
        guard after.isVendorSigned, after.uvx == nil || after.uvxSignature == .vendor else {
            return .failed(
                message: "uv self update finished, but the new uv is not signed by Astral (Team \(UvScanner.teamIdentifier))",
                output: run.text)
        }
        guard let version = after.version, version == after.receiptVersion else {
            return .failed(
                message: "uv self update finished, but the new uv reads as \(after.version ?? "nothing") and its receipt as \(after.receiptVersion ?? "nothing")",
                output: run.text)
        }
        return .updated(version: version)
    }

    /// The line the row shows when the command failed.
    ///
    /// uv prints its own failures as `error: <what>` on stderr, often followed by
    /// a `Caused by:` chain. With every proxy variable at a dead `127.0.0.1:9`,
    /// 0.9.18's `self update` printed (2026-10-02):
    ///
    ///     info: Checking for updates...
    ///     error: error sending request for url (https://api.github.com/repos/astral-sh/uv/releases)
    ///       Caused by: client error (Connect)
    ///       …
    ///       Caused by: Connection refused (os error 61)
    ///
    /// The `error:` line says what uv was doing; the chain under it ends on a
    /// root cause with no context. So the `error:` line is taken, without its
    /// prefix, and the whole chain stays in the output for the detail pane;
    /// anything else falls to the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let error = lines.last(where: { $0.hasPrefix("error: ") }) {
            return String(error.dropFirst("error: ".count))
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
