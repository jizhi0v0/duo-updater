import Foundation

/// Runs the one-click update a Boat status offers — `~/.ascii/bin/boat
/// self-update`, Boat's own command on its own file — and reports how it went.
///
/// It runs exactly `status.oneClick`; whether one is offered is `BoatCheck`'s
/// decision. Asked again here, because each can change between the check and
/// the click: a `self-update` already running (`BoatActivity`); the file —
/// still at its path, not quarantined, the version that was checked, and byte
/// for byte the build Boat published for it; Boat's config — the same channel
/// and server; and the channel itself, which must still name a version newer
/// than the file. `self-update` takes whatever the channel names, so a channel
/// switched in Boat's config after the check (`prod` → `staging`), or one that
/// has since moved back, would otherwise downgrade the file (review, #986).
/// Measured 2026-10-04: the published 1.0.38 with `"channel":"staging"` in its
/// config printed `{"event":"updated","version":"1.0.34-staging1"}`, exit 0,
/// and read as 1.0.34-staging1 afterwards.
///
/// After it ran, the same rule is asked of what it left: a version newer than
/// the one it replaced, and that version's published sha256. Anything else is a
/// failure, not "updated".
///
/// Measured on 2026-10-04 in a scratch HOME, the published 1.0.37 at
/// `.ascii/bin/boat`: with output to a pipe, `boat self-update` printed one JSON
/// line and exited 0 within seconds,
///
///     {"event":"updated","version":"1.0.38"}
///
/// leaving a new inode, byte for byte the 1.0.38 release (`64ed164b…`). With
/// every proxy variable at a dead `127.0.0.1:9` it printed
/// `{"error":"error sending request for url (https://boat.dev/api/boat/cli/version?…): client error (Connect): …","event":"error"}`
/// and exited 1, the file untouched.
public struct BoatUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> BoatActivity.Busy?

    let busy: BusyCheck
    let scanner: BoatScanner
    let check: BoatCheck
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 build is 6,635,600 bytes (1.0.38); five minutes is ~180 kbit/s.
    /// The deadline is for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(5 * 60), killAfter: .seconds(5 * 60 + 30))

    public init() {
        self.init(
            busy: { BoatActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: BoatScanner(),
            check: BoatCheck(),
            // Boat's HTTP client reads the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: BoatScanner,
        check: BoatCheck,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = BoatUpdater.defaultDeadline
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
        guard let command = status.oneClick, case .boat(let install) = status.detail else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        guard let current = await scanner.reread(), current.path == command.executable, current.problem == nil,
              !current.quarantined, let before = current.version, before == install.version,
              current.settings == install.settings, current.settings.customAPI == nil,
              let platform = current.platform
        else {
            return .failed(message: "not run: \(install.path) is no longer the boat that was checked", output: "")
        }
        // Never downgrade: what `self-update` will install is what the channel
        // names now, not what it named at the check.
        let channel = current.settings.channel
        do {
            let newest = try await check.latest(channel, platform)
            guard VersionComparator.compare(before, newest) == .orderedAscending else {
                return .failed(
                    message: "not run: Boat's \(channel) channel now names \(newest), not a version newer than \(before)",
                    output: "")
            }
        } catch {
            return .failed(message: "not run: could not read Boat's \(channel) channel: \(error)", output: "")
        }
        // The trust rule, at the click: the file may have changed since the check.
        switch await check.trust(of: current) {
        case .published:
            break
        case .differs:
            return .failed(
                message: "not run: \(install.path) is not byte for byte the boat \(before) Boat published", output: "")
        case .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }

        var environment = self.environment()
        // The config `BoatCheck` read is under `$HOME`; the child must read the
        // same one. The API-URL variables the binary names (`strings` of 1.0.38:
        // `BOAT_API_URL` and the per-mode `BOAT_STAGING_`, `BOAT_DEV_`,
        // `BOAT_AMSTERDAM_API_URL`) — a terminal-run `duo` may carry one — would
        // send the update to another server than the one asked.
        environment["HOME"] = scanner.home.path
        for key in Self.serverOverrides { environment.removeValue(forKey: key) }
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

        // The trust rule again, on the file the update left.
        guard let after = await scanner.reread(), after.problem == nil, let version = after.version else {
            return .failed(message: "boat self-update finished, but \(install.path) no longer reads as a Boat build",
                           output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still boat \(version)" : "went from boat \(before) to \(version)"
            return .failed(message: "boat self-update finished, but \(install.path) \(what)", output: run.text)
        }
        switch await check.trust(of: after) {
        case .published:
            return .updated(version: version)
        case .differs:
            return .failed(
                message: "boat self-update finished, but the new file is not the boat \(version) Boat published",
                output: run.text)
        case .couldNotVerify(let reason):
            return .failed(message: "boat self-update finished, but \(reason)", output: run.text)
        }
    }

    static let serverOverrides = ["BOAT_API_URL", "BOAT_STAGING_API_URL", "BOAT_DEV_API_URL", "BOAT_AMSTERDAM_API_URL"]

    /// The line the row shows when the command failed: the `error` of Boat's
    /// JSON event line when there is one, else the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut {
            for line in lines.reversed() {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let error = json["error"] as? String, !error.isEmpty
                else { continue }
                return error
            }
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
