import Foundation

/// Runs the one-click update Deno's row offers — `~/.deno/bin/deno upgrade`,
/// Deno's own command on its own file — and reports how it went.
///
/// It runs exactly `status.oneClick`; whether one is offered is `DenoCheck`'s
/// decision. Asked again here, because each can change between the check and
/// the click: a `deno upgrade` already running (`DenoActivity`); the file — still
/// at its path, not quarantined, the version that was checked, signed by Deno
/// Land, a stable build; and the channel, which must still name a version newer
/// than the file, since `deno upgrade` installs whatever it names.
///
/// What `deno upgrade` does (`cli/tools/upgrade.rs`, v2.9.7): reads
/// `release-latest.txt`, stops at once when that is the running version, else
/// tries a bsdiff delta chain from the running build and falls back to
/// downloading the release's zip from GitHub (cached in `$DENO_DIR/dl`), runs
/// the new file's `-V`, and renames it over its own path. There is no hash
/// unless `--checksum` is passed: the file it leaves is held to the trust rule
/// here — a newer version, signed by Deno Land — or the run is a failure, not
/// "updated".
public struct DenoUpdater: Sendable {

    typealias BusyCheck = @Sendable (DenoInstall) -> DenoActivity.Busy?

    let busy: BusyCheck
    let scanner: DenoScanner
    let check: DenoCheck
    /// The child's environment before `HOME`, `PATH` and `TMPDIR` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The aarch64 zip of 2.9.7 is ~45 MB; ten minutes is ~600 kbit/s. The
    /// deadline is for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// What would send `deno upgrade` elsewhere: another host for the channel
    /// file (`DENO_DONT_USE_INTERNAL_BASE_UPGRADE_URL`) or for the download
    /// (`DENO_TESTING_UPGRADE`, localhost) — both test-suite hooks a
    /// terminal-run `duo` could inherit.
    static let overrides = ["DENO_DONT_USE_INTERNAL_BASE_UPGRADE_URL", "DENO_TESTING_UPGRADE"]

    public init() {
        self.init(
            busy: { DenoActivity.upgrading(deno: $0.path, processes: NpmActivity.runningProcesses()) },
            scanner: DenoScanner(),
            check: DenoCheck(),
            // Deno's HTTP client reads the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: DenoScanner,
        check: DenoCheck,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = DenoUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.environment = environment
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .deno(let install) = status.detail else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let found = await offCooperativePool({ scanner.scan() }) else {
            return .failed(message: "not run: \(install.path) is no longer the Deno that was checked", output: "")
        }
        let current = await scanner.checked(found)
        guard current.path == command.executable, current.problem == nil, !current.quarantined,
              let before = current.version, before == install.version, !current.isPrerelease
        else {
            return .failed(message: "not run: \(install.path) is no longer the Deno that was checked", output: "")
        }
        guard current.signature == .vendor else {
            return .failed(
                message: "not run: \(install.path) is not signed by Deno Land (Team \(DenoScanner.teamIdentifier))",
                output: "")
        }
        guard current.reported == DenoInstall.Reported(version: before, channel: "stable") else {
            return .failed(message: "not run: \(install.path) is not a stable Deno \(before) build", output: "")
        }
        guard current.writable else {
            return .failed(message: "not run: the folder of \(install.path) is not writable", output: "")
        }
        // Never downgrade: what `deno upgrade` installs is what the channel names now.
        do {
            let newest = try await check.latest()
            guard DenoRelease.compare(before, newest) == .orderedAscending else {
                return .failed(
                    message: "not run: Deno's channel now names \(newest), not a version newer than \(before)",
                    output: "")
            }
        } catch {
            return .failed(message: "not run: could not read Deno's release channel: \(error)", output: "")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-deno-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return .failed(message: "could not make a temporary directory: \(error)", output: "")
        }
        var environment = self.environment()
        for key in Self.overrides { environment[key] = nil }
        environment["HOME"] = scanner.home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        environment["NO_COLOR"] = "1"
        // Its temporary directory lands here, and goes with ours.
        environment["TMPDIR"] = directory.path + "/"
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

        let after: DenoInstall?
        if let rescanned = await offCooperativePool({ scanner.scan() }) {
            after = await scanner.checked(rescanned)
        } else {
            after = nil
        }
        return Self.verdict(after: after, before: before, output: run.text)
    }

    /// What `deno upgrade` left, judged: a newer Deno, signed by Deno Land.
    static func verdict(after: DenoInstall?, before: String, output: String) -> CLIToolUpdateOutcome {
        guard let after, after.problem == nil, let version = after.version else {
            return .failed(message: "deno upgrade finished, but the file no longer reads as a Deno build", output: output)
        }
        guard DenoRelease.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still \(version)" : "went from \(before) to \(version)"
            return .failed(message: "deno upgrade finished, but Deno \(what)", output: output)
        }
        guard after.signature == .vendor, !after.quarantined else {
            return .failed(
                message: "Deno \(version) is not signed by Deno Land (Team \(DenoScanner.teamIdentifier)): "
                    + (after.quarantined ? "quarantined" : after.signature?.rawValue ?? "unchecked"),
                output: output)
        }
        return .updated(version: version)
    }

    /// Deno's own reason with the exit status: its `error: <reason>` line (an
    /// error it returns), else its last line with words in it — a failed
    /// download is logged without the prefix ("Download could not be found,
    /// aborting", exit 1, measured on 2.9.7 with `--version 9.9.9`). A timeout or
    /// a signal is the shared rule's. The whole output stays in `output`.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        guard !outcome.timedOut, !outcome.uncaughtSignal else {
            return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        }
        let reason = lines.last(where: { $0.hasPrefix("error: ") })
            .map { $0.dropFirst("error: ".count).trimmingCharacters(in: .whitespaces) }
            ?? lines.last(where: CLIToolCommandRunner.isMeaningful)?.trimmingCharacters(in: .whitespaces)
        guard let reason, !reason.isEmpty else {
            return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        }
        return "deno upgrade: \(reason) (exit \(outcome.terminationStatus))"
    }
}
