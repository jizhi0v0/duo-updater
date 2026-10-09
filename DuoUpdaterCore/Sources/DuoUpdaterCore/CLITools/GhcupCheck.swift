import Foundation

/// One ghcup install's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`GhcupScanner`): the version the file claims
///    is a candidate, and its sha256 must be that version's published one
///    (`GhcupVerifier`, `SHA256SUMS`) — which names the version and vouches for
///    the bytes in one step. ghcup is only ever ad hoc signed, so a file that is
///    not its version's published build is `.unverified` and nothing of it is
///    run (`CLIToolTrust`).
/// 2. **Compared on ghcup's own metadata** (`GhcupRelease`): the `GHCup` version
///    tagged `Latest`, what `ghcup upgrade` installs, and only toward a newer one.
/// 3. **The update is ghcup's own `ghcup upgrade`**, which downloads that
///    version's binary, checks it against the metadata's sha256 and writes it
///    over `~/.ghcup/bin/ghcup` — never the bootstrap script, which asks
///    questions, edits the shell rc files and installs toolchains.
/// 4. **Never race a change already running** (`GhcupActivity`).
///
/// ghcup has no auto-update: its startup check only prints a notice, which
/// `GHCUP_SKIP_UPDATE_CHECK` (an environment variable, invisible to a GUI
/// process) silences. There is no settings gate.
public struct GhcupCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String
    typealias Verify = @Sendable (_ sha256: String?, _ version: String, _ target: String) async -> UvVerifier.Result

    let latest: Latest
    let verify: Verify

    public init(release: GhcupRelease = GhcupRelease()) {
        let verifier = GhcupVerifier()
        self.init(latest: { try await release.latest() },
                  verify: { await verifier.verify(sha256: $0, version: $1, target: $2) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest, verify: @escaping Verify) {
        self.latest = latest
        self.verify = verify
    }

    public func status(of install: GhcupInstall, busy: GhcupActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .ghcup, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .ghcup(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .link:
            return verdict(.unknown, note: "a link, which ghcup upgrade would replace with a file",
                           withheld: .unsupportedInstaller)
        case .versionUnreadable:
            return verdict(.unknown, note: "no ghcup version in the file", withheld: .versionUnreadable)
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
            return verdict(.unknown, note: "could not read ghcup's metadata: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        guard let target = install.target else {
            return verdict(state, latest: newest, note: "not an arm64 or x86_64 ghcup", withheld: .unverified)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        if !install.writable {
            return verdict(state, latest: newest, note: "ghcup upgrade could not write to \(install.directory)",
                           withheld: .unsupportedInstaller)
        }
        // A 5 KB file per version, remembered: the check itself can ask it. When
        // it cannot be had, the click asks again before anything runs.
        if case .differs = await verify(install.sha256, installed, target) {
            return verdict(state, latest: newest,
                           note: "not byte for byte the ghcup \(installed) the GHCup project published: not run",
                           withheld: .unverified)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: Self.updateCommand(for: install))
    }

    /// `~/.ghcup/bin/ghcup upgrade`, with that directory first on `PATH` so ghcup
    /// finds itself there and does not warn that it is not on `PATH`.
    static func updateCommand(for install: GhcupInstall) -> CLIToolCommand {
        CLIToolCommand(executable: install.path, arguments: ["upgrade"], pathPrefix: install.directory)
    }
}
