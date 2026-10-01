import Foundation

/// Runs the one-click update a Rust row offers — `rustup self update`, or
/// `rustup update <toolchain> --no-self-update` — and reports how it went.
///
/// It runs exactly `status.oneClick`; whether one is offered is `RustCheck`'s
/// decision. Asked again here, because each can change between the check and
/// the click: a rustup command already running (`RustActivity`, plus one this
/// process started for another row), rustup's `auto_self_update`, and rustup
/// itself — a file that is no longer the one whose hash the check proved is
/// proved again before it runs, or not run.
///
/// The child gets `CARGO_HOME` and `RUSTUP_HOME` set to the homes the row was
/// found in: rustup reads both from its environment, and `duo` run from a shell
/// that exports another `CARGO_HOME` would otherwise update a different install
/// than the row's. Plus the system proxy, which rustup's HTTP client reads from
/// `https_proxy` (measured below).
///
/// After `rustup self update`, the new file is held to the trust rule like any
/// other: rustup downloads `rustup-init` with no checksum at all
/// (`prepare_update` in `src/cli/self_update.rs`, 1.29.1: `download_file(…,
/// None, …)`), so the result is only "updated" when its sha256 is the one
/// rust-lang publishes for the version it is. Toolchain downloads rustup checks
/// against the manifest's sha256 itself.
public struct RustUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> RustActivity.Busy?

    let scanner: RustScanner
    let release: RustRelease
    let busy: BusyCheck
    /// The child's environment before the homes and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    /// rustup's settings as they are at the click.
    let settings: @Sendable () -> RustupSettings
    let lock: RustActivity.RunLock
    let deadline: ChildProcess.Deadline

    /// A minimal-profile stable toolchain is ~200 MB of downloads and unpacking
    /// (~23 s on 2026-10-01); `complete` or many targets much more. rustup gives
    /// up on a stalled download by itself; thirty minutes is for a child that
    /// hangs, not for a slow link.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(30 * 60), killAfter: .seconds(30 * 60 + 30))

    public init() {
        let scanner = RustScanner()
        self.init(
            scanner: scanner, release: RustRelease(),
            busy: { RustActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            settings: { RustupSettings.read(rustupHome: scanner.rustupHome) })
    }

    init(
        scanner: RustScanner,
        release: RustRelease,
        busy: @escaping BusyCheck,
        environment: @escaping @Sendable () -> [String: String],
        settings: @escaping @Sendable () -> RustupSettings,
        lock: RustActivity.RunLock = .shared,
        deadline: ChildProcess.Deadline = RustUpdater.defaultDeadline
    ) {
        self.scanner = scanner
        self.release = release
        self.busy = busy
        self.environment = environment
        self.settings = settings
        self.lock = lock
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .rust(let item) = status.detail,
              let trusted = item.trustedRustup, command.executable == trusted.path
        else { return .notOffered }
        guard lock.tryAcquire() else { return .busy(RustActivity.Busy.ours.description) }
        defer { lock.release() }

        let (busy, settings, scanner) = (self.busy, self.settings, self.scanner)
        let (running, now, current) = await offCooperativePool { (busy(), settings(), scanner.rustup()) }
        if let running { return .busy(running.description) }
        if item.kind == .rustup, !now.selfUpdateEnabled { return .notOffered }
        if case .toolchain = item.kind {
            // `rustup update <name>` installs a toolchain that is not there; a
            // row whose directory went away is not an offer to install it.
            guard FileManager.default.fileExists(atPath: item.path) else { return .notOffered }
        }

        // The trust rule at the click: the same bytes the check proved, or
        // bytes proved again now.
        guard let current, current.problem == nil, !current.quarantined, let sha = current.sha256 else {
            return .failed(message: "not run: \(trusted.path) is no longer the rustup that was checked", output: "")
        }
        if sha != trusted.sha256 {
            let identity = try? await release.identify(
                sha256: sha, triple: current.hostTriple, claimed: current.claimedVersion)
            guard identity?.verified != nil else {
                return .failed(
                    message: "not run: \(trusted.path) changed since the check and could not be proved a build "
                        + "rust-lang publishes",
                    output: "")
            }
        }

        var environment = self.environment()
        environment["CARGO_HOME"] = scanner.cargoHome.path
        environment["RUSTUP_HOME"] = scanner.rustupHome.path
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

        switch item.kind {
        case .rustup:
            return await verifySelfUpdate(before: item.version, output: run.text)
        case .toolchain(let name):
            let path = URL(fileURLWithPath: item.path)
                .appendingPathComponent("lib/rustlib/multirust-channel-manifest.toml")
            let after = await offCooperativePool { RustScanner.manifestVersion(path) }
            guard let after else {
                return .failed(message: "rustup update finished, but \(name.name)'s version cannot be read",
                               output: run.text)
            }
            // Exit 0 is not proof that the toolchain moved; the version its own
            // manifest now records is.
            if after.display == item.version {
                return .failed(message: "rustup update finished, but \(name.name) is still \(after.display)",
                               output: run.text)
            }
            return .updated(version: after.display)
        }
    }

    /// The new rustup, proved like any rustup before its version is believed.
    func verifySelfUpdate(before: String?, output: String) async -> CLIToolUpdateOutcome {
        let scanner = self.scanner
        guard let after = await offCooperativePool({ scanner.rustup() }), after.problem == nil else {
            return .failed(message: "rustup self update left no rustup at \(scanner.rustupPath.path)", output: output)
        }
        let identity: RustRelease.Identity
        do {
            identity = try await release.identify(
                sha256: after.sha256, triple: after.hostTriple, claimed: after.claimedVersion)
        } catch {
            return .failed(
                message: "rustup self update finished, but the new rustup could not be checked against "
                    + "rust-lang's published hash (\(error)); it will not be run until it is",
                output: output)
        }
        guard let version = identity.verified else {
            let claim = after.claimedVersion ?? "an unknown version"
            return .failed(
                message: "rustup self update left a file whose sha256 is not rust-lang's for \(claim) "
                    + "(\(after.hostTriple ?? "unknown architecture")): it will not be run",
                output: output)
        }
        if version == before {
            return .failed(message: "rustup self update finished, but rustup is still \(version)", output: output)
        }
        return .updated(version: version)
    }

    /// The line the row shows when the command failed: rustup's last `error: `
    /// line without its prefix, else the shared rule. rustup prints each failure
    /// as `error: <reason>` on stderr, and may follow it with `info:` lines.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let error = lines.last(where: { $0.hasPrefix("error: ") }) {
            return String(error.dropFirst("error: ".count))
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
