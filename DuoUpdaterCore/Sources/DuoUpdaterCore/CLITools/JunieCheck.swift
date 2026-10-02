import Foundation

/// One Junie install's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules, as agreed for Junie (2026-10-01):
/// 1. **Read from disk, never run** (`JunieScanner`). The build `current` names
///    must be the build its bundle says it is; otherwise `.versionMismatch`.
/// 2. **Compared on the install's own channel**, the way the installer picks its
///    target (`JunieRelease`). EAP and nightly are offered like release.
/// 3. **One-click is the vendor's installer for that channel** — the documented
///    `curl -fsSL https://junie.jetbrains.com/install.sh | bash` (or `install-eap.sh`,
///    `install-nightly.sh`), which re-downloads the whole build (~330 MB) and checks
///    it against the feed's sha256. Junie's configuration reference also lists a
///    `junie update` command (`--force` "reinstall[s] the latest build of the
///    current channel when used with `junie update`", parameters page, 2026-10-02),
///    but that runs the Junie binary, which DuoUpdater does not do. Junie is never
///    run, so an ad hoc signed install (1543.24 shipped that way) is offered the
///    installer too; the build the installer leaves must then carry JetBrains'
///    Developer ID (`JunieUpdater`). `experimental` has no installer.
/// 4. **Junie's own update is respected**: `auto-update: false` reports the update
///    with the command; an update Junie has already downloaded (`pendingUpdate`) is
///    left to it; one in flight is not raced (`JunieActivity`).
public struct JunieCheck: Sendable {

    typealias Latest = @Sendable (String) async throws -> JunieRelease.Build

    let latest: Latest

    public init(release: JunieRelease = JunieRelease()) {
        self.init(latest: { try await release.latest(channel: $0) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    /// What the one-click stands for: the vendor's documented command, spelled as
    /// the vendor spells it. `JunieUpdater` runs its equivalent — it fetches the
    /// script over TLS itself and runs `/bin/bash <file>`, so a truncated download
    /// cannot half-run — and never this text. `pathPrefix` is `~/.local/bin`: with it
    /// on `PATH` the installer leaves the user's shell profile alone (`add_to_path`).
    static func command(installer: URL, launcher: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl", arguments: ["-fsSL", installer.absoluteString, "|", "bash"],
            pathPrefix: (launcher as NSString).deletingLastPathComponent)
    }

    public func status(of install: JunieInstall, settings: JunieSettings, busy: JunieActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .junie, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: install.channel, state: state, oneClick: oneClick, withheld: withheld,
                note: note, manualCommand: manualCommand, detail: .junie(install))
        }

        if let problem = install.problem {
            return verdict(.unknown, note: Self.describe(problem, install: install), withheld: .broken)
        }
        guard let installed = install.version, let channel = install.channel else {
            return verdict(.unknown, note: "no build to read", withheld: .versionUnreadable)
        }
        guard install.bundleVersion == installed else {
            return verdict(
                .unknown,
                note: "versions/\(installed) holds a junie.app that says it is \(install.bundleVersion ?? "nothing readable")",
                withheld: .versionMismatch)
        }
        let target: JunieRelease.Build
        do {
            target = try await latest(channel)
        } catch {
            return verdict(.unknown, note: "could not read the \(channel) channel: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch JunieRelease.compare(installed, target.version) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: target.version) }

        guard let installer = JunieRelease.installer(channel: channel) else {
            return verdict(
                state, latest: target.version,
                note: "the \(channel) channel has no installer (only release, eap and nightly do)",
                withheld: .unsupportedInstaller)
        }
        let command = Self.command(installer: installer, launcher: install.path)
        // Junie has the update already; its shim installs it at the next launch.
        // Running the installer now would not stop that: the shim applies the
        // manifest whatever build `current` names, so a staged build older than
        // the installer's would be put back on top of it.
        if let pending = install.pendingUpdate {
            return verdict(
                state, latest: target.version,
                note: "Junie has downloaded \(pending) and installs it the next time it starts",
                withheld: .staged)
        }
        if !settings.autoUpdate {
            return verdict(
                state, latest: target.version, note: "auto-update is off (\"auto-update\": false): reported only",
                withheld: .autoUpdateOff, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: target.version, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: target.version, oneClick: command)
    }

    static func describe(_ problem: JunieInstall.Problem, install: JunieInstall) -> String {
        switch problem {
        case .noCurrent: return "\(install.dataDirectory)/current is missing or not a symlink"
        case .versionUnreadable: return "\(install.dataDirectory)/current does not name a build"
        case .versionMissing: return "versions/\(install.version ?? "?") is missing"
        case .appMissing: return "versions/\(install.version ?? "?") has no junie.app to run"
        case .channelUnknown: return "nothing in versions/\(install.version ?? "?") says which channel it is from"
        case .channelConflict:
            return "versions/\(install.version ?? "?") names one channel in its channel file and another in its jar"
        }
    }
}
