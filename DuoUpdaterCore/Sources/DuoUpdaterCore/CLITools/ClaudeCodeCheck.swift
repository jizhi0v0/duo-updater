import Foundation

/// One install's verdict: is there an update on the user's own channel, and may
/// DuoUpdater apply it — and if so, with exactly which command.
///
/// The rules, as agreed for this feature:
/// 1. **Same place, same installer, same channel.** A native install is updated by
///    `claude update`, an npm install by the npm of the node prefix it lives in,
///    and the channel is the user's `autoUpdatesChannel`. Nothing is ever moved
///    between installers or channels.
/// 2. **One-click only while auto-update is on.** With `DISABLE_AUTOUPDATER` or
///    `DISABLE_UPDATES` set the update is still reported, never offered.
/// 3. **Never race an update already running** (`ClaudeCodeActivity`).
public struct ClaudeCodeStatus: Sendable, Equatable, Codable {

    public enum State: String, Sendable, Codable {
        case upToDate
        case updateAvailable
        /// Newer than the channel — a `latest` build on a machine now on `stable`.
        case ahead
        /// No comparison possible; `note` says why.
        case unknown
    }

    /// A command to run, spelled out in full: no `PATH` lookup, no shell.
    public struct Command: Sendable, Equatable, Codable {
        public let executable: String
        public let arguments: [String]
        /// Put first on the child's `PATH`, so a `#!/usr/bin/env node` script
        /// finds the node of *this* prefix and not whichever one the GUI sees.
        public let pathPrefix: String?

        public var display: String { ([executable] + arguments).joined(separator: " ") }
    }

    public let install: ClaudeCodeInstall
    public let channel: ClaudeCodeSettings.Channel
    public let latestVersion: String?
    /// nil = not checked (no manifest, or not a binary the manifest describes);
    /// false = the file on disk is not the release its layout names.
    public let versionConfirmed: Bool?
    public let state: State
    /// Present only when every gate passed.
    public let oneClick: Command?
    /// Why there is no one-click, when there is an update and no command.
    public let note: String?
}

public struct ClaudeCodeCheck: Sendable {

    /// The version a channel points at, for an install's method.
    typealias Latest = @Sendable (ClaudeCodeSettings.Channel, ClaudeCodeInstall.Method) async throws -> String
    /// This Mac's artifact in a version's manifest.
    typealias Manifest = @Sendable (String) async throws -> ClaudeCodeRelease.Artifact

    let latest: Latest
    let manifest: Manifest

