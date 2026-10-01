import Foundation

/// Runs the one-click update a Junie status offers — the vendor's installer for the
/// install's own channel — and checks what it left.
///
/// `status.oneClick` is the documented `curl -fsSL <installer> | bash`; this runs
/// its equivalent without the pipe: it fetches the script itself (TLS, the whole
/// body or an error) into a private temporary directory and runs `/bin/bash
/// <file>`, so a download cut short can never run as half a script. What the
/// script does, from `install.sh` (read 2026-10-02):
/// - fetches the channel's `update-info*.jsonl`, takes the newest build for this
///   Mac, and downloads it with `curl -fSL --progress-bar -o $(mktemp) <url>` — the
///   whole ~330 MB every time, no resume (`-C` is not passed and the file is a
///   fresh `mktemp`), no retry and no stall timeout of its own;
/// - checks the zip's sha256 against the feed, extracts it with `ditto` into
///   `versions/.<build>.tmp.$$`, strips quarantine, renames it into
///   `versions/<build>` and points `current` at it with `ln -sfn`;
/// - **rewrites the launcher** (`cat > ~/.local/bin/junie`) with the shim embedded
///   in the script. A first-generation shim becomes the managed one; a newer shim
///   Junie refreshed by itself would be replaced by the installer's copy;
/// - appends `~/.local/bin` to a shell profile unless it is already on `PATH` —
///   which is why the child's `PATH` starts with it.
///
/// Gates asked again here, because they can change between the check and the
/// click: an update in flight (`JunieActivity`), Junie's own `auto-update` setting,
/// and the install itself — a build Junie staged or installed since the check is
/// left alone. Afterwards the install is read again: it must have moved to a newer
/// build of the same channel, and that build must carry JetBrains' Developer ID
/// (Team `2ZEFAR8TH3`, `CLIToolTrust`) — anything else is `.failed`, never
/// `.updated`.
public struct JunieUpdater: Sendable {

    /// The installer's file name starts with this, so `JunieActivity` can tell a
    /// run of it in the process table.
    static let scriptPrefix = "junie-install-"

    typealias BusyCheck = @Sendable (JunieInstall) -> JunieActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    /// Re-reads the install before the run and after it; its `home` is the `HOME`
    /// the installer gets, so it writes where the scan reads.
    let scanner: JunieScanner
    /// The child's environment before `HOME`, `PATH` and `TMPDIR` are set.
    let environment: @Sendable () -> [String: String]
    /// Junie's settings as they are at the click (`~/.junie/config.json`).
    let settings: @Sendable () -> JunieSettings
    let fetchScript: FetchScript
    let deadline: ChildProcess.Deadline

    /// A build is ~330 MB (3419.26 for `macos-aarch64`: 334,563,717 bytes), and the
    /// installer's curl has no stall timeout: a download that stops making progress
    /// waits for this deadline. Thirty minutes is ~1.5 Mbit/s for the whole file.
    /// On SIGTERM the bash running the installer exits and a curl it started keeps
    /// going (the deadline signals the child's pid alone, `ChildProcess`); its
    /// partial file is in the temporary directory this removes afterwards.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(30 * 60), killAfter: .seconds(30 * 60 + 30))

