import Foundation

/// Runs the one-click update a Biome status offers — the vendor's installer,
/// pinned to the version checked and pointed at the install's own directory —
/// and checks what it left.
///
/// `status.oneClick` is the documented `curl -fsSL https://biomejs.dev/install |
/// bash -s -- --version <v>` with `--no-modify-path` and `BIOME_INSTALL_DIR`;
/// this runs its equivalent without the pipe, as zoxide's does
/// (`ZoxideUpdater`): the script is fetched whole into a private temporary
/// directory and run as `/bin/bash <file> --version <v> --no-modify-path`. What
/// the script does, from `biomejs.dev/install` (read 2026-10-21):
/// - with `--version`, asks nothing: it downloads
///   `github.com/biomejs/biome/releases/download/@biomejs/biome@<v>/biome-darwin-<arch>`
///   with `curl --fail --location` into `mktemp -d <dir>/.biome-install.XXXXXX`
///   (removed on exit), `chmod 755`s it and `mv`s it over `<dir>/biome`;
/// - first runs the installed `<dir>/biome --version`, and stops ("already
///   installed") when it prints the version asked for. The file was just
///   hashed to a published build (`BiomeScanner`), and is older, so it goes on;
/// - with `--no-modify-path`, touches no shell rc file. It has no `sudo`.
///
/// Asked again here, because each can change between the check and the click:
/// a run already under way (`BiomeActivity`), the install (the same file and
/// version, writable, not a link), and the latest version, which must still be
/// newer and carry a digest for this Mac's binary.
///
/// The child's `PATH` is a private directory holding only the programs the
/// script runs; `BIOME_VERSION`, `XDG_BIN_HOME` and the GitHub Actions
/// variables a terminal-run `duo` may carry are taken out.
///
/// After it ran, the trust rule is asked of what it left: a version newer than
/// the one it replaced, byte for byte that version's published build (the
/// rescan names the file's version by its sha256 alone). Anything else is a
/// failure, not "updated".
public struct BiomeUpdater: Sendable {

    /// The installer, as Biome's site gives it.
    public static let installer = URL(string: "https://biomejs.dev/install")!

    /// The installer's file name starts with this, so `BiomeActivity` can tell
    /// a run of it in the process table.
    static let scriptPrefix = "biome-install-"

    typealias BusyCheck = @Sendable () -> BiomeActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: BiomeScanner
    let check: BiomeCheck
    let fetchScript: FetchScript
    /// The child's environment before `HOME`, `PATH` and `BIOME_INSTALL_DIR` are set.
    let environment: @Sendable () -> [String: String]
    /// The programs put on the child's `PATH`, by name.
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 binary is ~74 MB (2.6.2). The deadline is for a child that hangs.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// Read by the installer before its arguments, or written to: a version or
    /// a directory other than the ones checked, or a `GITHUB_PATH` file appended to.
    static let overrides = ["BIOME_VERSION", "XDG_BIN_HOME", "GITHUB_ACTIONS", "GITHUB_PATH"]

    /// What the installer runs on a Mac when its stderr is not a terminal:
    /// `curl`, `uname`, `mkdir`, `mktemp`, `chmod`, `mv`, `rm` (its exit trap)
    /// and `cat` (the closing banner). Its progress bar's `sed` and `mkfifo`
    /// run only on a terminal, its `grep` only when it edits a shell rc file.
    /// Nothing else, `sudo` least of all.
    static let defaultTools = [
        "curl": "/usr/bin/curl", "uname": "/usr/bin/uname", "mkdir": "/bin/mkdir", "mktemp": "/usr/bin/mktemp",
        "chmod": "/bin/chmod", "mv": "/bin/mv", "rm": "/bin/rm", "cat": "/bin/cat",
    ]

