import Foundation

/// Runs the one-click update a Codex status offers — the vendor's standalone
/// installer, which is what `codex update` runs on this kind of install — and
/// checks what it left.
///
/// `status.oneClick` is the documented
/// `curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh`;
/// this runs its equivalent without the pipe: it fetches the script itself (TLS,
/// the whole body or an error) into a private temporary directory and runs
/// `/bin/sh <file>`, so a download cut short can never run as half a script.
/// What the script does, from `install.sh` at `rust-v0.160.0` (read 2026-10-04):
/// - resolves `latest` from `releases.openai.com/codex/channels/latest` (GitHub
///   Releases as the fallback), then takes `install.lock` (`CodexActivity`);
/// - downloads `codex-package_SHA256SUMS`, checks it against the digest the
///   release metadata gives for it, then downloads
///   `codex-package-<target>.tar.gz` (130 MB for aarch64 0.160.0) and checks it
///   against that file — `curl --max-time 300` from releases.openai.com, then a
///   retry from GitHub without a time limit;
/// - extracts into `releases/.staging.<name>.$$`, renames it into
///   `releases/<version>-<target>`, runs the new binary's `--version` to confirm
///   it, and swaps `current` and `~/.local/bin/codex` by rename;
/// - appends `~/.local/bin` to a shell profile unless it is already on `PATH`, and
///   offers to uninstall an npm or Homebrew Codex it finds first on `PATH` —
///   which is why the child's `PATH` starts with the launcher's directory: the
///   installer then sees its own launcher and does neither. `CODEX_NON_INTERACTIVE`
///   answers every prompt no.
///
/// Gates asked again here, because they can change between the check and the
/// click: an installer running (`CodexActivity`), Codex's own
/// `check_for_update_on_startup`, the install itself — the same launcher, release
/// and Team-ID-signed binary — and the channel, which must still name a version
/// newer than the installed one: the installer installs whatever `latest` names,
/// newer or not. Afterwards the install is read again: it must have moved to a
/// newer release whose binary carries OpenAI's Developer ID — anything else is
/// `.failed`, never `.updated`.
public struct CodexUpdater: Sendable {

    /// The installer's file name.
    static let scriptName = "codex-install.sh"

    typealias BusyCheck = @Sendable (CodexInstall) -> CodexActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    /// Re-reads the install before the run and after it; its `home` is the `HOME`
    /// the installer gets, so it writes where the scan reads.
    let scanner: CodexScanner
    let check: CodexCheck
    /// The child's environment before `HOME`, `PATH` and `TMPDIR` are set.
    let environment: @Sendable () -> [String: String]
    /// Codex's settings as they are at the click.
    let settings: @Sendable () -> CodexSettings
    let fetchScript: FetchScript
    let deadline: ChildProcess.Deadline

    /// The aarch64 package is 129,976,298 bytes (0.160.0), x86_64 141,304,442.
    /// The installer gives releases.openai.com five minutes, then fetches the
    /// whole file again from GitHub with no limit of its own; thirty minutes
    /// covers both at ~1 Mbit/s. The deadline is for a child that hangs, not for a
    /// slow one. On SIGTERM the shell's trap releases the lock and removes its
    /// temporary directory.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(30 * 60), killAfter: .seconds(30 * 60 + 30))

    /// The variables `install.sh` and the daemon's updater read. Each would change
    /// what is installed or where — a pinned release, another `CODEX_HOME` or
    /// launcher directory, a daemon-only install, guarded or deferred selection —
    /// and none of them is DuoUpdater's to pass on from a terminal-run `duo`.
    static let installerOverrides = [
        "CODEX_RELEASE", "CODEX_HOME", "CODEX_INSTALL_DIR", "CODEX_INSTALL_DAEMON_ONLY",
        "CODEX_INSTALL_DEFER_SELECTION", "CODEX_INSTALLER_USE_RELEASES_OPENAI_COM", "CODEX_INSTALL_IF_LATEST",
        "CODEX_INSTALL_IF_CURRENT", "CODEX_UPDATE_FROM_RELEASE",
    ]