    public init() {
        self.init(
            busy: { JunieActivity.busy($0, processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: JunieScanner(),
            // The installer runs curl, which reads `https_proxy`; a GUI app launched
            // by launchd has none. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            settings: { JunieSettings.read() },
            fetchScript: { try await JunieUpdater.download($0) })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: JunieScanner,
        environment: @escaping @Sendable () -> [String: String],
        settings: @escaping @Sendable () -> JunieSettings = { JunieSettings() },
        fetchScript: @escaping FetchScript,
        deadline: ChildProcess.Deadline = JunieUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.environment = environment
        self.settings = settings
        self.fetchScript = fetchScript
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard let command = status.oneClick, case .junie(let install) = status.detail,
              let channel = install.channel, let installer = JunieRelease.installer(channel: channel),
              let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy(install) }) {
            return .busy(running.description)
        }
        let settings = self.settings
        guard await offCooperativePool({ settings() }).autoUpdate else { return .notOffered }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.scan().first }), now.path == install.path,
              now.problem == nil, now.channel == channel
        else {
            return .failed(message: "not run: \(install.path) is no longer the Junie install that was checked", output: "")
        }
        if let pending = now.pendingUpdate {
            return .busy("Junie has downloaded \(pending) and installs it the next time it starts")
        }
        if now.version != before {
            return .busy("Junie is now \(now.version ?? "unreadable"), not the \(before) that was checked")
        }

        let script: Data
        do {
            script = try await fetchScript(installer)
        } catch {
            return .failed(message: "could not download \(installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script, channel: channel) else {
            return .failed(
                message: "\(installer.absoluteString) did not answer with the \(channel) installer", output: "")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-junie-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("\(Self.scriptPrefix)\(channel).sh")
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try script.write(to: file, options: .atomic)
        } catch {
            return .failed(message: "could not write the installer: \(error)", output: "")
        }

        var environment = self.environment()
        // Pins and one-shot mode change what the installer does; neither is ours.
        for key in ["JUNIE_VERSION", "JUNIE_ONESHOT", "JUNIE_ONESHOT_VERSION_FILE"] { environment[key] = nil }
        environment["HOME"] = scanner.home.path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: command.pathPrefix)
        // Its `mktemp` zip lands here, and goes with the directory.
        environment["TMPDIR"] = directory.path + "/"
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/bash", arguments: [file.path], pathPrefix: command.pathPrefix),
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

        let after = await offCooperativePool { scanner.scan().first.map(scanner.withSignature) }
        return Self.verdict(after: after, before: before, channel: channel, output: run.text)
    }

    /// What the installer left, judged: a newer, intact build of the same channel,
    /// signed by JetBrains.
    static func verdict(after: JunieInstall?, before: String, channel: String, output: String) -> CLIToolUpdateOutcome {
        guard let after, after.problem == nil, let version = after.version else {
            let why = after?.problem.map { JunieCheck.describe($0, install: after!) } ?? "no Junie install found"
            return .failed(message: "the installer finished, but \(why)", output: output)
        }
        guard JunieRelease.compare(version, before) == .orderedDescending else {
            return .failed(message: "the installer finished, but Junie is still \(version)", output: output)
        }
        guard after.bundleVersion == version, after.channel == channel else {
            return .failed(
                message: "the installer finished, but versions/\(version) is not a \(channel) build of \(version)",
                output: output)
        }
        guard after.signature == .vendor else {
            return .failed(
                message: "\(version) is not signed by JetBrains (Team \(JunieScanner.teamIdentifier)): "
                    + (after.signature?.rawValue ?? "unchecked"),
                output: output)
        }
        return .updated(version: version)
    }

    /// The script is the channel's installer: a shell script that sets the
    /// channel it installs (`CHANNEL="release"`, line 16 of `install.sh` on
    /// 2026-10-02). An error page, or the installer of another channel, is not run.
    static func isInstaller(_ data: Data, channel: String) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("#!/bin/bash") || text.hasPrefix("#!/usr/bin/env bash") else { return false }
        return text.split(whereSeparator: \.isNewline).contains { $0 == "CHANNEL=\"\(channel)\"" }
    }

    /// The whole script or an error: `data(for:)` fails a body shorter than its
    /// `Content-Length`. Never cached: the installer is what decides the install.
    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .install)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw JunieRelease.Failure.http(status) }
        return data
    }

    /// The line the row shows when the installer failed.
    ///
    /// `install.sh` runs under `set -euo pipefail` and says why on stderr as
    /// `ERROR: <reason>` (`log_error`: "Checksum verification failed!", "No release
    /// found for platform: …"); when its curl fails first, curl's own line ends the
    /// output (`curl: (22) The requested URL returned error: 404`). The shared rule
    /// finds either; only the `ERROR: ` prefix is taken off. The progress bar's
    /// lines carry no letters, so they are never the reason.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        let line = CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        return line.hasPrefix("ERROR: ") ? String(line.dropFirst("ERROR: ".count)) : line
    }
}
