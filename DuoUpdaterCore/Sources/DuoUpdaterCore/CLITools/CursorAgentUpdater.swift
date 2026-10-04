import Foundation

/// Runs the one-click update Cursor's CLI row offers — the vendor's installer —
/// and checks what it left.
///
/// `status.oneClick` is the documented `curl https://cursor.com/install -fsS |
/// bash`; this runs its equivalent without the pipe: it fetches the script
/// itself (TLS, the whole body or an error), reads the version it installs, and
/// runs `/bin/bash <file>` from a private temporary directory. What the script
/// does (2026.10.01-e373342's, read 2026-10-04): downloads
/// `agent-cli-package.tar.gz` (no checksum) and extracts it into
/// `versions/.tmp-<version>-<epoch>`, renames that to `versions/<version>`, and
/// points `~/.local/bin/agent` and `cursor-agent` at it. It edits no rc file.
///
/// The installer keeps the old version (~591 MB each). The CLI's own update
/// removes stale ones after it installs, by spawning `cursor-agent
/// cleanup-install-versions <version>` **detached** and never waiting for it
/// (`install-core-posix.ts`); run here and waited for, that command had not
/// exited after five minutes in a scratch HOME (2026-10-04), having started the
/// whole CLI (it wrote `~/.cursor/cli-config.json` and a 0.9 MB
/// `statsig-cache.json`). So it is not run: the next update the CLI makes of
/// itself, at its next start, cleans up as it always does.
///
/// Gates asked again at the click: an install running (`CursorAgentActivity`),
/// the `static` channel, the install itself, and the script's version, which
/// must still be newer than the installed one. Afterwards the launchers must name
/// that version, and its `node` must carry the Node.js Foundation's Developer ID
/// and its `rg` Anysphere's — anything else is `.failed`.
public struct CursorAgentUpdater: Sendable {

    static let scriptName = "cursor-agent-install.sh"

    typealias BusyCheck = @Sendable () -> CursorAgentActivity.Busy?

    let busy: BusyCheck
    let scanner: CursorAgentScanner
    let release: CursorAgentRelease
    /// The child's environment before `HOME`, `PATH` and `TMPDIR` are set.
    let environment: @Sendable () -> [String: String]
    let settings: @Sendable () -> CursorAgentSettings
    let deadline: ChildProcess.Deadline

    /// The package is ~150 MB compressed; thirty minutes is ~700 kbit/s. The
    /// deadline is for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(30 * 60), killAfter: .seconds(30 * 60 + 30))

    public init() {
        let scanner = CursorAgentScanner()
        self.init(
            busy: { CursorAgentActivity.busy(root: scanner.root, processes: NpmActivity.runningProcesses()) },
            scanner: scanner,
            release: CursorAgentRelease(),
            // The installer runs curl, which reads `https_proxy`; a GUI app has
            // none. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            settings: { CursorAgentSettings.read(home: scanner.home) })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: CursorAgentScanner,
        release: CursorAgentRelease,
        environment: @escaping @Sendable () -> [String: String],
        settings: @escaping @Sendable () -> CursorAgentSettings = { CursorAgentSettings() },
        deadline: ChildProcess.Deadline = CursorAgentUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.release = release
        self.environment = environment
        self.settings = settings
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard status.oneClick != nil, case .cursorAgent(let install) = status.detail, let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let settings = self.settings
        guard await !offCooperativePool({ settings() }).updatesDisabled else { return .notOffered }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.scan() }), now.path == install.path, now.problem == nil,
              now.version == before
        else {
            return .failed(message: "not run: \(install.path) is no longer the Cursor CLI that was checked", output: "")
        }

        let script: Data
        let target: String
        do {
            (script, target) = try await release.installer(purpose: .install)
        } catch {
            return .failed(message: "could not download \(CursorAgentRelease.installerURL.absoluteString): \(error)", output: "")
        }
        guard CursorAgentRelease.compare(before, target) == .orderedAscending else {
            return .failed(message: "not run: the installer now installs \(target), not a version newer than \(before)",
                           output: "")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-cursor-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(Self.scriptName)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try script.write(to: file, options: .atomic)
        } catch {
            return .failed(message: "could not write the installer: \(error)", output: "")
        }

        var environment = self.environment()
        environment["HOME"] = scanner.home.path
        environment["PATH"] = CLIToolCommandRunner.systemPath
        environment["TMPDIR"] = directory.path + "/"
        // Plain output: its colour codes and cursor moves are for a terminal.
        environment["NO_COLOR"] = "1"
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/bash", arguments: [file.path], pathPrefix: nil),
            environment: environment, deadline: deadline, progress: progress)
        let outcome: ChildProcess.Outcome
        switch run.result {
        case .couldNotStart(let error):
            return .failed(message: "could not run /bin/bash: \(error)", output: run.text)
        case .finished(let finished):
            outcome = finished
        }
        guard outcome.succeeded else {
            return .failed(message: Self.failureMessage(run.lines, outcome, deadline: deadline), output: run.text)
        }

        let after = await offCooperativePool { () -> (CursorAgentInstall?, Bool) in
            let after = scanner.scan()
            let trusted = after?.directory.map { scanner.isTrusted(URL(fileURLWithPath: $0)) } ?? false
            return (after, trusted)
        }
        return Self.verdict(after: after.0, trusted: after.1, target: target, output: run.text)
    }

    /// What the installer left, judged: the launchers on the script's version,
    /// the vendors' build.
    static func verdict(after: CursorAgentInstall?, trusted: Bool, target: String, output: String) -> CLIToolUpdateOutcome {
        guard let after, after.problem == nil, let version = after.version else {
            return .failed(message: "the installer finished, but the launchers name no complete version", output: output)
        }
        guard version == target else {
            return .failed(message: "the installer finished, but the Cursor CLI is \(version), not \(target)", output: output)
        }
        guard trusted else {
            return .failed(
                message: "\(version) is not the vendors' build: its node must be signed by the Node.js Foundation "
                    + "(Team \(NpmScanner.nodeTeamIdentifier)) and its rg by Anysphere (Team \(CursorAgentScanner.teamIdentifier))",
                output: output)
        }
        return .updated(version: version)
    }

    /// The installer's own `✗ <reason>` line, else the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let line = lines.first(where: { $0.hasPrefix("✗ ") }) {
            return String(line.dropFirst(2))
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
