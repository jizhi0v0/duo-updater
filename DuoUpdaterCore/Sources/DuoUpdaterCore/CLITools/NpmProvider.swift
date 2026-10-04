import Foundation

/// Global npm packages as one of the app's command-line tools: one group, a row
/// per package and prefix — its own scanner, check and updater (`Npm*`), seen
/// through `CLIToolProvider`.
public struct NpmProvider: CLIToolProvider {
    public var kind: CLIToolKind { .npm }

    let home: URL
    let prefixes: [NodePrefix]?

    /// `prefixes` replaces the discovery (`NodePrefixes`) — for a check against
    /// one scratch prefix.
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, prefixes: [NodePrefix]? = nil) {
        self.home = home
        self.prefixes = prefixes
    }

    var scanner: NpmScanner { NpmScanner(home: home, prefixes: prefixes) }

    public func scan() async -> [CLIToolSighting] {
        let scanner = self.scanner
        return await offCooperativePool { scanner.scan() }.map(Self.sighting)
    }

    /// What a verdict rests on besides the version: a link, an alias, a custom
    /// registry, the prefix's node and npm, and the package's own update settings.
    static func sighting(_ install: NpmInstall) -> CLIToolSighting {
        var own: String?
        switch install.ownUpdate {
        case .openclaw(let s):
            own = "openclaw:\(s.channel ?? "-"):\(s.autoUpdate.map(String.init) ?? "-"):\(s.supportsTag)"
        case .agentBrowser: own = "agent-browser"
        case nil: own = nil
        }
        return CLIToolSighting(
            kind: .npm, path: install.path, version: install.version,
            state: [install.linkTarget, install.manifestName, install.customRegistry?.url,
                    install.runtime.nodeSignature?.rawValue, install.runtime.nodeQuarantined ? "quarantined" : nil,
                    install.runtime.nodeVersion, install.runtime.npm, install.runtime.npmVersion, own]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let scanner = self.scanner
        let scanned = await offCooperativePool { scanner.scan() }
        let installs = await Self.withNodeVersions(scanned)
        // The busy verdicts resolve symlinks: worked out off the pool, before the check.
        let busy: [String: NpmActivity.Busy] = installs.isEmpty ? [:] : await offCooperativePool {
            let processes = NpmActivity.runningProcesses()
            return installs.reduce(into: [:]) { $0[$1.path] = NpmActivity.busy($1, processes: processes) }
        }
        let statuses = await NpmCheck().statuses(of: installs) { busy[$0.path] }
        return CLIToolReport(kind: .npm, statuses: statuses, context: .npm, sightings: scanned.map(Self.sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await NpmUpdater().update(status, progress: progress)
    }

    /// The GitHub Releases of the package's repository, for the versions the row
    /// is about (`NpmChangelog`).
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        guard case .npm(let package) = status.detail else { throw CLIToolReleaseNotesError.noSections }
        return try await NpmChangelog.fetch(
            repository: package.install.repository, name: package.install.manifestName ?? package.install.name,
            versions: package.pending, force: force)
    }

    // MARK: - Node versions

    /// Fills in the node version of each prefix whose layout does not name it
    /// (`/usr/local` from the nodejs.org installer, an npmrc prefix with its own
    /// node), by running that node's `--version` — only a Node.js-signed,
    /// unquarantined node (the trust rule), once per prefix.
    static func withNodeVersions(
        _ installs: [NpmInstall], read: @Sendable (String) async -> String? = nodeVersion
    ) async -> [NpmInstall] {
        var versions: [String: String?] = [:]
        var out: [NpmInstall] = []
        for install in installs {
            let runtime = install.runtime
            guard runtime.nodeVersion == nil, let node = runtime.node, runtime.nodeSignature == .vendor,
                  !runtime.nodeQuarantined
            else {
                out.append(install)
                continue
            }
            if versions[node] == nil { versions[node] = .some(await read(node)) }
            out.append(install.with(runtime: runtime.with(nodeVersion: versions[node] ?? nil)))
        }
        return out
    }

    /// `node --version` (`v24.13.0`) without the `v`, or nil.
    static func nodeVersion(_ node: String) async -> String? {
        guard let outcome = try? await ChildProcess.run(
                node, ["--version"], environment: ["PATH": CLIToolCommandRunner.systemPath], standardInput: Data(),
                standardError: .discard,
                deadline: ChildProcess.Deadline(terminateAfter: .seconds(10), killAfter: .seconds(12)),
                onCancel: .terminateChild),
              outcome.succeeded
        else { return nil }
        let text = String(decoding: outcome.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return NodePrefixes.versionName(text)
    }
}
