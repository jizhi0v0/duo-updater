import Foundation

/// Runs the one-click update a ghcup status offers — `~/.ghcup/bin/ghcup
/// upgrade`, ghcup's own command on its own file — and checks what it left.
///
/// Asked again here, because each can change between the check and the click:
/// - a change already running (`GhcupActivity`);
/// - the install: the same file (by its sha256), the version that was checked,
///   a directory this user can write to, not quarantined, and byte for byte its
///   version's published build (`GhcupVerifier`);
/// - the metadata, which must still name a version newer than the file.
///
/// **What the child can run.** `ghcup upgrade`'s own path runs only two
/// programs, both looked up on `PATH`: `sw_vers` (platform detection,
/// `GHCup.Query.System.getPlatform`) and `curl` (the metadata and the binary,
/// the default `downloader`); `gpg` too when the user's config turned GPG
/// checks on, and `wget` when it chose that downloader (v0.2.6.2 source). It
/// runs no compiler, `git` or `xcrun` — the programs whose stubs in `/usr/bin`
/// bring up the Xcode command line tools dialog — and names no absolute path
/// but `/usr/bin/xattr`, on toolchain installs only. So the child's `PATH` is
/// `~/.ghcup/bin` and a private directory holding only `curl` and `sw_vers`:
/// nothing else is reachable, and a config that wants `gpg` or `wget` fails
/// instead of finding one.
///
/// The environment drops every `GHCUP_*` and `XDG_*` variable — a terminal-run
/// `duo` may carry `GHCUP_INSTALL_BASE_PREFIX`, `GHCUP_USE_XDG_DIRS` or
/// `GHCUP_CURL_OPTS`, which would move the directories or the download — then
/// sets `GHCUP_SKIP_UPDATE_CHECK`, which skips ghcup's startup check of every
/// installed toolchain (and its note in `~/.ghcup/cache`); the upgrade itself
/// does not depend on it.
///
/// After it ran, the same rule is asked of what it left: a version newer than
/// the one it replaced, and byte for byte that version's published build.
/// Anything else is a failure, not "updated".
public struct GhcupUpdater: Sendable {

    typealias BusyCheck = @Sendable () -> GhcupActivity.Busy?

    let busy: BusyCheck
    let scanner: GhcupScanner
    let check: GhcupCheck
    let verifier: GhcupVerifier
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    /// The programs put on the child's `PATH`, by name.
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    /// The arm64 binary is 135 MB (0.2.6.2), fetched by curl; the deadline is for
    /// a child that hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(15 * 60), killAfter: .seconds(15 * 60 + 30))

    static let defaultTools = ["curl": "/usr/bin/curl", "sw_vers": "/usr/bin/sw_vers"]
    static let strippedPrefixes = ["GHCUP_", "XDG_"]

    public init() {
        self.init(
            busy: { GhcupActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: GhcupScanner(),
            check: GhcupCheck(),
            verifier: GhcupVerifier(),
            // ghcup's curl reads the proxy variables, which a GUI app launched by
            // launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: GhcupScanner,
        check: GhcupCheck,
        verifier: GhcupVerifier,
        environment: @escaping @Sendable () -> [String: String],
        tools: [String: String] = GhcupUpdater.defaultTools,
        deadline: ChildProcess.Deadline = GhcupUpdater.defaultDeadline
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
        guard let command = status.oneClick, case .ghcup(let install) = status.detail,
              let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.read() }), now.problem == nil,
              now.path == command.executable, now.version == before, now.sha256 == install.sha256,
              let target = now.target, !now.quarantined
        else {
            return .failed(message: "not run: \(install.path) is no longer the ghcup that was checked", output: "")
        }
        guard now.writable else {
            return .failed(message: "not run: ghcup upgrade could not write to \(now.directory)", output: "")
        }
        do {
            let newest = try await check.latest()
            guard VersionComparator.compare(before, newest) == .orderedAscending else {
                return .failed(message: "not run: ghcup's metadata now names \(newest), not a version newer than \(before)",
                               output: "")
            }
        } catch {
            return .failed(message: "not run: could not read ghcup's metadata: \(error)", output: "")
        }

        // The trust rule, at the click.
        progress("Checking \(now.path) against ghcup \(before) as the GHCup project published it…")
        switch await verifier.verify(sha256: now.sha256, version: before, target: target) {
        case .matches:
            break
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "not run: \(reason)", output: reason)
        }
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }

        let tools = self.tools
        let toolsDirectory: URL
        do {
            toolsDirectory = try await offCooperativePool { try Self.makeToolsDirectory(tools) }
        } catch {
            return .failed(message: "not run: could not prepare the update’s PATH: \(error)", output: "")
        }
        defer { try? FileManager.default.removeItem(at: toolsDirectory) }

        var environment = self.environment()
        for key in environment.keys where Self.strippedPrefixes.contains(where: { key.hasPrefix($0) }) {
            environment.removeValue(forKey: key)
        }
        environment["GHCUP_SKIP_UPDATE_CHECK"] = "1"
        environment["HOME"] = scanner.home.path
        environment["PATH"] = [command.pathPrefix, toolsDirectory.path].compactMap { $0 }.joined(separator: ":")
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

        // The trust rule again, on the file the upgrade left.
        guard let after = await offCooperativePool({ scanner.read() }), after.problem == nil,
              let version = after.version, let newTarget = after.target
        else {
            return .failed(message: "ghcup upgrade finished, but \(install.path) no longer reads as ghcup", output: run.text)
        }
        guard VersionComparator.compare(version, before) == .orderedDescending else {
            let what = version == before ? "is still ghcup \(version)" : "went from ghcup \(before) to \(version)"
            return .failed(message: "ghcup upgrade finished, but \(install.path) \(what)", output: run.text)
        }
        switch await verifier.verify(sha256: after.sha256, version: version, target: newTarget) {
        case .matches:
            return .updated(version: version)
        case .differs(let reason), .couldNotVerify(let reason):
            return .failed(message: "ghcup upgrade finished, but \(install.path) is \(reason)", output: run.text)
        }
    }

    /// A fresh directory holding a link to each tool, for the child's `PATH`.
    /// Blocking.
    static func makeToolsDirectory(_ tools: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-ghcup-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, target) in tools {
            try FileManager.default.createSymbolicLink(
                atPath: directory.appendingPathComponent(name).path, withDestinationPath: target)
        }
        return directory
    }

    /// The exit status after the tool's own line, so the row says both what it
    /// said and how it ended.
    static func exitSuffix(_ outcome: ChildProcess.Outcome) -> String {
        outcome.uncaughtSignal ? " (signal \(outcome.terminationStatus))" : " (exit \(outcome.terminationStatus))"
    }

    /// The line the row shows when `ghcup upgrade` failed: its last `[ Error ]`
    /// line, without the tag; anything else falls to the shared rule.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        if !outcome.timedOut, let line = lines.last(where: { $0.hasPrefix("[ Error ]") }) {
            let message = line.dropFirst("[ Error ]".count).trimmingCharacters(in: .whitespaces)
            if !message.isEmpty { return message + Self.exitSuffix(outcome) }
        }
        return CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
    }
}
