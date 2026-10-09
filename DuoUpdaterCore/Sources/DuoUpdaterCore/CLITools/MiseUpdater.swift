import Foundation

/// Runs the one-click update mise's row offers — `~/.local/bin/mise self-update
/// -y --no-plugins`, mise's own command on its own file — and reports how it
/// went.
///
/// It runs exactly `status.oneClick`; whether one is offered is `MiseCheck`'s
/// decision. Asked again here, because each can change between the check and
/// the click: a `mise self-update` already running (`MiseActivity`); the file —
/// still at its path, not quarantined, the version that was checked, signed by
/// mise's Team, no packager's marker, a writable folder; and the release index,
/// which must still pick a version newer than the file.
///
/// What `mise self-update` does (`src/cli/self_update.rs`, v2026.10.6): picks
/// the newest release past the minimum release age (`MiseRelease`), stops at
/// once when that is not newer than itself ("mise is already up to date",
/// exit 0), checks the folder is writable, reads the release from GitHub's API,
/// downloads its archive and verifies the release's packslip (sigstore) and the
/// archive's embedded zipsign signature against the key compiled into mise,
/// then replaces its own file. The file it leaves is held to the trust rule
/// here — a newer version, signed by mise's Team — or the run is a failure,
/// not "updated". That includes the exit-0 "already up to date" of a user whose
/// own `minimum_release_age` holds back what the row named.
public struct MiseUpdater: Sendable {

    typealias BusyCheck = @Sendable (MiseInstall) -> MiseActivity.Busy?

    let busy: BusyCheck
    let scanner: MiseScanner
    let check: MiseCheck
    /// The child's environment before `HOME`, `PATH` and `TMPDIR` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 tar.gz of 2026.10.5 is ~43 MB; ten minutes is ~600 kbit/s.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// What would send `mise self-update` to another source: a GitHub API host
    /// or repository other than `jdx/mise` (`self_update.api_url`,
    /// `self_update.repository` as environment variables), which a terminal-run
    /// `duo` can inherit.
    static let overrides = ["MISE_SELF_UPDATE_API_URL", "MISE_SELF_UPDATE_REPOSITORY"]

    public init() {
        self.init(
            busy: { MiseActivity.selfUpdating(mise: $0.path, processes: NpmActivity.runningProcesses()) },
            scanner: MiseScanner(),
            check: MiseCheck(),
            // mise's HTTP client reads the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: MiseScanner,
        check: MiseCheck,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = MiseUpdater.defaultDeadline
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
        guard let command = status.oneClick, case .mise(let install) = status.detail else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running.description)
        }
        guard let current = await scanner.scan(), current.path == command.executable, current.problem == nil,
              !current.quarantined, current.signature == .vendor,
              let before = current.version, before == install.version
        else {
            return .failed(message: "not run: \(install.path) is no longer the mise that was checked", output: "")
        }
        if let marker = current.selfUpdateDisabledBy {
            return .failed(message: "not run: its packager turned mise self-update off (\(marker))", output: "")
        }
        guard current.writable else {
            return .failed(message: "not run: the folder of \(install.path) is not writable", output: "")
        }
        do {
            let newest = try await check.latest()
            guard MiseRelease.compare(before, newest) == .orderedAscending else {
                return .failed(
                    message: "not run: mise's release index now picks \(newest), not a version newer than \(before)",
                    output: "")
            }
        } catch {
            return .failed(message: "not run: could not read mise's release index: \(error)", output: "")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-mise-\(UUID().uuidString)", isDirectory: true)
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
        // Its download and staging land here, and go with the directory.
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
        return Self.verdict(after: await scanner.scan(), before: before, lines: run.lines, output: run.text)
    }

    /// What `mise self-update` left, judged: a newer mise, signed by its Team.
    static func verdict(after: MiseInstall?, before: String, lines: [String], output: String) -> CLIToolUpdateOutcome {
        guard let after, after.problem == nil else {
            return .failed(message: "mise self-update finished, but the file is gone", output: output)
        }
        guard after.signature == .vendor, !after.quarantined else {
            return .failed(
                message: "mise is not signed by Jeffrey Dickey (Team \(MiseScanner.teamIdentifier)): "
                    + (after.quarantined ? "quarantined" : after.signature?.rawValue ?? "unchecked"),
                output: output)
        }
        guard let version = after.version else {
            return .failed(message: "mise self-update finished, but mise --version printed no version", output: output)
        }
        guard MiseRelease.compare(version, before) == .orderedDescending else {
            // "Selected mise 2026.10.4 (minimum release age: 7d)": mise's own pick.
            let selected = lines.last { $0.hasPrefix("Selected mise ") }.map { " (\($0))" } ?? ""
            let what = version == before ? "is still \(version)" : "went from \(before) to \(version)"
            return .failed(message: "mise self-update finished, but mise \(what)\(selected)", output: output)
        }
        return .updated(version: version)
    }

    /// mise's own reason with the exit status: the first `mise ERROR <reason>`
    /// line — the later ones are its version and "Run with --verbose…"
    /// (measured on 2026.10.4: a package-manager marker, a missing release) —
    /// else its last line with words in it. A timeout or a signal is the shared
    /// rule's. The whole output stays in `output`.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        guard !outcome.timedOut, !outcome.uncaughtSignal else {
            return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        }
        let marker = "mise ERROR "
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        let reason = trimmed.first(where: { $0.hasPrefix(marker) })
            .map { $0.dropFirst(marker.count).trimmingCharacters(in: .whitespaces) }
            ?? trimmed.last(where: CLIToolCommandRunner.isMeaningful)
        guard let reason, !reason.isEmpty else {
            return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        }
        return "mise self-update: \(reason) (exit \(outcome.terminationStatus))"
    }
}