    public init() {
        self.init(
            busy: { BiomeActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: BiomeScanner(),
            check: BiomeCheck(),
            fetchScript: { try await JunieUpdater.download($0) },
            // The installer's curl reads the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: BiomeScanner,
        check: BiomeCheck,
        fetchScript: @escaping FetchScript,
        environment: @escaping @Sendable () -> [String: String],
        tools: [String: String] = BiomeUpdater.defaultTools,
        deadline: ChildProcess.Deadline = BiomeUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.fetchScript = fetchScript
        self.environment = environment
        self.tools = tools
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard status.oneClick != nil, case .biome(let install) = status.detail, let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.reread(install.path) }), now.problem == nil,
              now.version == before, now.binary == install.binary, !now.linked, let target = now.target
        else {
            return .failed(message: "not run: \(install.path) is no longer the Biome that was checked", output: "")
        }
        let directory = BiomeCheck.installDirectory(of: now)
        guard now.writable else {
            return .failed(message: "not run: the installer cannot write \(directory) without sudo", output: "")
        }
        let latest: String
        do {
            latest = try await check.release.latestVersion()
            guard VersionComparator.compare(before, latest) == .orderedAscending else {
                return .failed(message: "not run: Biome's latest version is now \(latest), not newer than \(before)",
                               output: "")
            }
            guard try await check.release.digest(version: latest, target: target) != nil else {
                return .failed(message: "not run: the Biome \(latest) release names no digest for its \(BiomeRelease.assetName(target: target))",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read Biome's latest release: \(error)", output: "")
        }

        let script: Data
        do {
            script = try await fetchScript(Self.installer)
        } catch {
            return .failed(message: "could not download \(Self.installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script) else {
            return .failed(message: "\(Self.installer.absoluteString) did not answer with Biome's installer", output: "")
        }
        let tools = self.tools
        let scratch: URL
        let file: URL
        do {
            (scratch, file) = try await offCooperativePool { try Self.prepare(script: script, tools: tools) }
        } catch {
            return .failed(message: "not run: could not prepare the installer: \(error)", output: "")
        }
        defer { try? FileManager.default.removeItem(at: scratch) }

        var environment = self.environment()
        for key in Self.overrides { environment[key] = nil }
        environment["HOME"] = scanner.home.path
        environment["PATH"] = scratch.appendingPathComponent("bin").path
        environment["BIOME_INSTALL_DIR"] = directory
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/bash",
                           arguments: [file.path, "--version", latest, "--no-modify-path"], pathPrefix: nil),
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

        // The trust rule, on the file the installer left: its version is the
        // published build its sha256 equals, or none.
        progress("Checking \(install.path) against Biome \(latest) as published…")
        guard let after = await offCooperativePool({ scanner.reread(install.path) }) else {
            return .failed(message: "the installer finished, but \(install.path) is gone", output: run.text)
        }
        guard after.problem == nil, let version = after.version else {
            return .failed(message: "the installer finished, but \(install.path) is not the Biome \(latest) published on GitHub",
                           output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still Biome \(version)" : "went from Biome \(before) to \(version)"
            return .failed(message: "the installer finished, but \(install.path) \(what)", output: run.text)
        }
        return .updated(version: version)
    }

    /// The script is Biome's installer: a bash script that says so and takes
    /// `--version` and `--no-modify-path` and `BIOME_INSTALL_DIR`. An error page
    /// or anything else is not run.
    static func isInstaller(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        return text.hasPrefix("#!/usr/bin/env bash") && text.contains("readonly APP=\"biome\"")
            && text.contains("--no-modify-path)") && text.contains("BIOME_INSTALL_DIR")
            && text.contains("-v | --version)")
    }

    /// A private directory holding the script and `bin/`, a link to each tool,
    /// for the child's `PATH`. Blocking.
    static func prepare(script: Data, tools: [String: String]) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-biome-\(UUID().uuidString)", isDirectory: true)
        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        for (name, target) in tools {
            try FileManager.default.createSymbolicLink(
                atPath: bin.appendingPathComponent(name).path, withDestinationPath: target)
        }
        let file = directory.appendingPathComponent("\(scriptPrefix)\(UUID().uuidString).sh")
        try script.write(to: file, options: .atomic)
        return (directory, file)
    }

    /// The line the row shows when the installer failed: its `Error: <reason>`
    /// line on stderr (`fail`), without the prefix, and its exit status; anything
    /// else falls to the shared rule. The whole output goes to the detail pane.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        let line = CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        guard !outcome.timedOut, !outcome.uncaughtSignal, line.hasPrefix("Error: ") else { return line }
        return "\(line.dropFirst("Error: ".count)) (the installer exited with status \(outcome.terminationStatus))"
    }
}
