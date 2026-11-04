import Foundation

/// Runs the one-click update a terminal-mac status offers: the release archive
/// the check compared, checked against GitHub's published digest, then its own
/// installer pointed at the prefix the install lives under.
///
/// `status.oneClick` is the release's `get.sh` piped to `bash`; this runs the
/// same two steps without the pipe, as Biome's and Obelus's updaters do — but
/// its bytes come from the archive itself rather than from a script fetched at
/// click time:
/// - download `terminal-mac-<version>-<build>-macos-arm64.zip` from the
///   **pinned** tag, never `releases/latest` (the latest may have moved between
///   the check and the click);
/// - refuse the archive unless its sha256 is the `digest` GitHub published for
///   it, so `install.sh` never runs out of bytes nobody vouched for;
/// - unpack it with `ditto` into a private directory and run its
///   `install.sh --prefix <prefix>` — the installer's `codesign --verify` then
///   checks the bundle it copies.
///
/// Asked again here, because each can change between the check and the click:
/// an install already under way (`TerminalMacActivity`), the install itself (the
/// same launcher and version, still writable), and the release (still newer, and
/// still carrying the archive).
///
/// Afterwards the launcher must resolve into a bundle of exactly the version and
/// build checked; anything else is a failure, not "updated". Old versions are
/// left where the installer left them — the vendor's layout, and the running
/// copy may be using one.
public struct TerminalMacUpdater: Sendable {

    /// The archive's `install.sh` is this, under the unpacked archive's stem:
    /// `terminal-mac-<version>-<build>-macos-arm64/install.sh`.
    static let installerName = "install.sh"

    /// The vendor's tools on the child's `PATH`. `PlistBuddy` is called by its
    /// absolute path; `bash` is the interpreter itself. No `sudo`.
    static let defaultTools = [
        "codesign": "/usr/bin/codesign", "shasum": "/usr/bin/shasum", "ditto": "/usr/bin/ditto",
        "dirname": "/usr/bin/dirname", "uname": "/usr/bin/uname", "sw_vers": "/usr/bin/sw_vers",
        "mkdir": "/bin/mkdir",
        "mv": "/bin/mv", "ln": "/bin/ln", "readlink": "/usr/bin/readlink", "mktemp": "/usr/bin/mktemp",
        "rmdir": "/bin/rmdir", "rm": "/bin/rm", "cat": "/bin/cat",
    ]

    /// Read by the installer before its argument, or by a shell it may inherit:
    /// a prefix other than the one checked.
    static let overrides = ["TERMINAL_MAC_PREFIX", "GITHUB_ACTIONS", "GITHUB_PATH"]

