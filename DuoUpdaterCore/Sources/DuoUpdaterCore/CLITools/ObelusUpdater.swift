import Foundation

/// Runs the one-click update an Obelus status offers — the vendor's installer,
/// pointed at the row's binary, the install's own directory and the release
/// checked — and checks what it left.
///
/// `status.oneClick` is the documented `curl -fsSL <install.sh> | sh` with
/// `--bin` and `--dir`; this runs its equivalent without the pipe, as zoxide's
/// does (`ZoxideUpdater`): the script is fetched whole into a private temporary
/// directory and run as `/bin/sh <file> --bin <obg|ob> --version v<latest> --dir
/// <dir> --no-omarchy --no-desktop`. What the script does on a Mac, from
/// `contrib/install.sh` on `master` (read 2026-10-19):
/// - with `--version`, asks nothing about the latest release: it downloads that
///   tag's `SHA256SUMS` and `<bin>-<version>-universal2-apple-darwin.tar.xz`
///   into a `mktemp -d` it removes on exit, refuses an archive whose sha256 is
///   not `SHA256SUMS`'s, unpacks it with `tar -xJf`, and `install -m 755`s the
///   binary over `--dir/<bin>` (falling back to `cp` and `chmod`);
/// - never asks the GitHub API, and never uses `sudo`.
///
/// `--version` pins the run to the release this check compared and found
/// newer, so what the script installs is the version `ObelusVerifier` checks.
/// `--no-omarchy` and `--no-desktop` are no-ops on a Mac (both halves are
/// Linux's), given so the run never writes outside `--dir`.
///
/// Asked again here, because each can change between the check and the click:
/// a run already under way (`ObelusActivity`), the install (the same file and
/// version, writable, not a link), and the latest release, which must still be
/// newer and name this binary's archive.
///
/// The child's `PATH` is a private directory holding only the programs the
/// script runs.
///
/// After it ran, the trust rule is asked of what it left: a version newer than
/// the one it replaced, byte for byte that version's published build
/// (`ObelusVerifier`). Anything else is a failure, not "updated".
public struct ObelusUpdater: Sendable {

    /// The installer, as Obelus's README gives it.
    public static let installer = URL(string: "https://raw.githubusercontent.com/obelus-editor/obelus/master/contrib/install.sh")!

    /// The installer's file name starts with this, so `ObelusActivity` can tell
    /// a run of it in the process table.
    static let scriptPrefix = "obelus-install-"

    typealias BusyCheck = @Sendable () -> ObelusActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: ObelusScanner
    let check: ObelusCheck
    let verifier: ObelusVerifier
    let fetchScript: FetchScript
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    /// The programs put on the child's `PATH`, by name.
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    /// Each archive is 20–34 MB (v0.9.0 to v0.16.0). The deadline is for a child that hangs.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10 * 60), killAfter: .seconds(10 * 60 + 30))

    /// The installer reads `OBELUS_INSTALL_DIR` before its arguments; `--dir`
    /// overrides it, and it is dropped all the same.
    static let overrides = ["OBELUS_INSTALL_DIR"]

    /// What `install.sh` runs on a Mac: `curl` (its downloader), `shasum` (its
    /// sha256; `sha256sum` is asked for first and not given), `awk` (reading
    /// `SHA256SUMS`), `cut`, `uname`, `mktemp`, `rm`, `mkdir`, `tar`, `install`,
    /// and `cp`/`chmod` as `install`'s fallback.
    static let defaultTools = [
        "curl": "/usr/bin/curl", "shasum": "/usr/bin/shasum", "awk": "/usr/bin/awk", "cut": "/usr/bin/cut",
        "uname": "/usr/bin/uname", "mktemp": "/usr/bin/mktemp", "rm": "/bin/rm", "mkdir": "/bin/mkdir",
        "tar": "/usr/bin/tar", "install": "/usr/bin/install", "cp": "/bin/cp", "chmod": "/bin/chmod",
    ]