    public init() {
        let scanner = CodexScanner()
        self.init(
            busy: { CodexActivity.busy(root: URL(fileURLWithPath: $0.root)) },
            scanner: scanner,
            check: CodexCheck(),
            // The installer runs curl, which reads `https_proxy`; a GUI app
            // launched by launchd has none. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            settings: { CodexSettings.read(home: scanner.home) },
            fetchScript: { try await CodexUpdater.download($0) })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: CodexScanner,
        check: CodexCheck,
        environment: @escaping @Sendable () -> [String: String],
        settings: @escaping @Sendable () -> CodexSettings = { CodexSettings() },
        fetchScript: @escaping FetchScript,
        deadline: ChildProcess.Deadline = CodexUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.environment = environment
        self.settings = settings
        self.fetchScript = fetchScript
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .codex(let install) = status.detail,
              let before = install.version, let target = install.target
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running.description)
        }
        let settings = self.settings
        guard await offCooperativePool({ settings() }).checkForUpdates else { return .notOffered }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.scan().first.map(scanner.withSignature) }),
              now.path == install.path, now.root == install.root, now.problem == nil, !now.quarantined,
              now.version == before, now.target == target
        else {
            return .failed(message: "not run: \(install.path) is no longer the Codex install that was checked", output: "")
        }
        guard now.signature == .vendor else {
            return .failed(
                message: "not run: \(now.binary ?? install.path) is not signed by OpenAI (Team \(CodexScanner.teamIdentifier))",
                output: "")
        }
        // Never downgrade: what the installer will install is what `latest`
        // names now, not what it named at the check.
        do {
            let newest = try await check.latest(target)
            guard CodexRelease.compare(before, newest) == .orderedAscending else {
                return .failed(
                    message: "not run: Codex's latest channel now names \(newest), not a version newer than \(before)",
                    output: "")
            }
        } catch {
            return .failed(message: "not run: could not read Codex's latest channel: \(error)", output: "")
        }

        let script: Data
        do {
            script = try await fetchScript(CodexCheck.installer)
        } catch {
            return .failed(message: "could not download \(CodexCheck.installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script) else {
            return .failed(message: "\(CodexCheck.installer.absoluteString) did not answer with the Codex installer", output: "")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-codex-\(UUID().uuidString)", isDirectory: true)
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
        for key in Self.installerOverrides { environment[key] = nil }
        environment["CODEX_NON_INTERACTIVE"] = "1"
        environment["HOME"] = scanner.home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        // Its `mktemp -d` lands here, and goes with the directory.
        environment["TMPDIR"] = directory.path + "/"
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/sh", arguments: [file.path], pathPrefix: command.pathPrefix),
            environment: environment, deadline: deadline, progress: progress)
        let outcome: ChildProcess.Outcome
        switch run.result {
        case .couldNotStart(let error):
            return .failed(message: "could not run /bin/sh: \(error)", output: run.text)
        case .finished(let finished):
            outcome = finished
        }
        guard outcome.succeeded else {
            return .failed(message: CLIToolCommandRunner.failureMessage(run.lines, outcome, deadline: deadline),
                           output: run.text)
        }

        let after = await offCooperativePool { scanner.scan().first.map(scanner.withSignature) }
        return Self.verdict(after: after, before: before, output: run.text)
    }

    /// What the installer left, judged: a newer, intact release, signed by OpenAI.
    static func verdict(after: CodexInstall?, before: String, output: String) -> CLIToolUpdateOutcome {
        guard let after, after.problem == nil, let version = after.version else {
            let why = after?.problem.map { CodexCheck.describe($0, install: after!) } ?? "no standalone Codex found"
            return .failed(message: "the installer finished, but \(why)", output: output)
        }
        guard CodexRelease.compare(version, before) == .orderedDescending else {
            let what = version == before ? "Codex is still \(version)" : "Codex went from \(before) to \(version)"
            return .failed(message: "the installer finished, but \(what)", output: output)
        }
        guard after.signature == .vendor, !after.quarantined else {
            return .failed(
                message: "\(version) is not signed by OpenAI (Team \(CodexScanner.teamIdentifier)): "
                    + (after.quarantined ? "quarantined" : after.signature?.rawValue ?? "unchecked"),
                output: output)
        }
        return .updated(version: version)
    }

    /// The script is Codex's standalone installer: a POSIX shell script that
    /// installs into `$CODEX_HOME_DIR/packages/standalone` from
    /// releases.openai.com (lines 10 and 19 of `install.sh` at `rust-v0.160.0`).
    /// An error page, a captive portal's answer, or another script is not run.
    static func isInstaller(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("#!/bin/sh") else { return false }
        let lines = Set(text.split(whereSeparator: \.isNewline).map(String.init))
        return lines.contains("STANDALONE_ROOT=\"$CODEX_HOME_DIR/packages/standalone\"")
            && lines.contains("RELEASES_BASE_URL=\"https://releases.openai.com/codex\"")
    }

    /// The whole script or an error: `data(for:)` fails a body shorter than its
    /// `Content-Length`. Never cached: the installer is what decides the install.
    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .install)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CodexRelease.Failure.http(status) }
        return data
    }
}
