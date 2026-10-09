import Foundation

/// Runs the one-click update an Atuin status offers — `<binary> update`, Atuin's
/// own command on the install's own file — and checks what it left.
///
/// Asked again here, because each can change between the check and the click:
/// - a change already running (`AtuinActivity`);
/// - the install: the same path and file, the version that was checked, the copy
///   the receipt names, a directory this user can write to, not quarantined, and
///   byte for byte its version's published build (`AtuinVerifier`, which
///   downloads that release's archive here the first time);
/// - the channel, which must still name a version newer than the file.
///
/// The child gets the app's environment without any `ATUIN_*`, `AXOUPDATER_*`
/// or `INSTALLER_*` variable, `CARGO_DIST_FORCE_INSTALL_DIR` or
/// `XDG_CONFIG_HOME` — each would point Atuin's settings, axoupdater's receipt
/// or the installer's download or directory elsewhere than what was checked; a
/// GUI process has none of them, a terminal-run `duo` may. `HOME` is the
/// scanner's, and `PATH` the receipt's directory first, then the system's
/// (`AtuinCheck.updateCommand`).
///
/// After it ran, the same rule is asked of what it left: a version newer than
/// the one it replaced, by the rewritten receipt, and byte for byte that
/// version's published build. Anything else is a failure, not "updated".
public struct AtuinUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> AtuinActivity.Busy?

    let busy: BusyCheck
    let scanner: AtuinScanner
    let check: AtuinCheck
    let verifier: AtuinVerifier
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 archive is ~15 MB; the deadline is for a child that hangs, not
    /// for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    static let strippedPrefixes = ["ATUIN_", "AXOUPDATER_", "INSTALLER_"]
    static let strippedKeys = ["CARGO_DIST_FORCE_INSTALL_DIR", "XDG_CONFIG_HOME"]

    public init() {
        self.init(
            busy: { AtuinActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: AtuinScanner(),
            check: AtuinCheck(),
            verifier: AtuinVerifier(),
            // axoupdater and the installer's curl both read the proxy variables,
            // which a GUI app launched by launchd does not have. See
            // `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: AtuinScanner,
        check: AtuinCheck,
        verifier: AtuinVerifier,
        environment: @escaping @Sendable () -> [String: String],
        deadline: ChildProcess.Deadline = AtuinUpdater.defaultDeadline
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
        guard let command = status.oneClick, case .atuin(let install) = status.detail,
              let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.reread(install.path) }), now.problem == nil,
              now.version == before, let binary = now.binary, binary == command.executable,
              now.installDirectory == command.pathPrefix, let target = now.target, !now.quarantined,
              now.settings == install.settings
        else {
            return .failed(message: "not run: \(install.path) is no longer the atuin that was checked", output: "")
        }
        guard now.writable else {
            return .failed(message: "not run: atuin update could not write to \((binary as NSString).deletingLastPathComponent)",
                           output: "")
        }
        // Never toward an older version: `atuin update` installs what the
        // channel names now and refuses anything not newer itself; asking first
        // keeps a moved-back channel from reading as an update that did nothing.
        let channel = now.settings.channel
        do {
            let newest = try await check.latest(channel)
            guard AtuinRelease.compare(before, newest) == .orderedAscending else {
                return .failed(message: "not run: atuin's \(channel) channel now names \(newest), not a version newer than \(before)",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read atuin's \(channel) channel: \(error)", output: "")
        }

        // The trust rule, at the click.
        progress("Checking \(binary) against atuin \(before) as atuinsh published it…")
        switch await verifier.verify(binary: binary, version: before, target: target) {
        case .matches:
            break
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }
        // Asked again: the check above may have downloaded an archive, long
        // enough for an `atuin update` started in a terminal to be under way.
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }

        var environment = self.environment()
        for key in environment.keys
        where Self.strippedKeys.contains(key) || Self.strippedPrefixes.contains(where: { key.hasPrefix($0) }) {
            environment.removeValue(forKey: key)
        }
        environment["HOME"] = scanner.home.path
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
        guard let after = await offCooperativePool({ scanner.reread(install.path) }), after.problem == nil,
              let version = after.version, let newBinary = after.binary, let newTarget = after.target
        else {
            return .failed(message: "atuin update finished, but \(install.path) is no longer the copy its receipt names",
                           output: run.text)
        }
        guard AtuinRelease.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still atuin \(version)" : "went from atuin \(before) to \(version)"
            return .failed(message: "atuin update finished, but \(install.path) \(what)", output: run.text)
        }
        switch await verifier.verify(binary: newBinary, version: version, target: newTarget) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "atuin update finished, but \(reason)", output: run.text)
        }
    }

    /// The exit status after the tool's own line, so the row says both what it
    /// said and how it ended.
    static func exitSuffix(_ outcome: ChildProcess.Outcome) -> String {
        outcome.uncaughtSignal ? " (signal \(outcome.terminationStatus))" : " (exit \(outcome.terminationStatus))"
    }

    /// The line the row shows when `atuin update` failed: its `Error:` line
    /// (eyre's report from `main`), with the first `Caused by:` reason when it
    /// has one; anything else falls to the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let index = lines.lastIndex(where: { $0.hasPrefix("Error: ") }) {
            var message = String(lines[index].dropFirst("Error: ".count)).trimmingCharacters(in: .whitespaces)
            let rest = lines[(index + 1)...]
            if let caused = rest.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "Caused by:" }),
               let reason = rest[(caused + 1)...].first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                var cause = reason.trimmingCharacters(in: .whitespaces)
                // eyre numbers its causes: `   0: <reason>`.
                if let colon = cause.firstIndex(of: ":"), cause[..<colon].allSatisfy(\.isNumber), !cause[..<colon].isEmpty {
                    cause = cause[cause.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                message += ": " + cause
            }
            if !message.isEmpty { return message + Self.exitSuffix(outcome) }
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
