import Foundation

/// Deno's row, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **The update is Deno's own `deno upgrade`**, on the installer's file. It
///    installs what `DenoRelease`'s channel names.
/// 2. **The trust rule** (`CLIToolTrust`): Deno is Developer ID signed by Deno
///    Land, and the file is run only with that Team ID and no quarantine.
/// 3. **Only a stable build is offered it.** `deno upgrade` installs the newest
///    stable release whatever build runs it, so on an LTS, RC or canary build it
///    would switch the channel. Such a build is reported, with no click: an RC
///    by its version, the others by what their `--version` prints. A file whose
///    `--version` disagrees with its bytes, or prints nothing readable, is not
///    run either.
/// 4. **Never downgrade.** `deno upgrade` installs the channel's version whenever
///    it differs from the running one (`find_latest_version_to_upgrade`), so a
///    build newer than the channel reads as `.ahead` and gets no click.
/// 5. **Never race an upgrade already running** (`DenoActivity`), nor run one in
///    a folder this user cannot write to.
///
/// Deno has no setting that turns `deno upgrade` off (`DENO_NO_UPDATE_CHECK`
/// only silences its notice), so there is no settings gate.
public struct DenoCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String

    let latest: Latest

    public init(release: DenoRelease = DenoRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: DenoInstall, busy: DenoActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .deno, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: install.reported?.channel, state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .deno(install))
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
        if install.isPrerelease {
            return verdict(.unknown, note: "a release candidate: deno upgrade would move it to the stable channel",
                           withheld: .unsupportedInstaller)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read Deno's release channel: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch DenoRelease.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        guard install.signature == .vendor else {
            return verdict(
                state, latest: newest,
                note: "not signed by Deno Land (Team \(DenoScanner.teamIdentifier)): "
                    + (install.signature?.rawValue ?? "unchecked"),
                withheld: .wrongSigner)
        }
        guard let reported = install.reported, reported.version == installed else {
            let printed = install.reported.map { "deno --version says \($0.version)" } ?? "deno --version printed no version"
            return verdict(.unknown, latest: newest, note: "\(printed), the file \(installed)", withheld: .versionMismatch)
        }
        guard reported.channel == "stable" else {
            return verdict(
                state, latest: newest,
                note: "a \(reported.channel) build: deno upgrade would move it to the stable channel",
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

    /// `~/.deno/bin/deno upgrade`: the newest stable release.
    static func updateCommand(for install: DenoInstall) -> CLIToolCommand {
        CLIToolCommand(executable: install.path, arguments: ["upgrade"], pathPrefix: nil)
    }
}
