import Foundation

/// Runs the one-click update a zoxide status offers — the vendor's installer,
/// pointed at the install's own directory — and checks what it left.
///
/// `status.oneClick` is the documented `curl -sSfL <install.sh> | sh` with
/// `--bin-dir`; this runs its equivalent without the pipe, as Junie's does
/// (`JunieUpdater`): the script is fetched whole into a private temporary
/// directory and run as `/bin/sh <file> --bin-dir <dir>`. What the script does,
/// from `install.sh` on `main` (read 2026-10-09):
/// - asks `api.github.com/repos/ajeetdsouza/zoxide/releases/latest` with its own
///   anonymous `curl`, and stops ("you have exceeded GitHub's API rate limit")
///   when GitHub refuses it;
/// - downloads that release's archive for this Mac into `mktemp -d
///   /tmp/zoxide_XXXXXX`, which it never removes, unpacks it, and `cp`s
///   `zoxide` over `--bin-dir/zoxide` (the same file, rewritten) and the man
///   pages into `--man-dir`;
/// - takes no version: whatever is latest when it runs is installed.
///
/// `--man-dir` is left at the installer's default, `~/.local/share/man`, the
/// directory the first install used with the default `--bin-dir`, which is the
/// only directory scanned. A sibling of the bin directory would be the same
/// place here, and nothing records a non-default man dir to reuse.
///
/// Asked again here, because each can change between the check and the click:
/// a run already under way (`ZoxideActivity`), the install (the same file and
/// version, writable, not a link), and the latest release, which must still be
/// newer and carry a digest for this Mac's archive.
///
/// The child's `PATH` is a private directory holding only the programs the
/// script runs. With no `sudo` on it, the script's `try_sudo` fallback stops
/// with "could not find the command `sudo`" instead of asking for a password,
/// should the directory stop being writable after the gate above.
///
/// After it ran, the trust rule is asked of what it left: a version newer than
/// the one it replaced, byte for byte that version's published build
/// (`ZoxideVerifier`). Anything else is a failure, not "updated".
public struct ZoxideUpdater: Sendable {

    /// The installer, as zoxide's README gives it.
    public static let installer = URL(string: "https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh")!

    /// The installer's file name starts with this, so `ZoxideActivity` can tell
    /// a run of it in the process table.
    static let scriptPrefix = "zoxide-install-"

    typealias BusyCheck = @Sendable () -> ZoxideActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: ZoxideScanner
    let check: ZoxideCheck
    let verifier: ZoxideVerifier
    let fetchScript: FetchScript
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    /// The programs put on the child's `PATH`, by name.
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 archive is ~1 MB. The deadline is for a child that hangs.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(5 * 60), killAfter: .seconds(5 * 60 + 30))

    /// The installer reads `_ZOXIDE_ARCH` before its arguments; a terminal-run
    /// `duo` may carry it, and it would pick another build than the one checked.
    static let overrides = ["_ZOXIDE_ARCH"]

    /// What `install.sh` runs on a Mac: `curl` (its downloader), `grep` and
    /// `cut` (reading the API's answer), `uname`/`sysctl` (the architecture),
    /// `mktemp`, `tar`, `mkdir`, `cp` and `chmod`. Nothing else, `sudo` least
    /// of all.
    static let defaultTools = [
        "curl": "/usr/bin/curl", "grep": "/usr/bin/grep", "cut": "/usr/bin/cut", "uname": "/usr/bin/uname",
        "sysctl": "/usr/sbin/sysctl", "mktemp": "/usr/bin/mktemp", "tar": "/usr/bin/tar", "mkdir": "/bin/mkdir",
        "cp": "/bin/cp", "chmod": "/bin/chmod",
    ]

    public init() {
        self.init(
            busy: { ZoxideActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: ZoxideScanner(),
            check: ZoxideCheck(),
            verifier: ZoxideVerifier(),
            fetchScript: { try await JunieUpdater.download($0) },
            // The installer's curl reads the proxy variables, which a GUI app
            // launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: ZoxideScanner,
        check: ZoxideCheck,
        verifier: ZoxideVerifier,
        fetchScript: @escaping FetchScript,
        environment: @escaping @Sendable () -> [String: String],
        tools: [String: String] = ZoxideUpdater.defaultTools,
        deadline: ChildProcess.Deadline = ZoxideUpdater.defaultDeadline
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
        guard status.oneClick != nil, case .zoxide(let install) = status.detail, let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.reread(install.path) }), now.problem == nil,
              now.version == before, now.binary == install.binary, !now.linked, let target = now.target
        else {
            return .failed(message: "not run: \(install.path) is no longer the zoxide that was checked", output: "")
        }
        let directory = ZoxideCheck.binDirectory(of: now)
        guard now.writable else {
            return .failed(message: "not run: the installer would need sudo to write \(directory)", output: "")
        }
        do {
            let latest = try await check.latest()
            guard VersionComparator.compare(before, latest.version) == .orderedAscending else {
                return .failed(message: "not run: zoxide's latest release is now \(latest.version), not newer than \(before)",
                               output: "")
            }
            guard latest.archiveDigests[target] != nil else {
                return .failed(message: "not run: the zoxide \(latest.version) release names no digest for its \(target) archive",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read zoxide's latest release: \(error)", output: "")
        }

        let script: Data
        do {
            script = try await fetchScript(Self.installer)
        } catch {
            return .failed(message: "could not download \(Self.installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script) else {
            return .failed(message: "\(Self.installer.absoluteString) did not answer with zoxide's installer", output: "")
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
            CLIToolCommand(executable: "/bin/sh", arguments: [file.path, "--bin-dir", directory], pathPrefix: nil),
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
              let version = after.version, let binary = after.binary, let newTarget = after.target
        else {
            return .failed(message: "the installer finished, but \(install.path) no longer reads as zoxide", output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still zoxide \(version)" : "went from zoxide \(before) to \(version)"
            return .failed(message: "the installer finished, but \(install.path) \(what)", output: run.text)
        }
        progress("Checking \(binary) against zoxide \(version) as published…")
        switch await verifier.verify(binary: binary, version: version, target: newTarget) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "the installer finished, but \(reason)", output: run.text)
        }
    }

    /// The script is zoxide's installer: a POSIX shell script that says so and
    /// takes `--bin-dir`. An error page or anything else is not run.
    static func isInstaller(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        return text.hasPrefix("#!/bin/sh") && text.contains("# The official zoxide installer.")
            && text.contains("--bin-dir)")
    }

    /// A private directory holding the script and `bin/`, a link to each tool,
    /// for the child's `PATH`. Blocking.
    static func prepare(script: Data, tools: [String: String]) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-zoxide-\(UUID().uuidString)", isDirectory: true)
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
    /// line on stderr (`err`), without the prefix, and its exit status; anything
    /// else falls to the shared rule. The whole output goes to the detail pane.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        let line = CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        guard !outcome.timedOut, !outcome.uncaughtSignal, line.hasPrefix("Error: ") else { return line }
        return "\(line.dropFirst("Error: ".count)) (install.sh exited with status \(outcome.terminationStatus))"
    }
}
