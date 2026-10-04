import Foundation

/// Runs the one-click update bun's own row offers — `~/.bun/bin/bun upgrade`,
/// bun's own command on its own file — and reports how it went. A package row's
/// click is `NpmUpdater`'s.
///
/// It runs exactly `status.oneClick`; whether one is offered is `BunCheck`'s
/// decision. Asked again here, because each can change between the check and
/// the click: a `bun upgrade` already running (`BunActivity`); the file — still
/// at its path, not quarantined, the version that was checked, signed by Oven;
/// and the channel, which must still name a version newer than the file, since
/// `bun upgrade` installs whatever it names.
///
/// What `bun upgrade` does (`upgrade_command.zig`, `bun-v1.3.10`): asks its
/// channel (`BunRelease`), exits 0 at once when that is the running version,
/// downloads `bun-darwin-<arch>.zip` into `$BUN_TMPDIR`/`$TMPDIR`, unzips it with
/// the `unzip` on `PATH`, runs the new binary's `--version` and refuses a version
/// other than the channel's, then renames the new file over its own path. There
/// is no hash: the file it leaves is held to the trust rule here — a newer
/// version, signed by Oven — or the run is a failure, not "updated".
public struct BunUpdater: Sendable {

    typealias BusyCheck = @Sendable (BunInstall) -> BunActivity.Busy?

    let busy: BusyCheck
    let scanner: BunScanner
    let check: BunCheck
    /// The child's environment before `HOME`, `PATH` and `TMPDIR` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The aarch64 zip of 1.4.2 is ~23 MB; ten minutes is ~300 kbit/s. The
    /// deadline is for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// What would send `bun upgrade` elsewhere: a canary instead of the release
    /// (`BUN_CANARY=1`), another GitHub API host (`GITHUB_API_DOMAIN`, for a
    /// mirror). A terminal-run `duo` can inherit either.
    static let overrides = ["BUN_CANARY", "GITHUB_API_DOMAIN", "BUN_TMPDIR"]

    public init() {
        self.init(
            busy: { BunActivity.upgrading(bun: $0.path, processes: NpmActivity.runningProcesses()) },
            scanner: BunScanner(),
            check: BunCheck(),
            // bun's HTTP client reads the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: BunScanner,
        check: BunCheck,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = BunUpdater.defaultDeadline
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
        guard let command = status.oneClick, case .bun(let install) = status.detail else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let current = await offCooperativePool({ scanner.scan().map(scanner.withSignature) }),
              current.path == command.executable, current.problem == nil, !current.quarantined,
              let before = current.version, before == install.version, !current.isCanary
        else {
            return .failed(message: "not run: \(install.path) is no longer the bun that was checked", output: "")
        }
        guard current.signature == .vendor else {
            return .failed(message: "not run: \(install.path) is not signed by Oven (Team \(BunScanner.teamIdentifier))",
                           output: "")
        }
        // Never downgrade: what `bun upgrade` installs is what the channel names now.
        do {
            let newest = try await check.latest()
            guard BunRelease.compare(before, newest) == .orderedAscending else {
                return .failed(
                    message: "not run: bun's channel now names \(newest), not a version newer than \(before)", output: "")
            }
        } catch {
            return .failed(message: "not run: could not read bun's release channel: \(error)", output: "")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-bun-\(UUID().uuidString)", isDirectory: true)
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
        environment["BUN_INSTALL"] = scanner.root.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        // Its download and unzip land here, and go with the directory.
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

        let after = await offCooperativePool { scanner.scan().map(scanner.withSignature) }
        return Self.verdict(after: after, before: before, output: run.text)
    }

    /// What `bun upgrade` left, judged: a newer bun, signed by Oven.
    static func verdict(after: BunInstall?, before: String, output: String) -> CLIToolUpdateOutcome {
        guard let after, after.problem == nil, let version = after.version else {
            return .failed(message: "bun upgrade finished, but the file no longer reads as a bun build", output: output)
        }
        guard BunRelease.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still \(version)" : "went from \(before) to \(version)"
            return .failed(message: "bun upgrade finished, but bun \(what)", output: output)
        }
        guard after.signature == .vendor, !after.quarantined else {
            return .failed(
                message: "bun \(version) is not signed by Oven (Team \(BunScanner.teamIdentifier)): "
                    + (after.quarantined ? "quarantined" : after.signature?.rawValue ?? "unchecked"),
                output: output)
        }
        return .updated(version: version)
    }

    /// bun's own `error: <reason>` line when there is one (`Failed to download…`,
    /// `The downloaded version of Bun (…) doesn't match…`), else the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let line = lines.last(where: { $0.hasPrefix("error: ") }) {
            let reason = line.dropFirst("error: ".count).trimmingCharacters(in: .whitespaces)
            if !reason.isEmpty { return reason }
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
