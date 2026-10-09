import Foundation

/// Runs the one-click update a Starship status offers — starship.rs's official
/// script, into the install's own directory, pinned to the version checked —
/// and checks what it left.
///
/// The script is fetched over TLS into a private directory (`isInstaller`), then
/// `/bin/sh <dir>/starship-install.sh -y -b <directory> -v v<target>` runs with:
/// - the script's own variables (`BIN_DIR`, `VERSION`, `BASE_URL`, `PLATFORM`,
///   `ARCH`, `FORCE`, `VERBOSE`) removed, so only those flags decide;
/// - a `PATH` of a private directory holding only the programs the script runs
///   — no `sudo`, so a directory that stopped being writable after the gate ends
///   in "Could not find the command sudo" rather than a password prompt (the
///   script calls `sudo` only by name, never `/usr/bin/sudo`), and nothing
///   else; `TMPDIR` inside the private directory;
/// - empty stdin (`-y` skips the only question).
///
/// `/bin/sh` is bash in POSIX mode, which sets `POSIXLY_CORRECT`, so the
/// script's guard against non-POSIX bash passes. The script checks no hash:
/// afterwards the file must read as a newer version and be byte for byte that
/// version's published build (`StarshipVerifier`), or the outcome is a failure.
public struct StarshipUpdater: Sendable {

    static let scriptName = "starship-install.sh"

    typealias BusyCheck = @Sendable () -> StarshipActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: StarshipScanner
    let check: StarshipCheck
    let verifier: StarshipVerifier
    let environment: @Sendable () -> [String: String]
    let fetchScript: FetchScript
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    static let defaultTools = [
        "curl": "/usr/bin/curl", "tar": "/usr/bin/tar", "uname": "/usr/bin/uname", "tr": "/usr/bin/tr",
        "mktemp": "/usr/bin/mktemp", "touch": "/usr/bin/touch", "rm": "/bin/rm", "getconf": "/usr/bin/getconf",
    ]

    static let scriptVariables = ["BIN_DIR", "VERSION", "BASE_URL", "PLATFORM", "ARCH", "FORCE", "VERBOSE"]

    public init() {
        self.init(
            busy: { StarshipActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: StarshipScanner(),
            check: StarshipCheck(),
            verifier: StarshipVerifier(),
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            fetchScript: { try await JunieUpdater.download($0) })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: StarshipScanner,
        check: StarshipCheck,
        verifier: StarshipVerifier,
        environment: @escaping @Sendable () -> [String: String],
        fetchScript: @escaping FetchScript,
        tools: [String: String] = StarshipUpdater.defaultTools,
        deadline: ChildProcess.Deadline = StarshipUpdater.defaultDeadline
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
        guard status.oneClick != nil, case .starship(let install) = status.detail, let before = install.version
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
            return .failed(message: "not run: \(install.path) is no longer the starship that was checked", output: "")
        }
        guard now.writable else {
            return .failed(message: "not run: the script would need sudo to replace \(install.path)", output: "")
        }
        let newest: String
        do {
            newest = try await check.latest()
            guard VersionComparator.compare(before, newest) == .orderedAscending else {
                return .failed(message: "not run: Starship's latest release is now \(newest), not newer than \(before)",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read Starship's latest release: \(error)", output: "")
        }

        progress("Checking \(binary) against starship \(before) as published…")
        switch await verifier.verify(binary: binary, version: before, target: target) {
        case .matches:
            break
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }

        let installer = StarshipCheck.installer
        let script: Data
        do {
            script = try await fetchScript(installer)
        } catch {
            return .failed(message: "could not download \(installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script) else {
            return .failed(message: "\(installer.absoluteString) did not answer with Starship’s install script", output: "")
        }
        let tools = self.tools
        let directory: URL
        let file: URL
        do {
            directory = try await offCooperativePool { try LuvusUpdater.makeToolsDirectory(tools) }
            file = directory.appendingPathComponent(Self.scriptName)
            try script.write(to: file, options: .atomic)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        } catch {
            return .failed(message: "not run: could not prepare the script: \(error)", output: "")
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        var environment = self.environment()
        for key in Self.scriptVariables { environment[key] = nil }
        environment["HOME"] = scanner.home.path
        // Only the private directory: the script then warns that the bin
        // directory is not on `PATH`, which changes nothing.
        environment["PATH"] = directory.path
        environment["TMPDIR"] = directory.appendingPathComponent("tmp").path + "/"
        let command = CLIToolCommand(
            executable: "/bin/sh", arguments: [file.path, "-y", "-b", install.directory, "-v", "v\(newest)"],
            pathPrefix: nil)
        let run = await CLIToolCommandRunner.run(
            command, environment: environment, deadline: deadline, standardInput: Data(), progress: progress)
        let outcome: ChildProcess.Outcome
        switch run.result {
        case .couldNotStart(let error):
            return .failed(message: "could not run /bin/sh: \(error)", output: run.text)
        case .finished(let finished):
            outcome = finished
        }
        guard outcome.succeeded else {
            return .failed(message: Self.failureMessage(run.lines, outcome, deadline: deadline), output: run.text)
        }

        guard let after = await offCooperativePool({ scanner.scan().first }), after.problem == nil,
              let version = after.version, let newBinary = after.binary, let newTarget = after.target
        else {
            return .failed(message: "the script finished, but \(install.path) no longer reads as starship", output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            return .failed(message: "the script finished, but \(install.path) is still starship \(version)", output: run.text)
        }
        switch await verifier.verify(binary: newBinary, version: version, target: newTarget) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "the script finished, but \(reason)", output: run.text)
        }
    }

    /// Starship's script: a POSIX `sh` script that downloads from the project's
    /// releases and takes `-b` and `-v`. An error page is not run.
    static func isInstaller(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("#!/usr/bin/env sh") || text.hasPrefix("#!/bin/sh") else { return false }
        return text.contains(#"BASE_URL="https://github.com/starship/starship/releases""#)
            && text.contains("-b | --bin-dir)")
            && text.contains("-v | --version)")
    }

    /// The script's `x <reason>` line (its `error`), colour codes and the mark
    /// taken off; else the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut,
           // `tput sgr0` is `ESC ( B ESC [ m` on macOS; the shared strip leaves `ESC ( B`.
           let line = lines.map({ CLIToolCommandRunner.stripEscapes($0.replacingOccurrences(of: "\u{1B}(B", with: "")) })
               .last(where: { $0.hasPrefix("x ") }) {
            return HelmUpdater.withStatus(String(line.dropFirst(2)), outcome)
        }
        return HelmUpdater.withStatus(CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline), outcome)
    }
}
