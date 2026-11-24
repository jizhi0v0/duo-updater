import Foundation

public struct AntigravityCLIInstall: Sendable, Equatable, Codable {
    public static let teamIdentifier = "EQHXZ8M8AV"
    static let signingIdentifier = "cli"

    public let path: String
    public let version: String?
    public let signature: CLIToolTrust.Signature
    public let quarantined: Bool
    public let writableDirectory: Bool

    public init(
        path: String, version: String?, signature: CLIToolTrust.Signature,
        quarantined: Bool = false, writableDirectory: Bool = true
    ) {
        self.path = path
        self.version = version
        self.signature = signature
        self.quarantined = quarantined
        self.writableDirectory = writableDirectory
    }

    var command: CLIToolCommand {
        CLIToolCommand(executable: path, arguments: ["update"], pathPrefix: nil,
                       shellLine: NvmCheck.shellQuoted(path) + " update")
    }
}

/// The standalone Antigravity CLI (agy). Google's bootstrapper puts a flat
/// executable in ~/.local/bin and exits if it is already there. Its built-in
/// updater replaces that file in place and arbitrates concurrent updates.
public struct AntigravityCLIProvider: CLIToolProvider {
    public let kind: CLIToolKind = .antigravityCLI

    let home: URL
    let session: URLSession
    let signature: @Sendable (URL) -> CLIToolTrust.Signature
    let readVersion: @Sendable (URL, URL) async -> String?

