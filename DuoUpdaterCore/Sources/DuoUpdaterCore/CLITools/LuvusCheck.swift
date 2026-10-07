import Foundation

/// One Luvus install's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`LuvusScanner`): the version is compiled
///    into the file.
/// 2. **Compared on `luvus.dev/latest.json`** (`LuvusRelease`), what `luvus
///    update` reads, and only toward a newer version.
/// 3. **The update is Luvus's own `luvus update`**, on the install's own file.
///    It downloads the archive and its `.sha256`, checks one against the other,
///    and renames the new binary into place. It has no version argument and
///    installs only a strictly newer manifest version.
/// 4. **The trust rule** (`CLIToolTrust`): luvus is only ever ad hoc signed, so
///    it is run only when it is byte for byte its version's published build
///    (`LuvusVerifier`). Once that release's digest is known the check compares
///    the file here and withholds a copy that differs as `.unverified`; until
///    then the click downloads the archive and compares first.
/// 5. **Never through `sudo`**: `luvus update` falls back to `sudo install` and
///    `sudo mv` when it cannot write beside its file — `/usr/local/bin` owned by
///    root — which would put a password or Touch ID prompt in front of the user
///    from a background app. Such an install is reported, not updated.
/// 6. **Only what `luvus update` can update**: a link to another place, and the
///    releases before 0.12.0, which have no `luvus update`, are reported.
/// 7. **Never race a change already running** (`LuvusActivity`).
///
/// Luvus has no auto-update — its background check only shows a notice, and
/// `check_updates` in `~/.luvus/config.json` turns that notice off — so there is
/// no settings gate.
public struct LuvusCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String
    /// Whether the file is its version's published build, when the release's
    /// digest is already known; nil when it is not. Blocking.
    typealias KnownVerdict = @Sendable (_ binary: String, _ version: String, _ target: String) -> Bool?

    let latest: Latest
    let knownVerdict: KnownVerdict

    public init(release: LuvusRelease = LuvusRelease()) {
        let verifier = LuvusVerifier()
        self.init(latest: { try await release.latest() },
                  knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest, knownVerdict: @escaping KnownVerdict) {
        self.latest = latest
        self.knownVerdict = knownVerdict
    }

    public func status(of install: LuvusInstall, busy: LuvusActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .luvus, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .luvus(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no luvus version is compiled into the file", withheld: .versionUnreadable)
        case .unknownLocation, nil:
            break
        }
        guard let installed = install.version, let binary = install.binary else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read luvus.dev/latest.json: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if install.problem == .unknownLocation {
            return verdict(state, latest: newest,
                           note: "\(install.path) links to \(binary), which luvus update does not replace",
                           withheld: .unsupportedInstaller)
        }
        if !install.hasUpdateCommand {
            return verdict(state, latest: newest,
                           note: "luvus \(installed) predates luvus update (\(LuvusInstall.firstUpdatingVersion))",
                           withheld: .unsupportedInstaller)
        }
        guard let target = install.target else {
            return verdict(state, latest: newest, note: "not an arm64 or x86_64 luvus", withheld: .unverified)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        if !install.writable {
            return verdict(state, latest: newest,
                           note: "luvus update would need sudo to replace a file in \((binary as NSString).deletingLastPathComponent)",
                           withheld: .unsupportedInstaller)
        }
        let knownVerdict = self.knownVerdict
        if await offCooperativePool({ knownVerdict(binary, installed, target) }) == false {
            return verdict(state, latest: newest,
                           note: "not byte for byte the luvus \(installed) RizRiyz published: not run",
                           withheld: .unverified)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: Self.updateCommand(binary: binary))
    }

    /// `<binary> update`. luvus resolves its own path before it classifies it,
    /// so the file itself is run, not a link to it. Nothing goes on `PATH` here:
    /// `LuvusUpdater` gives the child a `PATH` of its own.
    static func updateCommand(binary: String) -> CLIToolCommand {
        CLIToolCommand(executable: binary, arguments: ["update"], pathPrefix: nil)
    }
}
