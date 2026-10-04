import Foundation

/// Runs the one-click update Amp's row offers — the vendor's installer, pinned to
/// the checked version — and checks what it left.
///
/// `status.oneClick` is `curl -fsSL https://ampcode.com/install.sh | AMP_VERSION=<v>
/// bash`; this runs its equivalent without the pipe: it fetches the script itself
/// (TLS, the whole body or an error) and runs `/bin/bash <file>` with
/// `AMP_VERSION` set. What the script does (read 2026-10-04): downloads the
/// release's sha256 and the gzipped binary from `static.ampcode.com/cli/<v>/`,
/// checks the decompressed bytes against it (and the minisign signature when
/// `minisign` is installed), renames it over `~/.amp/bin/amp`, and links
/// `~/.local/bin/amp` to it — appending `~/.local/bin` to a shell profile only
/// when no preferred directory is on `PATH`, which is why the child's `PATH`
/// starts with `~/.local/bin`.
///
/// Gates asked again at the click: an install running (`AmpActivity`),
/// `amp.updates.mode`, the install itself, and `cli-version.txt`, which must
/// still name a version newer than the installed one. Afterwards the file must be
/// that version and carry Amp Frontier's Developer ID (Team `PZT9BJUAA5`).
public struct AmpUpdater: Sendable {

    static let scriptName = "amp-install.sh"

    typealias BusyCheck = @Sendable () -> AmpActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: AmpScanner
    let check: AmpCheck
    let environment: @Sendable () -> [String: String]
    let settings: @Sendable () -> AmpSettings
    let fetchScript: FetchScript
    let deadline: ChildProcess.Deadline

    /// The binary is ~109 MB (~40 MB gzipped). The deadline is for a child that
    /// hangs, not for a slow one.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(20 * 60), killAfter: .seconds(20 * 60 + 30))

    /// Where the installer would install from or to, other than what was checked:
    /// another storage or site (`AMP_STORAGE_BASE`, `AMP_URL`), another home
    /// (`AMP_HOME`), a pinned version (`AMP_VERSION`, set here to the checked one).
    static let overrides = ["AMP_STORAGE_BASE", "AMP_URL", "AMP_HOME", "AMP_VERSION"]

    public init() {
        let scanner = AmpScanner()
        self.init(
            busy: { AmpActivity.busy(root: scanner.root, processes: NpmActivity.runningProcesses()) },
            scanner: scanner,
            check: AmpCheck(),
            // The installer runs curl, which reads `https_proxy`; a GUI app has
            // none. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            settings: { AmpSettings.read(home: scanner.home) },
            fetchScript: { try await AmpUpdater.download($0) })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: AmpScanner,
        check: AmpCheck,
        environment: @escaping @Sendable () -> [String: String],
        settings: @escaping @Sendable () -> AmpSettings = { AmpSettings() },
        fetchScript: @escaping FetchScript,
        deadline: ChildProcess.Deadline = AmpUpdater.defaultDeadline
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
        guard status.oneClick != nil, case .amp(let install) = status.detail, let before = install.version
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let settings = self.settings
        guard await offCooperativePool({ settings() }).autoUpdate else { return .notOffered }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.scan() }), now.path == install.path, now.problem == nil,
              now.version == before
        else {
            return .failed(message: "not run: \(install.path) is no longer the Amp that was checked", output: "")
        }
        let target: String
        do {
            target = try await check.latest()
        } catch {
            return .failed(message: "not run: could not read Amp's cli-version.txt: \(error)", output: "")
        }
        guard AmpRelease.compare(before, target) == .orderedAscending else {
            return .failed(message: "not run: Amp's latest is now \(target), not a version newer than \(before)", output: "")
        }

        let script: Data
        do {
            script = try await fetchScript(AmpCheck.installer)
        } catch {
            return .failed(message: "could not download \(AmpCheck.installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script) else {
            return .failed(message: "\(AmpCheck.installer.absoluteString) did not answer with the Amp installer", output: "")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-amp-\(UUID().uuidString)", isDirectory: true)
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
        environment["AMP_VERSION"] = target
        environment["HOME"] = scanner.home.path
        // ~/.local/bin first: the installer links there and edits no profile.
        let localBin = scanner.home.appendingPathComponent(".local/bin").path
        environment["PATH"] = CLIToolCommandRunner.path(prefix: localBin)
        environment["TMPDIR"] = directory.path + "/"
        environment["NO_COLOR"] = "1"
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/bash", arguments: [file.path], pathPrefix: localBin),
            environment: environment, deadline: deadline, progress: progress)
        let outcome: ChildProcess.Outcome
        switch run.result {
        case .couldNotStart(let error):
            return .failed(message: "could not run /bin/bash: \(error)", output: run.text)
        case .finished(let finished):
            outcome = finished
        }
        guard outcome.succeeded else {
            return .failed(message: CLIToolCommandRunner.failureMessage(run.lines, outcome, deadline: deadline),
                           output: run.text)
        }
        let after = await offCooperativePool { scanner.scan().map(scanner.withSignature) }
        return Self.verdict(after: after, target: target, output: run.text)
    }

    /// What the installer left, judged: the version asked for, signed by Amp Frontier.
    static func verdict(after: AmpInstall?, target: String, output: String) -> CLIToolUpdateOutcome {
        guard let after, after.problem == nil, let version = after.version else {
            return .failed(message: "the installer finished, but ~/.amp/bin/amp no longer reads as Amp", output: output)
        }
        guard version == target else {
            return .failed(message: "the installer finished, but Amp is \(version), not \(target)", output: output)
        }
        guard after.signature == .vendor else {
            return .failed(
                message: "Amp \(version) is not signed by Amp Frontier (Team \(AmpScanner.teamIdentifier)): "
                    + (after.signature?.rawValue ?? "unchecked"),
                output: output)
        }
        return .updated(version: version)
    }

    /// The script is Amp's installer: bash, installing into `$AMP_HOME/bin` from
    /// `static.ampcode.com` (lines 5–7 of install.sh on 2026-10-04).
    static func isInstaller(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("#!/usr/bin/env bash") || text.hasPrefix("#!/bin/bash") else { return false }
        let lines = Set(text.split(whereSeparator: \.isNewline).map(String.init))
        return lines.contains(#"AMP_HOME="${AMP_HOME:-$HOME/.amp}""#)
            && lines.contains(#"AMP_STORAGE_BASE="${AMP_STORAGE_BASE:-https://static.ampcode.com}""#)
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .install)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AmpRelease.Failure.http(status) }
        return data
    }
}
