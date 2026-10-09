import Foundation

/// One Helm install's verdict.
///
/// The rules:
/// 1. **Read from disk, never run** (`HelmScanner`).
/// 2. **Compared on the install's own major line** (`HelmRelease`): a v3 install
///    against `helm3-latest-version`, never against v4.
/// 3. **Helm has no self-update; one-click is its official script** for that
///    line, run as `HELM_INSTALL_DIR=<the install's own directory>
///    USE_SUDO=false` with `--version v<target> --no-sudo` (`HelmUpdater`), which
///    checks the archive's sha256 and `cp`s the binary over the file. Only when
///    this user may overwrite the file without `sudo` — the default
///    `/usr/local/bin` is root's on most Macs. There — the directory the script
///    defaults to and escalates for, and root's — the one-click is that
///    documented command run as root behind the administrator panel
///    (`CLIToolAdministratorRun`), after the same gates; anywhere else this user
///    cannot write, the update is reported with the command for the user to run.
/// 4. **The trust rule** (`CLIToolTrust`): helm is only ever ad hoc signed, and
///    the script runs the installed `helm version` before it replaces it, so the
///    file must be byte for byte its version's published build (`HelmVerifier`).
/// 5. **Never race a change already running** (`HelmActivity`).
public struct HelmCheck: Sendable {

    typealias Latest = @Sendable (_ major: Int) async throws -> String
    typealias KnownVerdict = @Sendable (_ binary: String, _ version: String, _ target: String) -> Bool?

    let latest: Latest
    let knownVerdict: KnownVerdict
    /// Whether the install's directory is root's `/usr/local/bin` — the script's
    /// own default, which it escalates for — so its documented command may run
    /// as root. A fixture directory in tests.
    let rootDirectory: @Sendable (HelmInstall) -> Bool

    public init(release: HelmRelease = HelmRelease()) {
        let verifier = HelmVerifier()
        self.init(latest: { try await release.latest(major: $0) },
                  knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) },
                  rootDirectory: { CLIToolAdministratorRun.isRootsDefault($0.directory) })
    }

    init(latest: @escaping Latest, knownVerdict: @escaping KnownVerdict,
         rootDirectory: @escaping @Sendable (HelmInstall) -> Bool = { _ in false }) {
        self.latest = latest
        self.knownVerdict = knownVerdict
        self.rootDirectory = rootDirectory
    }

    public func status(of install: HelmInstall, busy: HelmActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil,
            needsAdministrator: Bool = false
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .helm, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: install.major.map { "v\($0)" }, state: state, oneClick: oneClick, withheld: withheld,
                note: note, manualCommand: manualCommand,
                releaseNotesKey: install.major.map { "helm-v\($0)" }, detail: .helm(install),
                needsAdministrator: needsAdministrator)
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no helm module version in the file (builds before 3.20.0 carry none)",
                           withheld: .versionUnreadable)
        case .linked, nil:
            break
        }
        guard let installed = install.version, let binary = install.binary, let major = install.major,
              let installer = HelmRelease.installer(major: major)
        else {
            return verdict(.unknown, note: "not a Helm 3 or Helm 4 version", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest(major)
        } catch {
            return verdict(.unknown, note: "could not read helm\(major)-latest-version: \(error)",
                           withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if install.problem == .linked {
            return verdict(state, latest: newest,
                           note: "\(install.path) links to \(binary): the script would write through the link",
                           withheld: .unsupportedInstaller)
        }
        // Root's default directory: the documented command, as root, past the
        // same gates as below (the script runs the installed `helm version`).
        let asRoot = !install.writable && rootDirectory(install)
        if !install.writable, !asRoot {
            return verdict(state, latest: newest,
                           note: "the script would need sudo to replace \(install.path)",
                           withheld: .unsupportedInstaller, manualCommand: Self.documentedCommand(installer: installer))
        }
        guard let target = install.target else {
            return verdict(state, latest: newest, note: "not an arm64 or amd64 helm", withheld: .unverified)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        let knownVerdict = self.knownVerdict
        if await offCooperativePool({ knownVerdict(binary, installed, target) }) == false {
            return verdict(state, latest: newest,
                           note: "not byte for byte the helm \(installed) the Helm project published: not run",
                           withheld: .unverified)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        if asRoot {
            let command = Self.documentedCommand(installer: installer)
            return verdict(state, latest: newest, oneClick: command,
                           note: "runs as root after an administrator password: \(install.directory) is root's",
                           manualCommand: command, needsAdministrator: true)
        }
        return verdict(state, latest: newest,
                       oneClick: Self.updateCommand(installer: installer, directory: install.directory, version: newest))
    }

    /// The command Helm's install docs give, for the user to run in a terminal,
    /// where the script's `sudo` can ask for a password.
    static func documentedCommand(installer: URL) -> CLIToolCommand {
        CLIToolCommand(executable: "curl", arguments: ["-fsSL", installer.absoluteString, "|", "bash"], pathPrefix: nil)
    }

    /// What the one-click stands for, spelled as a shell would run it.
    /// `HelmUpdater` runs its equivalent — the script fetched over TLS into a
    /// file, then `/bin/bash <file> --version v<version> --no-sudo` with
    /// `HELM_INSTALL_DIR` and `USE_SUDO=false` in its environment — and never this
    /// text.
    static func updateCommand(installer: URL, directory: String, version: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl",
            arguments: ["-fsSL", installer.absoluteString, "|", "HELM_INSTALL_DIR=\(directory)", "USE_SUDO=false",
                        "bash", "-s", "--", "--version", "v\(version)", "--no-sudo"],
            pathPrefix: nil)
    }
}