    public init(release: ClaudeCodeRelease = ClaudeCodeRelease()) {
        self.init(
            latest: { try await release.latestVersion(channel: $0, for: $1) },
            manifest: { try await release.artifact(version: $0, platform: ClaudeCodeRelease.platform) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest, manifest: @escaping Manifest) {
        self.latest = latest
        self.manifest = manifest
    }

    public func status(
        of install: ClaudeCodeInstall,
        settings: ClaudeCodeSettings,
        busy: ClaudeCodeActivity.Busy?
    ) async -> ClaudeCodeStatus {
        func verdict(
            _ state: ClaudeCodeStatus.State, latest: String? = nil, confirmed: Bool? = nil,
            oneClick: ClaudeCodeStatus.Command? = nil, note: String? = nil
        ) -> ClaudeCodeStatus {
            ClaudeCodeStatus(
                install: install, channel: settings.channel, latestVersion: latest,
                versionConfirmed: confirmed, state: state, oneClick: oneClick, note: note)
        }

        if let problem = install.problem {
            return verdict(.unknown, note: Self.describe(problem))
        }
        guard install.signature == .anthropic else {
            return verdict(.unknown, note: "not signed by Anthropic (Team \(ClaudeCodeScanner.teamIdentifier))")
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "version not readable from the layout")
        }
        let latest: String
        do {
            latest = try await self.latest(settings.channel, install.method)
        } catch {
            return verdict(.unknown, note: "could not read the \(settings.channel.rawValue) channel: \(error)")
        }
        let confirmed = await confirm(install, version: installed)

        var state: ClaudeCodeStatus.State
        switch VersionComparator.compare(installed, latest) {
        case .orderedSame: state = .upToDate
        case .orderedAscending: state = .updateAvailable
        case .orderedDescending: state = .ahead
        }
        // `minimumVersion` is a floor Claude Code's updater will not go below, so a
        // channel pointing under it is not an update the user can take.
        if state == .updateAvailable, let floor = settings.minimumVersion,
           VersionComparator.compare(latest, floor) == .orderedAscending {
            state = .upToDate
        }
        guard state == .updateAvailable else { return verdict(state, latest: latest, confirmed: confirmed) }

        if settings.updatesDisabled {
            return verdict(state, latest: latest, confirmed: confirmed, note: "updates are disabled (DISABLE_UPDATES)")
        }
        if settings.autoUpdatesDisabled {
            return verdict(state, latest: latest, confirmed: confirmed,
                           note: "auto-update is off (DISABLE_AUTOUPDATER): reported only")
        }
        if let busy {
            return verdict(state, latest: latest, confirmed: confirmed, note: busy.description)
        }
        if confirmed == false {
            return verdict(state, latest: latest, confirmed: confirmed,
                           note: "the file on disk is not the \(installed) release its layout names")
        }
        guard let command = Self.updateCommand(for: install, channel: settings.channel) else {
            return verdict(state, latest: latest, confirmed: confirmed,
                           note: "no supported way to update a \(install.method.rawValue) install: reported only")
        }
        return verdict(state, latest: latest, confirmed: confirmed, oneClick: command)
    }

    /// The vendor's documented update for each installer — and nothing for the
    /// ones we have not verified end to end.
    static func updateCommand(
        for install: ClaudeCodeInstall, channel: ClaudeCodeSettings.Channel
    ) -> ClaudeCodeStatus.Command? {
        let fm = FileManager.default
        switch install.method {
        case .native:
            // `claude update` reads `autoUpdatesChannel` and `minimumVersion` and
            // takes the native installer's own lock — the documented manual update.
            return .init(executable: install.path, arguments: ["update"], pathPrefix: nil)
        case .npm:
            // "To upgrade an npm installation, run
            // `npm install -g @anthropic-ai/claude-code@latest`" — with the dist-tag
            // that matches the user's channel, run by this prefix's own npm.
            // `--prefix` pins the destination: without it npm takes its global
            // directory from config (`~/.npmrc prefix=`, `NPM_CONFIG_PREFIX`) or
            // from where node really lives, either of which can be another place.
            guard let prefix = install.nodePrefix else { return nil }
            let bin = URL(fileURLWithPath: prefix).appendingPathComponent("bin")
            let node = bin.appendingPathComponent("node").path
            let npm = bin.appendingPathComponent("npm").path
            guard fm.isExecutableFile(atPath: node), fm.fileExists(atPath: npm) else { return nil }
            return .init(
                executable: node,
                arguments: [npm, "install", "-g", "--prefix", prefix, "@anthropic-ai/claude-code@\(channel.rawValue)"],
                pathPrefix: bin.path)
        case .pnpm, .bun, .unknown:
            return nil
        }
    }

    /// Hold the file against the manifest of the version its layout claims.
    /// Only the native binary and the npm package's linked binary are the
    /// manifest's artifact; anything else is left unchecked (nil).
    func confirm(_ install: ClaudeCodeInstall, version: String) async -> Bool? {
        guard let executable = install.executable,
              let artifact = try? await manifest(version)
        else { return nil }
        return ClaudeCodeRelease.sizeMatches(URL(fileURLWithPath: executable), artifact)
    }

    static func describe(_ problem: ClaudeCodeInstall.Problem) -> String {
        switch problem {
        case .executableMissing:
            return "the launcher points at a missing or empty file"
        case .nativeBinaryNotLinked:
            return "the package is installed but its native binary is not (postinstall was skipped)"
        }
    }
}
