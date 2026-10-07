import Foundation

/// Runs the one-click update a herdr status offers — `~/.local/bin/herdr
/// update`, herdr's own command on its own file — and reports how it went.
///
/// It runs exactly `status.oneClick`; whether one is offered is `HerdrCheck`'s
/// decision. Asked again here, because each can change between the check and
/// the click: an update already running (`HerdrActivity`); the file — still the
/// same file (inode, size, time), not quarantined, and by its sha256 still the
/// published build that was checked; herdr's config — the same channel, its
/// version check still on; and the channel itself, which must still offer a
/// build newer than the file's. `herdr update` takes whatever the channel
/// offers, newer or not (`HerdrCheck`, rule 3).
///
/// **Running sessions.** `herdr update` asks before it stops anything, and only
/// when it has a terminal (`src/update.rs`, `prompt_to_complete_plain_update`).
/// It is run with an empty stdin — never the terminal a `duo` may have — and
/// without `--handoff`, so:
/// - no session running, or each one's server already speaks the new build's
///   endpoint generation: herdr installs, the sessions keep running;
/// - a session whose server must stop for the new build: herdr downloads and
///   checks the build, then prints "Herdr was not updated." and "Stop running
///   Herdr sessions when ready, then run `herdr update` again." and exits **0**,
///   the file untouched. The check of what the update left finds the same build
///   and reports herdr's own two lines as the failure.
/// DuoUpdater never stops a session.
///
/// After it ran, the same rule is asked of what it left: a published build,
/// newer than the one it replaced. Anything else is a failure, not "updated".
public struct HerdrUpdater: Sendable {

    typealias BusyCheck = @Sendable (_ directory: URL) -> HerdrActivity.Busy?

    let busy: BusyCheck
    let scanner: HerdrScanner
    let check: HerdrCheck
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 build is 22,210,016 bytes (0.9.3), which herdr's own `curl`
    /// may take up to 120 s for, after a manifest read of up to 20 s; five minutes
    /// is for a child that hangs, not a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(5 * 60), killAfter: .seconds(5 * 60 + 30))

