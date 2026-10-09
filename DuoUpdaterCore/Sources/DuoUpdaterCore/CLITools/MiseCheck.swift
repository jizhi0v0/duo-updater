import Foundation

/// mise's row, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **The update is mise's own `mise self-update -y --no-plugins`**, on the
///    installer's file. `-y` because nothing can answer its prompt; and
///    `--no-plugins` because without it the command goes on to run `mise
///    plugins update` — the user's asdf/vfox plugins, not mise — which the
///    docs make optional ("Installed plugins are updated too unless you pass
///    `--no-plugins`"). mise's own automatic update passes the same flag.
/// 2. **The trust rule** (`CLIToolTrust`): mise is Developer ID signed by
///    Jeffrey Dickey, and the file is run — for `--version` too — only with that
///    Team ID and no quarantine.
/// 3. **The latest is the release `mise self-update` would pick**
///    (`MiseRelease`: the newest at least 24 hours old), so a release mise holds
///    back is never offered.
/// 4. **Never downgrade**: a build newer than that reads as `.ahead`. (mise
///    itself skips an older pick without a named version.)
/// 5. A packager's marker that turns `self-update` off, a folder this user
///    cannot write to, or an update already running: reported, no click.
public struct MiseCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String

    let latest: Latest

    public init(release: MiseRelease = MiseRelease()) {
        self.init(latest: { try await release.latest() })
    }

    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: MiseInstall, busy: MiseActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .mise, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .mise(install))
        }

        if install.problem == .executableMissing {
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        }
        // Its version is read by running it, so these come first.
        if install.quarantined {
            return verdict(.unknown, note: "quarantined, so not run", withheld: .unverified)
        }
        guard install.signature == .vendor else {
            return verdict(
                .unknown,
                note: "not signed by Jeffrey Dickey (Team \(MiseScanner.teamIdentifier)): "
                    + (install.signature?.rawValue ?? "unchecked") + "; not run",
                withheld: .wrongSigner)
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "mise --version printed no version", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read mise's release index: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch MiseRelease.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if let marker = install.selfUpdateDisabledBy {
            return verdict(state, latest: newest, note: "its packager turned mise self-update off (\(marker))",
                           withheld: .unsupportedInstaller)
        }
        guard install.writable else {
            return verdict(state, latest: newest, note: "its folder is not writable by this user",
                           withheld: .unsupportedInstaller)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: Self.updateCommand(for: install))
    }

    /// `~/.local/bin/mise self-update -y --no-plugins`.
    static func updateCommand(for install: MiseInstall) -> CLIToolCommand {
        CLIToolCommand(executable: install.path, arguments: ["self-update", "-y", "--no-plugins"], pathPrefix: nil)
    }
}
