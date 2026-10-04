import Foundation

/// Runs the one-click update an OpenCode status offers — the vendor's installer,
/// pinned to the checked version — and checks what it left.
///
/// `status.oneClick` is `curl -fsSL https://opencode.ai/install | bash -s --
/// --version <v> --no-modify-path`; this runs its equivalent without the pipe: it
/// fetches the script itself (TLS, the whole body or an error) into a private
/// temporary directory and runs `/bin/bash <file> --version <v> --no-modify-path`,
/// so a download cut short can never run as half a script. What the script does
/// (read 2026-10-04):
/// - checks that `github.com/anomalyco/opencode/releases/tag/v<v>` exists;
/// - runs `opencode --version` from `PATH` to say what is installed — and the
///   child's `PATH` here holds only the system's directories, so the installed
///   file is never run;
/// - downloads `opencode-darwin-<arch>.zip` with curl into
///   `$TMPDIR/opencode_install_<pid>`, unzips it and `mv`s `opencode` over
///   `~/.opencode/bin/opencode`. **No checksum** is checked: what it leaves is
///   held to the trust rule here instead;
/// - with `--no-modify-path`, leaves the shell's rc files alone.
///
/// Gates asked again here, because they can change between the check and the
/// click: an installer running (`OpencodeActivity`), OpenCode's own `autoupdate`
/// setting, the install itself — the same file at the same version — and the
/// channel, whose version must still be newer: it is what the installer is told
/// to install. Afterwards the install must read as that version and carry
/// Anomaly's Developer ID (Team `5NZ4Q7NXJ4`) — anything else is `.failed`.
public struct OpencodeUpdater: Sendable {

    static let scriptName = "opencode-install.sh"

    typealias BusyCheck = @Sendable () -> OpencodeActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: OpencodeScanner
    let check: OpencodeCheck
    /// The child's environment before `HOME`, `PATH` and `TMPDIR` are set.
    let environment: @Sendable () -> [String: String]
    let settings: @Sendable () -> OpencodeSettings
    let fetchScript: FetchScript
    let deadline: ChildProcess.Deadline

    /// The arm64 zip is 45,538,151 bytes (1.18.34), fetched by the installer's
    /// curl with no stall timeout; twenty minutes is ~300 kbit/s. The deadline is
    /// for a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(20 * 60), killAfter: .seconds(20 * 60 + 30))

    /// `VERSION` is the installer's own pin, read before its arguments; the
    /// GitHub Actions variables make it write `$GITHUB_PATH`. A terminal-run
    /// `duo` can inherit any of them.
    static let overrides = ["VERSION", "GITHUB_ACTIONS", "GITHUB_PATH"]

    public init() {
        let scanner = OpencodeScanner()
        self.init(
            busy: {
                OpencodeActivity.busy(
                    processes: NpmActivity.runningProcesses(), temporaryDirectories: OpencodeActivity.temporaryDirectories)
            },
            scanner: scanner,
            check: OpencodeCheck(),
            // The installer runs curl, which reads `https_proxy`; a GUI app has
            // none. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            settings: { OpencodeSettings.read(home: scanner.home) },
            fetchScript: { try await OpencodeUpdater.download($0) })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: OpencodeScanner,
        check: OpencodeCheck,
        environment: @escaping @Sendable () -> [String: String],
        settings: @escaping @Sendable () -> OpencodeSettings = { OpencodeSettings() },
        fetchScript: @escaping FetchScript,
        deadline: ChildProcess.Deadline = OpencodeUpdater.defaultDeadline
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
        guard status.oneClick != nil, case .opencode(let install) = status.detail,
              let before = install.version, let architecture = install.architecture
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let settings = self.settings
        guard await offCooperativePool({ settings() }).autoUpdate else { return .notOffered }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.scan() }), now.path == install.path, now.problem == nil,
              now.version == before, now.architecture == architecture
        else {
            return .failed(message: "not run: \(install.path) is no longer the OpenCode that was checked", output: "")
        }
        // The version the installer is told to install is the channel's now.
        let target: String
        do {
            target = try await check.latest(architecture)
        } catch {
            return .failed(message: "not run: could not read OpenCode's latest release: \(error)", output: "")
        }
        guard OpencodeRelease.compare(before, target) == .orderedAscending else {
            return .failed(message: "not run: OpenCode's latest release is now \(target), not a version newer than \(before)",
                           output: "")
        }

        let script: Data
        do {
            script = try await fetchScript(OpencodeCheck.installer)
        } catch {
            return .failed(message: "could not download \(OpencodeCheck.installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script) else {
            return .failed(message: "\(OpencodeCheck.installer.absoluteString) did not answer with the OpenCode installer",
                           output: "")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-opencode-\(UUID().uuidString)", isDirectory: true)
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
        for key in Self.overrides { environment[key] = nil }
        environment["HOME"] = scanner.home.path
        // The system's directories only: the installer's `opencode --version`
        // must find no OpenCode to run.
        environment["PATH"] = CLIToolCommandRunner.systemPath
        // Its `opencode_install_<pid>` lands here, and goes with the directory.
        environment["TMPDIR"] = directory.path + "/"
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/bash", arguments: [file.path, "--version", target, "--no-modify-path"],
                           pathPrefix: nil),
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

        let after = await offCooperativePool { scanner.scan().map(scanner.withSignature) }
        return Self.verdict(after: after, target: target, output: run.text)
    }

    /// What the installer left, judged: the version it was told to install,
    /// signed by Anomaly.
    static func verdict(after: OpencodeInstall?, target: String, output: String) -> CLIToolUpdateOutcome {
        guard let after, after.problem == nil, let version = after.version else {
            return .failed(message: "the installer finished, but ~/.opencode/bin/opencode no longer reads as OpenCode",
                           output: output)
        }
        guard version == target else {
            return .failed(message: "the installer finished, but OpenCode is \(version), not \(target)", output: output)
        }
        guard after.signature == .vendor else {
            return .failed(
                message: "OpenCode \(version) is not signed by Anomaly (Team \(OpencodeScanner.teamIdentifier)): "
                    + (after.signature?.rawValue ?? "unchecked"),
                output: output)
        }
        return .updated(version: version)
    }

    /// The script is OpenCode's installer: a bash script that names its app and
    /// installs into `$HOME/.opencode/bin` (lines 3 and 68 of the installer on
    /// 2026-10-04). An error page or another script is not run.
    static func isInstaller(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("#!/usr/bin/env bash") || text.hasPrefix("#!/bin/bash") else { return false }
        let lines = Set(text.split(whereSeparator: \.isNewline).map(String.init))
        return lines.contains("APP=opencode") && lines.contains("INSTALL_DIR=$HOME/.opencode/bin")
            && text.contains("--no-modify-path")
    }

    /// The whole script or an error. Never cached: the installer decides the install.
    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .install)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OpencodeRelease.Failure.http(status) }
        return data
    }

    /// The installer's own error line (`Error: Release v… not found`, colour codes
    /// stripped), else the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let line = lines.last(where: { $0.hasPrefix("Error: ") }) {
            return String(line.dropFirst("Error: ".count))
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