    public init() {
        // herdr's curl reads the proxy variables, which a GUI app launched by
        // launchd does not have. See `SystemProxyEnvironment`. The scanner reads
        // the config path from the same environment the child gets.
        let environment = ProcessInfo.processInfo.environmentWithSystemProxy
        self.init(
            busy: { HerdrActivity.busy(directory: $0, processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: HerdrScanner(environment: environment),
            check: HerdrCheck(),
            environment: { environment })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: HerdrScanner,
        check: HerdrCheck,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = HerdrUpdater.defaultDeadline
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
        guard let command = status.oneClick, case .herdr(let install) = status.detail,
              let before = status.installedVersion
        else { return .notOffered }
        let busy = self.busy
        let directory = URL(fileURLWithPath: install.path).deletingLastPathComponent()
        if let running = await offCooperativePool({ busy(directory) }) {
            return .busy(running.description)
        }
        guard let current = await scanner.reread(), current.path == command.executable, current.problem == nil,
              !current.quarantined, current.identity == install.identity, current.target == install.target,
              current.settings == install.settings, current.settings.channelIsKnown, current.settings.versionCheck
        else {
            return .failed(message: "not run: \(install.path) is no longer the herdr that was checked", output: "")
        }
        // The trust rule and the channel, at the click: the file must still be
        // the published build that was checked, and what `herdr update` will
        // install is what the channel offers now, not what it offered then.
        let channel = current.settings.channel
        let resolution: HerdrRelease.Resolution
        do {
            resolution = try await check.resolution(of: current)
        } catch {
            return .failed(message: "not run: could not read herdr's \(channel) channel: \(error)", output: "")
        }
        let installed: HerdrBuild
        switch resolution.installed {
        case .published(let build) where build.version == before:
            installed = build
        case .published, .unpublished:
            return .failed(
                message: "not run: \(install.path) is not byte for byte the herdr \(before) herdr published", output: "")
        case .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }
        guard HerdrBuild.compare(installed, resolution.offered) == .orderedAscending else {
            return .failed(
                message: "not run: herdr's \(channel) channel now offers \(resolution.offered.version), not a build newer than \(before)",
                output: "")
        }

        let run = await CLIToolCommandRunner.run(
            command, environment: childEnvironment(), deadline: deadline, standardInput: Data(), progress: progress)
        let outcome: ChildProcess.Outcome
        switch run.result {
        case .couldNotStart(let error):
            return .failed(message: "could not run \(command.executable): \(error)", output: run.text)
        case .finished(let finished):
            outcome = finished
        }
        guard outcome.succeeded else {
            return .failed(message: CLIToolCommandRunner.failureMessage(run.lines, outcome, deadline: deadline),
                           output: run.text)
        }

        // The trust rule again, on the file the update left.
        guard let after = await scanner.reread(), after.problem == nil, after.target != nil else {
            return .failed(message: "herdr update finished, but \(install.path) is no longer a herdr build",
                           output: run.text)
        }
        let left: HerdrBuild
        do {
            switch try await check.resolution(of: after).installed {
            case .published(let build):
                left = build
            case .unpublished:
                return .failed(message: "herdr update finished, but the new file is no build herdr published",
                               output: run.text)
            case .couldNotVerify(let reason):
                return .failed(message: "herdr update finished, but \(reason)", output: run.text)
            }
        } catch {
            return .failed(message: "herdr update finished, but its channel could not be read: \(error)",
                           output: run.text)
        }
        guard HerdrBuild.compare(left, installed) == .orderedDescending else {
            if left.version == before, let declined = Self.declined(run.lines) {
                return .failed(message: declined, output: run.text)
            }
            let what = left.version == before ? "is still herdr \(before)" : "went from herdr \(before) to \(left.version)"
            return .failed(message: "herdr update finished, but \(install.path) \(what)", output: run.text)
        }
        return .updated(version: left.version)
    }

    /// What the child runs with. `HOME` is the scanner's, so it reads the config
    /// the check read and lists the sessions under it. Stripped:
    /// - `HERDR_SOCKET_PATH` and `HERDR_SESSION`, which narrow herdr's look for
    ///   running sessions to one (`running_update_targets`) — a `duo` started in
    ///   a herdr pane carries them — so the others would be left on an old
    ///   server it never asked about;
    /// - `HERDR_FAKE_UPDATE_VERSION` and `HERDR_FAKE_UPDATE_NOTES_VERSION`,
    ///   herdr's testing switches;
    /// - an empty `HERDR_CONFIG_PATH` or `XDG_CONFIG_HOME`, which herdr would take
    ///   as a relative path and `HerdrSettings` does not.
    /// `HERDR_ENV` stays: inside a herdr pane, herdr refuses to update itself,
    /// and says so.
    func childEnvironment() -> [String: String] {
        var environment = self.environment()
        environment["HOME"] = scanner.home.path
        for key in Self.stripped { environment.removeValue(forKey: key) }
        for key in ["HERDR_CONFIG_PATH", "XDG_CONFIG_HOME"] where environment[key]?.isEmpty == true {
            environment.removeValue(forKey: key)
        }
        // herdr runs `curl` by name, which is in /usr/bin.
        environment["PATH"] = CLIToolCommandRunner.path(prefix: nil)
        return environment
    }

    static let stripped = ["HERDR_SOCKET_PATH", "HERDR_SESSION", "HERDR_FAKE_UPDATE_VERSION", "HERDR_FAKE_UPDATE_NOTES_VERSION"]

    /// herdr's own words when it would not install because a session must stop
    /// first: "Herdr was not updated." and the line after it.
    static func declined(_ lines: [String]) -> String? {
        guard let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "Herdr was not updated." })
        else { return nil }
        return lines[index...].prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }
}