    /// The archive is under a megabyte; the deadline is for a child that hangs.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(5 * 60),
                                                       killAfter: .seconds(5 * 60 + 30))

    typealias BusyCheck = @Sendable (String?) -> TerminalMacActivity.Busy?
    typealias Download = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: TerminalMacScanner
    let release: TerminalMacRelease
    let download: Download
    /// The child's environment before `HOME` and `PATH` are set.
    let environment: @Sendable () -> [String: String]
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    public init() {
        self.init(
            busy: { prefix in TerminalMacActivity.busy(prefix: prefix, processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: TerminalMacScanner(),
            release: TerminalMacRelease(),
            download: { try await Self.get($0, purpose: .install) },
            // The installer runs no network command, but `codesign` and
            // `shasum` may read a proxy from the environment a terminal gave
            // `duo`; the GUI process has none. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.childEnvironmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: TerminalMacScanner,
        release: TerminalMacRelease,
        download: @escaping Download,
        environment: @escaping @Sendable () -> [String: String],
        tools: [String: String] = TerminalMacUpdater.defaultTools,
        deadline: ChildProcess.Deadline = TerminalMacUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.release = release
        self.download = download
        self.environment = environment
        self.tools = tools
        self.deadline = deadline
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard status.oneClick != nil, case .terminalMac(let install) = status.detail,
              let before = install.version, let beforeBuild = install.build, let prefix = install.prefix
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy(prefix) }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.reread(install.path) }), now.problem == nil,
              now.version == before, now.build == beforeBuild, now.binary == install.binary,
              now.prefix == prefix
        else {
            return .failed(message: "not run: \(install.path) is no longer the copy the check read", output: "")
        }
        guard now.writable else {
            return .failed(message: "not run: the installer cannot write \(prefix) without administrator rights",
                           output: "")
        }

        let published: TerminalMacRelease.Published
        do {
            published = try await release.latest()
        } catch {
            return .failed(message: "not run: could not read terminal-mac's latest release: \(error)", output: "")
        }
        guard VersionComparator.isNewer(published.side, than: now.side) else {
            return .failed(
                message: "not run: terminal-mac's latest release is now \(published.displayVersion), "
                    + "not newer than \(now.displayVersion)",
                output: "")
        }

        progress("Downloading terminal-mac \(published.displayVersion)…")
        let archive: Data
        do {
            archive = try await download(published.zip)
        } catch {
            return .failed(message: "could not download \(published.asset): \(error)", output: "")
        }
        let scratch: URL
        do {
            scratch = try await offCooperativePool { try Self.prepare(archive: archive, named: published.asset, tools: tools) }
        } catch {
            return .failed(message: "not run: could not prepare the archive: \(error)", output: "")
        }
        defer { try? FileManager.default.removeItem(at: scratch) }

        let archiveURL = scratch.appendingPathComponent(published.asset)
        let actual = await offCooperativePool { CLIToolTrust.sha256(of: archiveURL) }
        guard CLIToolTrust.matches(actual, published: published.digest) else {
            return .failed(
                message: "not run: the downloaded \(published.asset) is not the build GitHub published "
                    + "(sha256 \(actual ?? "unreadable"), expected \(published.digest))",
                output: "")
        }

        let unpacked = scratch.appendingPathComponent("unpacked", isDirectory: true)
        do {
            try await Self.unzip(archiveURL, into: unpacked)
        } catch {
            return .failed(message: "could not unpack \(published.asset): \(error)", output: "")
        }
        let installer = unpacked.appendingPathComponent("\(published.asset.dropLast(".zip".count))/\(Self.installerName)")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: installer.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return .failed(message: "\(published.asset) carries no \(Self.installerName)", output: "")
        }

        progress("Running terminal-mac \(published.displayVersion)'s installer…")
        let bin = scratch.appendingPathComponent("bin", isDirectory: true)
        var environment = self.environment()
        for key in Self.overrides { environment[key] = nil }
        environment["HOME"] = scanner.home.path
        environment["PATH"] = bin.path
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/bash", arguments: [installer.path, "--prefix", prefix],
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
            return .failed(message: CLIToolCommandRunner.failureMessage(run.lines, outcome, deadline: deadline),
                           output: run.text)
        }

        progress("Checking \(install.path) after the installer…")
        guard let after = await offCooperativePool({ scanner.reread(install.path) }) else {
            return .failed(message: "the installer finished, but \(install.path) is gone", output: run.text)
        }
        guard after.problem == nil, after.version == published.marketing, after.build == published.build else {
            let what = after.displayVersion
            return .failed(
                message: "the installer finished, but \(install.path) is \(what), not "
                    + "terminal-mac \(published.displayVersion)",
                output: run.text)
        }
        return .updated(version: after.displayVersion)
    }

    /// A private directory holding the archive, `bin/` with links to the
    /// installer's tools, and `unpacked/`. Blocking.
    static func prepare(archive: Data, named name: String, tools: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-terminal-mac-\(UUID().uuidString)", isDirectory: true)
        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        for (tool, target) in tools {
            try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent(tool).path,
                                                       withDestinationPath: target)
        }
        try archive.write(to: directory.appendingPathComponent(name), options: .atomic)
        return directory
    }

    /// `ditto -x -k`: the archive was written by `ditto`/`zip` on the vendor's
    /// Mac, and its extended attributes and symlinks are what `codesign --deep`
    /// later checks.
    static func unzip(_ archive: URL, into directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let outcome = try await ChildProcess.run(
            "/usr/bin/ditto", ["-x", "-k", archive.path, directory.path],
            environment: ["PATH": CLIToolCommandRunner.systemPath],
            standardOutput: .discard, standardError: .capture,
            deadline: ChildProcess.Deadline(terminateAfter: .seconds(60), killAfter: .seconds(65)),
            onCancel: .terminateChild)
        guard outcome.succeeded else {
            throw UnpackFailure(reason: String(decoding: outcome.standardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    struct UnpackFailure: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason.isEmpty ? "ditto failed" : reason }
    }

    /// The archive or an error. Never cached: the bytes decide the install.
    static func get(_ url: URL, purpose: RequestPurpose) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: purpose)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw TerminalMacRelease.Failure.http(status) }
        return data
    }
}
