import Foundation

/// Runs the one-click update a Helm status offers — Helm's official script for
/// the install's own major line, into the install's own directory, without
/// `sudo` — and checks what it left.
///
/// The script is fetched over TLS into a private directory, as Junie's is
/// (`JunieUpdater`), and must be the line's script (`isInstaller`); then
/// `/bin/bash <dir>/get-helm-<major> --version v<target> --no-sudo` runs with:
/// - `HELM_INSTALL_DIR` = the install's directory, `USE_SUDO=false`,
///   `VERIFY_CHECKSUM=true`; the script's other knobs (`BINARY_NAME`,
///   `VERIFY_SIGNATURES`, `DEBUG`, `DESIRED_VERSION`, `GPG_PUBRING`) removed;
/// - a `PATH` of a private directory holding only the programs the script runs
///   — no `sudo`, and no `git`, whose `/usr/bin` stub can offer to install the
///   command-line tools — plus a `helm` link to the install, so its closing
///   `command -v helm` finds the file it wrote; nothing else. The script calls
///   `sudo` only by name (`runAsRoot`), never `/usr/bin/sudo`; `TMPDIR` inside
///   the private directory;
/// - empty stdin.
///
/// What the script does with that (`get-helm-3`, read 2026-10-09): it runs the
/// installed `helm version --template="{{ .Version }}"` — which is why the file
/// must pass the trust rule first — and stops if that already is the target;
/// otherwise it downloads the archive and its `.sha256`, compares them with
/// `openssl`, unpacks, and `cp`s the binary over the file.
///
/// Gates asked again at the click: an update already running (`HelmActivity`),
/// the install itself (same file, version, writable, not quarantined, byte for
/// byte its version's published build), and the line's pointer, which must
/// still name a newer version; that version is the one the script is pinned to.
/// Afterwards the file must read as a newer version of the same line, byte for
/// byte that version's published build, or the outcome is a failure.
public struct HelmUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> HelmActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: HelmScanner
    let check: HelmCheck
    let verifier: HelmVerifier
    let environment: @Sendable () -> [String: String]
    let fetchScript: FetchScript
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    /// An archive is ~20 MB (3.22.0 darwin-arm64), and the script's curl has no
    /// timeout of its own.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// What the script runs.
    static let defaultTools = [
        "curl": "/usr/bin/curl", "openssl": "/usr/bin/openssl", "tar": "/usr/bin/tar", "uname": "/usr/bin/uname",
        "tr": "/usr/bin/tr", "grep": "/usr/bin/grep", "mktemp": "/usr/bin/mktemp", "awk": "/usr/bin/awk",
        "cat": "/bin/cat", "cp": "/bin/cp", "mkdir": "/bin/mkdir", "rm": "/bin/rm", "date": "/bin/date",
    ]

    /// The script's own settings, which this updater sets or leaves unset.
    static let scriptVariables = [
        "BINARY_NAME", "USE_SUDO", "DEBUG", "VERIFY_CHECKSUM", "VERIFY_SIGNATURES", "HELM_INSTALL_DIR",
        "GPG_PUBRING", "DESIRED_VERSION",
    ]

    public init() {
        self.init(
            busy: { HelmActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: HelmScanner(),
            check: HelmCheck(),
            verifier: HelmVerifier(),
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            fetchScript: { try await JunieUpdater.download($0) })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: HelmScanner,
        check: HelmCheck,
        verifier: HelmVerifier,
        environment: @escaping @Sendable () -> [String: String],
        fetchScript: @escaping FetchScript,
        tools: [String: String] = HelmUpdater.defaultTools,
        deadline: ChildProcess.Deadline = HelmUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.verifier = verifier
        self.environment = environment
        self.fetchScript = fetchScript
        self.tools = tools
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard status.oneClick != nil, case .helm(let install) = status.detail,
              let before = install.version, let major = install.major,
              let installer = HelmRelease.installer(major: major)
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.scan().first }), now.path == install.path,
              now.problem == nil, now.version == before, let binary = now.binary, let target = now.target,
              !now.quarantined
        else {
            return .failed(message: "not run: \(install.path) is no longer the helm that was checked", output: "")
        }
        guard now.writable else {
            return .failed(message: "not run: the script would need sudo to replace \(install.path)", output: "")
        }
        let newest: String
        do {
            newest = try await check.latest(major)
            guard VersionComparator.compare(before, newest) == .orderedAscending else {
                return .failed(message: "not run: helm\(major)-latest-version now names \(newest), not newer than \(before)",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read helm\(major)-latest-version: \(error)", output: "")
        }

        progress("Checking \(binary) against helm \(before) as the Helm project published it…")
        switch await verifier.verify(binary: binary, version: before, target: target) {
        case .matches:
            break
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }

        let script: Data
        do {
            script = try await fetchScript(installer)
        } catch {
            return .failed(message: "could not download \(installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script, major: major) else {
            return .failed(message: "\(installer.absoluteString) did not answer with Helm’s v\(major) script", output: "")
        }
        // The script ends with `command -v helm`; a link to the install itself
        // answers it, so nothing of the install's directory goes on `PATH`.
        let tools = self.tools.merging(["helm": install.path]) { _, link in link }
        let directory: URL
        let file: URL
        do {
            directory = try await offCooperativePool { try LuvusUpdater.makeToolsDirectory(tools) }
            file = directory.appendingPathComponent("get-helm-\(major)")
            try script.write(to: file, options: .atomic)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        } catch {
            return .failed(message: "not run: could not prepare the script: \(error)", output: "")
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        var environment = self.environment()
        for key in Self.scriptVariables { environment[key] = nil }
        environment["HELM_INSTALL_DIR"] = install.directory
        environment["USE_SUDO"] = "false"
        environment["VERIFY_CHECKSUM"] = "true"
        environment["HOME"] = scanner.home.path
        environment["PATH"] = directory.path
        environment["TMPDIR"] = directory.appendingPathComponent("tmp").path + "/"
        let command = CLIToolCommand(
            executable: "/bin/bash", arguments: [file.path, "--version", "v\(newest)", "--no-sudo"], pathPrefix: nil)
        let run = await CLIToolCommandRunner.run(
            command, environment: environment, deadline: deadline, standardInput: Data(), progress: progress)
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

        guard let after = await offCooperativePool({ scanner.scan().first }), after.problem == nil,
              let version = after.version, let newBinary = after.binary, let newTarget = after.target
        else {
            return .failed(message: "the script finished, but \(install.path) no longer reads as helm", output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending, after.major == major else {
            return .failed(message: "the script finished, but \(install.path) is helm \(version)", output: run.text)
        }
        switch await verifier.verify(binary: newBinary, version: version, target: newTarget) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "the script finished, but \(reason)", output: run.text)
        }
    }

    /// The script's reason: on failure its trap prints `Failed to install helm`
    /// and a support link after the line that says why ("SHA sum of … does not
    /// match. Aborting.", "Could not retrieve the latest release tag…", curl's
    /// own error), so the last meaningful line before that is the reason; else
    /// the shared rule. With the exit status.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let trap = lines.lastIndex(where: { $0.hasPrefix("Failed to install ") }),
           let reason = lines[..<trap].last(where: CLIToolCommandRunner.isMeaningful) {
            return withStatus(reason.trimmingCharacters(in: .whitespaces), outcome)
        }
        return withStatus(CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline), outcome)
    }

    /// `<reason> (exit <n>)` — or `(signal <n>)` — unless the reason already is
    /// the status or the deadline.
    static func withStatus(_ reason: String, _ outcome: ChildProcess.Outcome) -> String {
        if outcome.timedOut || reason.hasPrefix("exited with status") || reason.hasPrefix("terminated by signal") {
            return reason
        }
        let status = outcome.uncaughtSignal ? "signal \(outcome.terminationStatus)" : "exit \(outcome.terminationStatus)"
        return "\(reason) (\(status))"
    }

    /// The line's script: a bash script that installs into `HELM_INSTALL_DIR`,
    /// honours `--no-sudo`, and reads that line's pointer (the one line
    /// `get-helm-3` and `get-helm-4` differ in). An error page, or the other
    /// line's script, is not run.
    static func isInstaller(_ data: Data, major: Int) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("#!/usr/bin/env bash") || text.hasPrefix("#!/bin/bash") else { return false }
        return text.contains(#": ${HELM_INSTALL_DIR:="#)
            && text.contains("'--no-sudo')")
            && text.contains("https://get.helm.sh/helm\(major)-latest-version")
    }
}
