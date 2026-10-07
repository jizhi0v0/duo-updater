import Foundation

/// Runs the one-click update a Luvus status offers — `<binary> update`, Luvus's
/// own command on the install's own file — and checks what it left.
///
/// Asked again here, because each can change between the check and the click:
/// - a change already running (`LuvusActivity`);
/// - the install: the same path and file, the version that was checked, a place
///   `luvus update` replaces without `sudo`, not quarantined, and byte for byte
///   its version's published build (`LuvusVerifier`, which downloads that
///   release's archive here the first time);
/// - `latest.json`, which must still name a version newer than the file.
///
/// The child's `PATH` is a private directory holding only `curl` and `tar`, the
/// two programs `luvus update` runs for a direct install. Its `sudo` fallback is
/// looked up on `PATH` (a stand-in `sudo` there was called with `install -m 0755
/// …` when the directory was read-only, measured 2026-10-07), so with none on it
/// the fallback fails — "stage an update beside … with administrator permission:
/// No such file or directory" — instead of asking for a password, should the
/// directory stop being writable after the gate above.
///
/// After it ran, the same rule is asked of what it left: a version newer than
/// the one it replaced, byte for byte that version's published build. Anything
/// else is a failure, not "updated".
///
/// Measured 2026-10-07 in a scratch HOME, the published 0.14.2 at
/// `.local/bin/luvus`, with that `PATH`: `luvus update` printed
///
///     Checking for Luvus updates...
///     Luvus 0.14.3 is available (current: 0.14.2).
///     Updated Luvus 0.14.2 -> 0.14.3.
///     Run `luvus server restart` when you are ready to load the new server binary.
///
/// and exited 0 in 4 s, leaving a new inode byte for byte 0.14.3's (`ab10688b…`).
/// This updater's whole path — check, both archives downloaded and checked,
/// `luvus update`, the result checked — took 7.7 s the same day.
/// Without the proxy variables (this Mac reaches the network through a local
/// proxy) it printed `Error: could not check https://luvus.dev/latest.json;
/// check your connection and try again` and exited 1, the file untouched. A
/// running `luvus server` keeps the old binary until it is restarted; that is
/// luvus's own last line, and stays in the output.
public struct LuvusUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> LuvusActivity.Busy?

    let busy: BusyCheck
    let scanner: LuvusScanner
    let check: LuvusCheck
    let verifier: LuvusVerifier
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    /// The programs put on the child's `PATH`, by name.
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 archive is 5.8 MB (0.14.3), fetched by `curl --max-time 120`.
    /// The deadline is for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(5 * 60), killAfter: .seconds(5 * 60 + 30))

    /// What would point `luvus update` at another manifest or download server
    /// than the ones checked (`src/update.rs`): a terminal-run `duo` may carry
    /// them, a GUI app has none.
    static let overrides = ["LUVUS_UPDATE_MANIFEST", "LUVUS_UPDATE_RELEASE_BASE"]

    /// `curl` downloads, `tar` unpacks; nothing else, `sudo` least of all.
    static let defaultTools = ["curl": "/usr/bin/curl", "tar": "/usr/bin/tar"]

    public init() {
        self.init(
            busy: { LuvusActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: LuvusScanner(),
            check: LuvusCheck(),
            verifier: LuvusVerifier(),
            // luvus's curl reads the proxy variables, which a GUI app launched
            // by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: LuvusScanner,
        check: LuvusCheck,
        verifier: LuvusVerifier,
        environment: @escaping @Sendable () -> [String: String],
        tools: [String: String] = LuvusUpdater.defaultTools,
        deadline: ChildProcess.Deadline = LuvusUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.verifier = verifier
        self.environment = environment
        self.tools = tools
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .luvus(let install) = status.detail,
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
            return .failed(message: "not run: \(install.path) is no longer the luvus that was checked", output: "")
        }
        guard now.writable else {
            return .failed(
                message: "not run: luvus update would need sudo to replace a file in \((binary as NSString).deletingLastPathComponent)",
                output: "")
        }
        // Never toward an older version: what `luvus update` installs is what the
        // manifest names now. It refuses anything not newer itself; asking first
        // keeps a moved-back manifest from reading as an update that did nothing.
        do {
            let newest = try await check.latest()
            guard VersionComparator.compare(before, newest) == .orderedAscending else {
                return .failed(message: "not run: luvus.dev/latest.json now names \(newest), not a version newer than \(before)",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read luvus.dev/latest.json: \(error)", output: "")
        }

        // The trust rule, at the click.
        progress("Checking \(binary) against luvus \(before) as RizRiyz published it…")
        switch await verifier.verify(binary: binary, version: before, target: target) {
        case .matches:
            break
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }
        // Asked again: the check above may have downloaded an archive, long
        // enough for a `luvus update` started in a terminal to be under way.
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }

        let tools = self.tools
        let path: URL
        do {
            path = try await offCooperativePool { try Self.makeToolsDirectory(tools) }
        } catch {
            return .failed(message: "not run: could not prepare the update’s PATH: \(error)", output: "")
        }
        defer { try? FileManager.default.removeItem(at: path) }

        var environment = self.environment()
        for key in Self.overrides { environment[key] = nil }
        // luvus classifies `~/.local/bin/luvus` against `$HOME` as written: it must
        // be the home the scanner looked in.
        environment["HOME"] = scanner.home.path
        environment["PATH"] = path.path
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
            return .failed(message: "luvus update finished, but \(install.path) no longer reads as luvus", output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still luvus \(version)" : "went from luvus \(before) to \(version)"
            return .failed(message: "luvus update finished, but \(install.path) \(what)", output: run.text)
        }
        switch await verifier.verify(binary: newBinary, version: version, target: newTarget) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "luvus update finished, but \(reason)", output: run.text)
        }
    }

    /// A fresh directory holding a link to each tool, for the child's `PATH`.
    /// Blocking.
    static func makeToolsDirectory(_ tools: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-luvus-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, target) in tools {
            try FileManager.default.createSymbolicLink(
                atPath: directory.appendingPathComponent(name).path, withDestinationPath: target)
        }
        return directory
    }

    /// The line the row shows when `luvus update` failed: its `Error: <what>`
    /// line (anyhow's report from `main`), with the first `Caused by:` reason
    /// when it has one; anything else falls to the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let index = lines.lastIndex(where: { $0.hasPrefix("Error: ") }) {
            var message = String(lines[index].dropFirst("Error: ".count))
            let rest = lines[(index + 1)...]
            if let caused = rest.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "Caused by:" }),
               let reason = rest[(caused + 1)...].first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                message += ": " + reason.trimmingCharacters(in: .whitespaces)
            }
            return message
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