    public init() {
        self.init(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    init(
        home: URL, session: URLSession = .updates,
        signature: @escaping @Sendable (URL) -> CLIToolTrust.Signature = {
            CLIToolTrust.signature(of: $0, teamIdentifier: AntigravityCLIInstall.teamIdentifier,
                                   signingIdentifier: AntigravityCLIInstall.signingIdentifier)
        },
        readVersion: @escaping @Sendable (URL, URL) async -> String? = { await Self.runVersion($0, home: $1) }
    ) {
        self.home = home
        self.session = session
        self.signature = signature
        self.readVersion = readVersion
    }

    var path: URL { home.resolvingSymlinksInPath().appendingPathComponent(".local/bin/agy") }

    func installed() async -> AntigravityCLIInstall? {
        let executable = path
        guard let (signature, quarantined, writable) = await offCooperativePool({
            () -> (CLIToolTrust.Signature, Bool, Bool)? in
            let files = FileManager.default
            // This is the standalone installer's own directory. A launcher
            // pointing into another install (such as a Homebrew cask) is not it.
            guard executable.resolvingSymlinksInPath().path == executable.path,
                  (try? files.attributesOfItem(atPath: executable.path)[.type] as? FileAttributeType) == .typeRegular,
                  files.isExecutableFile(atPath: executable.path)
            else { return nil }
            return (self.signature(executable), CLIToolTrust.hasQuarantine(executable),
                    files.isWritableFile(atPath: executable.deletingLastPathComponent().path))
        }) else { return nil }
        let version = signature == .vendor && !quarantined ? await readVersion(executable, home) : nil
        return AntigravityCLIInstall(path: executable.path, version: version, signature: signature,
                                     quarantined: quarantined, writableDirectory: writable)
    }

    /// --version printed only the bare version on both tested stable builds,
    /// including with no network or filesystem writes permitted.
    static func runVersion(
        _ executable: URL, home: URL, deadline: ChildProcess.Deadline = FxScanner.versionDeadline
    ) async -> String? {
        guard let outcome = try? await ChildProcess.run(
            executable.path, ["--version"],
            environment: ["PATH": CLIToolCommandRunner.systemPath, "HOME": home.path],
            workingDirectory: home, standardOutput: .capture, standardError: .discard,
            deadline: deadline, onCancel: .terminateChild),
              outcome.succeeded, !outcome.timedOut
        else { return nil }
        let text = String(decoding: outcome.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stableVersion(text) == nil ? nil : text
    }

    func sighting(_ install: AntigravityCLIInstall) -> CLIToolSighting {
        CLIToolSighting(kind: kind, path: install.path, version: install.version,
                        state: "\(install.signature.rawValue)|\(install.quarantined)|\(install.writableDirectory)")
    }

    public func scan() async -> [CLIToolSighting] {
        await installed().map { [sighting($0)] } ?? []
    }

    public func check() async -> CLIToolReport {
        guard let install = await installed() else {
            return CLIToolReport(kind: kind, statuses: [], context: .antigravityCLI, sightings: [])
        }
        let status = await status(of: install, autoUpdateOff: Self.autoUpdateOff) { try await latest() }
        return CLIToolReport(kind: kind, statuses: [status], context: .antigravityCLI, sightings: [sighting(install)])
    }

    func status(
        of install: AntigravityCLIInstall, autoUpdateOff: Bool,
        latest: () async throws -> NpmVersion
    ) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: NpmVersion? = nil, oneClick: CLIToolCommand? = nil,
            withheld: CLIToolWithheld? = nil, note: String? = nil, manual: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(kind: kind, path: install.path, installedVersion: install.version,
                          latestVersion: latest?.description, channel: nil, state: state, oneClick: oneClick,
                          withheld: withheld, note: note, manualCommand: manual, detail: .antigravityCLI(install))
        }

        guard install.signature == .vendor else { return verdict(.unknown, withheld: .wrongSigner) }
        guard !install.quarantined else { return verdict(.unknown, withheld: .unverified) }
        guard let version = install.version.flatMap(Self.stableVersion) else {
            return verdict(.unknown, withheld: .versionUnreadable)
        }
        let available: NpmVersion
        do {
            available = try await latest()
        } catch {
            return verdict(.unknown, withheld: .channelUnreadable, note: "Could not read Antigravity CLI's manifest: \(error)")
        }
        if version == available { return verdict(.upToDate, latest: available) }
        if version > available { return verdict(.ahead, latest: available) }
        if autoUpdateOff {
            return verdict(.updateAvailable, latest: available, withheld: .autoUpdateOff, manual: install.command)
        }
        guard install.writableDirectory else {
            return verdict(.updateAvailable, latest: available, withheld: .unsupportedInstaller,
                           note: "The installation directory is not writable", manual: install.command)
        }
        return verdict(.updateAvailable, latest: available, oneClick: install.command)
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        guard case .antigravityCLI(let previous) = status.detail, status.oneClick == previous.command,
              let before = previous.version.flatMap(Self.stableVersion), !Self.autoUpdateOff else { return .notOffered }
        guard let current = await installed(), current.path == previous.path, current.version == previous.version,
              current.writableDirectory else {
            return .failed(message: "The Antigravity CLI install changed since the check", output: "")
        }

        // Preserve proxy configuration for Go's HTTP client, without passing
        // credentials for agent sessions or environment overrides to the updater.
        var environment = ProcessInfo.processInfo.childEnvironmentWithSystemProxy.filter {
            ["http_proxy", "https_proxy", "no_proxy", "tmpdir"].contains($0.key.lowercased())
        }
        environment["HOME"] = home.path
        environment["PATH"] = CLIToolCommandRunner.systemPath
        let childEnvironment = environment
        let deadline = ChildProcess.Deadline(terminateAfter: .seconds(30 * 60), killAfter: .seconds(30 * 60 + 30))
        do {
            return try await InstallCommit.run("agy update", landed: { outcome in
                if case .busy = outcome { return false }
                return true
            }) {
                let run = await CLIToolCommandRunner.run(
                    current.command, environment: childEnvironment, deadline: deadline,
                    standardInput: Data(), workingDirectory: home, progress: progress)
                switch run.result {
                case .couldNotStart(let error):
                    return .failed(message: error, output: run.text)
                case .finished(let outcome):
                    guard outcome.succeeded else {
                        if !outcome.timedOut, run.lines.contains("Error: update already in progress") {
                            return .busy("Antigravity CLI is already updating")
                        }
                        return .failed(message: CLIToolCommandRunner.failureMessage(run.lines, outcome, deadline: deadline),
                                       output: run.text)
                    }
                    return Self.updated(before: before, after: await installed()?.version, output: run.text)
                }
            }
        } catch {
            return .failed(message: String(describing: error), output: "")
        }
    }

    static func updated(before: NpmVersion, after: String?, output: String) -> CLIToolUpdateOutcome {
        guard let after, let version = stableVersion(after), version > before else {
            return .failed(message: "Antigravity CLI did not report a verified newer version after updating", output: output)
        }
        return .updated(version: after)
    }

    static var autoUpdateOff: Bool {
        ProcessInfo.processInfo.environment["AGY_CLI_DISABLE_AUTO_UPDATE"]?.lowercased() == "true"
    }

    // History: docs/app-audits/antigravity-cli.md#历史与实测
    static let manifest = URL(string:
        "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/darwin_arm64.json")!

    static func stableVersion(_ text: String) -> NpmVersion? {
        guard let version = NpmVersion(text), !version.isPrerelease, text == version.description else { return nil }
        return version
    }

    struct Manifest: Decodable {
        let version: NpmVersion

        private enum CodingKeys: String, CodingKey { case version }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let text = try values.decode(String.self, forKey: .version)
            guard let version = AntigravityCLIProvider.stableVersion(text) else {
                throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Expected a stable agy version")
            }
            self.version = version
        }
    }

    func latest() async throws -> NpmVersion {
        var request = URLRequest(url: Self.manifest, cachePolicy: URLRequest.versionFeedCachePolicy, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.countedData(for: request, purpose: .versionCheck)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CLIToolReleaseNotesError.status(http, url: Self.manifest)
        }
        return try JSONDecoder().decode(Manifest.self, from: bytes).version
    }

    static let changelog = URL(string:
        "https://raw.githubusercontent.com/google-antigravity/antigravity-cli/refs/heads/main/CHANGELOG.md")!

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        let request = URLRequest(url: Self.changelog, cachePolicy: force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy,
                                 timeoutInterval: 15)
        let (bytes, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CLIToolReleaseNotesError.status(http, url: Self.changelog)
        }
        let changelog = await offCooperativePool { AtuinChangelog.parse(String(decoding: bytes, as: UTF8.self)) }
        guard let changelog else { throw CLIToolReleaseNotesError.noSections }
        return changelog
    }
}
