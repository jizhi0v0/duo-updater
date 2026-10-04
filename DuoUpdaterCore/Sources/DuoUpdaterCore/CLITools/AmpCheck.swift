import Foundation

/// Amp's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`AmpScanner`).
/// 2. **Compared on `cli-version.txt`** (`AmpRelease`), and only toward a newer
///    version — the click installs exactly the version it checked (`AMP_VERSION`).
/// 3. **One-click is the vendor's installer**, `curl -fsSL
///    https://ampcode.com/install.sh | bash`, which checks the binary's sha256
///    before putting it in place; `AmpUpdater` runs its equivalent without the
///    pipe, pinned. Amp is never run, so nothing of it needs trusting first;
///    what the installer leaves must carry Amp Frontier's Developer ID.
/// 4. **Amp's own setting is respected**: `"amp.updates.mode": "disabled"`
///    reports the update with the command; an install running is not raced
///    (`AmpActivity`).
public struct AmpCheck: Sendable {

    public static let installer = URL(string: "https://ampcode.com/install.sh")!

    typealias Latest = @Sendable () async throws -> String

    let latest: Latest

    public init(release: AmpRelease = AmpRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    static func command(version: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl", arguments: ["-fsSL", installer.absoluteString, "|", "AMP_VERSION=\(version)", "bash"],
            pathPrefix: nil)
    }

    public func status(of install: AmpInstall, settings: AmpSettings, busy: AmpActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .amp, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .amp(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no version is compiled into the file", withheld: .versionUnreadable)
        case nil:
            break
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read Amp's cli-version.txt: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch AmpRelease.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }
        let command = Self.command(version: newest)
        if !settings.autoUpdate {
            return verdict(state, latest: newest, note: "amp.updates.mode is disabled: reported only",
                           withheld: .autoUpdateOff, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }
}
