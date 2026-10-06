import Foundation

/// One Vite+ install's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`VitePlusScanner`): the version is the
///    active version's wrapper `package.json`.
/// 2. **Compared on npm's `latest`** (`VitePlusRelease`), and only toward a
///    newer version.
/// 3. **The update is Vite+'s own `vp upgrade <version>`**, pinned to the version
///    checked, on the install's own binary. It downloads the platform package,
///    checks it against the registry's integrity (and, from 1.0.0-rc.0, its
///    provenance), installs beside the old version and swaps `current`.
/// 4. **The trust rule** (`CLIToolTrust`): `vp` is only ever ad hoc signed, so it
///    is run only once a click has found it byte for byte its version's npm
///    package (`VitePlusVerifier`). A copy found not to be is withheld as
///    `.unverified`, and stays so until the file changes.
/// 5. **Only the install `vp` itself resolves**: a split install while
///    `~/.vite-plus` exists is reported, not updated (`shadowed`).
/// 6. **Never race a change already running** (`VitePlusActivity`).
///
/// Vite+ has no auto-update — its background check only prints a notice
/// (`VP_NO_UPDATE_CHECK` silences it) — so there is no settings gate.
public struct VitePlusCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String

    let latest: Latest

    public init(release: VitePlusRelease = VitePlusRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: VitePlusInstall, busy: VitePlusActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .vitePlus, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .vitePlus(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "current names no version with a bin/vp", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "the active version's package.json names no version", withheld: .versionUnreadable)
        case .shadowed, nil:
            break
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read vite-plus@latest: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if install.problem == .shadowed {
            return verdict(state, latest: newest,
                           note: "~/.vite-plus exists, so vp upgrade would update that install, not this one",
                           withheld: .unsupportedInstaller)
        }
        guard let binary = install.binary, install.platform != nil else {
            return verdict(state, latest: newest, note: "not an arm64 or x86_64 vp", withheld: .unverified)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        if install.hashVerdict == .differs {
            return verdict(state, latest: newest,
                           note: "not byte for byte the vp VoidZero published for \(installed): not run",
                           withheld: .unverified)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: Self.updateCommand(binary: binary, version: newest))
    }

    /// `<root>/<version>/bin/vp upgrade <latest>`. Pinned, so the click installs
    /// what was checked even if `latest` moves in between.
    static func updateCommand(binary: String, version: String) -> CLIToolCommand {
        CLIToolCommand(executable: binary, arguments: ["upgrade", version], pathPrefix: nil)
    }
}