    public init() {
        self.init(
            busy: { ObelusActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: ObelusScanner(),
            check: ObelusCheck(),
            verifier: ObelusVerifier(),
            fetchScript: { try await JunieUpdater.download($0) },
            // The installer's curl reads the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: ObelusScanner,
        check: ObelusCheck,
        verifier: ObelusVerifier,
        fetchScript: @escaping FetchScript,
        environment: @escaping @Sendable () -> [String: String],
        tools: [String: String] = ObelusUpdater.defaultTools,
        deadline: ChildProcess.Deadline = ObelusUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.check = check
        self.verifier = verifier
        self.fetchScript = fetchScript
        self.environment = environment
        self.tools = tools
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard status.oneClick != nil, case .obelus(let install) = status.detail, let before = install.version
        else { return .notOffered }
        let name = install.name
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.reread(install.path) }), now.problem == nil,
              now.version == before, now.binary == install.binary, now.name == name, !now.linked
        else {
            return .failed(message: "not run: \(install.path) is no longer the \(name.rawValue) that was checked", output: "")
        }
        let directory = ObelusCheck.directory(of: now)
        guard now.writable else {
            return .failed(message: "not run: the installer cannot write \(directory)", output: "")
        }
        let target: String
        do {
            let latest = try await check.latest()
            guard VersionComparator.compare(before, latest.version) == .orderedAscending else {
                return .failed(message: "not run: Obelus's latest release is now \(latest.version), not newer than \(before)",
                               output: "")
            }
            guard latest.archiveDigests[name] != nil else {
                return .failed(message: "not run: the Obelus \(latest.version) SHA256SUMS names no \(ObelusRelease.archiveName(name, version: latest.version))",
                               output: "")
            }
            target = latest.version
        } catch {
            return .failed(message: "not run: could not read Obelus's latest release: \(error)", output: "")
        }

        let script: Data
        do {
            script = try await fetchScript(Self.installer)
        } catch {
            return .failed(message: "could not download \(Self.installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script) else {
            return .failed(message: "\(Self.installer.absoluteString) did not answer with Obelus's installer", output: "")
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
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/sh", arguments: [file.path] + Self.arguments(name, version: target, directory: directory),
                           pathPrefix: nil),
            environment: environment, deadline: deadline, progress: progress)
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

        // The trust rule, on the file the installer left.
        guard let after = await offCooperativePool({ scanner.reread(install.path) }), after.problem == nil,
              let version = after.version, let binary = after.binary
        else {
            return .failed(message: "the installer finished, but \(install.path) no longer reads as Obelus", output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still \(name.rawValue) \(version)" : "went from \(name.rawValue) \(before) to \(version)"
            return .failed(message: "the installer finished, but \(install.path) \(what)", output: run.text)
        }
        progress("Checking \(binary) against \(name.rawValue) \(version) as published…")
        switch await verifier.verify(binary: binary, name: name, version: version) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "the installer finished, but \(reason)", output: run.text)
        }
    }

    /// The script's arguments after its path.
    static func arguments(_ name: ObelusInstall.Binary, version: String, directory: String) -> [String] {
        ["--bin", name.rawValue, "--version", "v\(version)", "--dir", directory, "--no-omarchy", "--no-desktop"]
    }

    /// The script is Obelus's installer: a POSIX shell script for its repository
    /// that takes every option `arguments` passes. An error page or anything
    /// else is not run.
    static func isInstaller(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        return text.hasPrefix("#!/bin/sh") && text.contains("repository=obelus-editor/obelus")
            && ["--bin)", "--version)", "--dir)", "--no-omarchy)", "--no-desktop)"].allSatisfy(text.contains)
    }

    /// A private directory holding the script and `bin/`, a link to each tool,
    /// for the child's `PATH`. Blocking.
    static func prepare(script: Data, tools: [String: String]) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-obelus-\(UUID().uuidString)", isDirectory: true)
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

    /// The line the row shows when the installer failed: its `obelus: <reason>`
    /// line on stderr (`die`), without the prefix, and its exit status; anything
    /// else falls to the shared rule. The whole output goes to the detail pane.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        let line = CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        guard !outcome.timedOut, !outcome.uncaughtSignal, line.hasPrefix("obelus: ") else { return line }
        return "\(line.dropFirst("obelus: ".count)) (install.sh exited with status \(outcome.terminationStatus))"
    }
}
