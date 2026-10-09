import Foundation

/// One Starship install's verdict.
///
/// The rules:
/// 1. **Read from disk, never run** (`StarshipScanner`).
/// 2. **Compared on GitHub's latest release** (`StarshipRelease`), what the
///    script installs.
/// 3. **Starship has no self-update; one-click is its official script**, run
///    as `install.sh -y -b <the install's own directory> -v v<target>`
///    (`StarshipUpdater`), when this user may write there without `sudo`. The
///    default `/usr/local/bin` is root's on most Macs; there — the directory the
///    script defaults to and escalates for, and root's — the one-click is the
///    documented command with the script's own `-y` (its one question reads
///    `/dev/tty`, which a run behind the panel has not got) run as root behind
///    the administrator panel (`CLIToolAdministratorRun`), after the same gates.
///    Anywhere else this user cannot write, the documented command is reported
///    for the user to run.
/// 4. **The trust rule** (`CLIToolTrust`): every build is held to the `.sha256`
///    its release publishes (`StarshipVerifier`), before the click and after.
///    The script checks no hash itself.
/// 5. **Never race a change already running** (`StarshipActivity`).
public struct StarshipCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String
    typealias KnownVerdict = @Sendable (_ binary: String, _ version: String, _ target: String) -> Bool?

    let latest: Latest
    let knownVerdict: KnownVerdict
    /// Whether the install's directory is root's `/usr/local/bin`, the script's
    /// default, which it escalates for. A fixture directory in tests.
    let rootDirectory: @Sendable (StarshipInstall) -> Bool

    public init(release: StarshipRelease = StarshipRelease()) {
        let verifier = StarshipVerifier()
        self.init(latest: { try await release.latest() },
                  knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) },
                  rootDirectory: { CLIToolAdministratorRun.isRootsDefault($0.directory) })
    }

    init(latest: @escaping Latest, knownVerdict: @escaping KnownVerdict,
         rootDirectory: @escaping @Sendable (StarshipInstall) -> Bool = { _ in false }) {
        self.latest = latest
        self.knownVerdict = knownVerdict
        self.rootDirectory = rootDirectory
    }

    public static let installer = URL(string: "https://starship.rs/install.sh")!

    public func status(of install: StarshipInstall, busy: StarshipActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil,
            needsAdministrator: Bool = false
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .starship, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .starship(install), needsAdministrator: needsAdministrator)
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no starship version is compiled into the file", withheld: .versionUnreadable)
        case .linked, nil:
            break
        }
        guard let installed = install.version, let binary = install.binary else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read Starship's latest release: \(error)",
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
                           note: "\(install.path) links to \(binary): the script would unpack over the link",
                           withheld: .unsupportedInstaller)
        }
        let asRoot = !install.writable && rootDirectory(install)
        if !install.writable, !asRoot {
            return verdict(state, latest: newest,
                           note: "the script would need sudo to replace \(install.path)",
                           withheld: .unsupportedInstaller, manualCommand: Self.documentedCommand)
        }
        guard let target = install.target else {
            return verdict(state, latest: newest, note: "not an arm64 or x86_64 starship", withheld: .unverified)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        let knownVerdict = self.knownVerdict
        if await offCooperativePool({ knownVerdict(binary, installed, target) }) == false {
            return verdict(state, latest: newest,
                           note: "not byte for byte the starship \(installed) published on GitHub: not run",
                           withheld: .unverified)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        if asRoot {
            return verdict(state, latest: newest, oneClick: Self.rootCommand,
                           note: "runs as root after an administrator password: \(install.directory) is root's",
                           manualCommand: Self.documentedCommand, needsAdministrator: true)
        }
        return verdict(state, latest: newest, oneClick: Self.updateCommand(directory: install.directory, version: newest))
    }

    /// The command starship.rs gives, for the user to run in a terminal, where
    /// the script's `sudo` can ask.
    static let documentedCommand = CLIToolCommand(
        executable: "curl", arguments: ["-sS", installer.absoluteString, "|", "sh"], pathPrefix: nil)

    /// What runs as root in root's `/usr/local/bin`: the documented command with
    /// the script's `-y`, and nothing else — its `BIN_DIR` default is that
    /// directory.
    static let rootCommand = CLIToolCommand(
        executable: "curl", arguments: ["-sS", installer.absoluteString, "|", "sh", "-s", "--", "-y"], pathPrefix: nil)

    /// What the one-click stands for; `StarshipUpdater` runs its equivalent from
    /// a fetched file, never this text.
    static func updateCommand(directory: String, version: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl",
            arguments: ["-sS", installer.absoluteString, "|", "sh", "-s", "--", "-y", "-b", directory, "-v", "v\(version)"],
            pathPrefix: nil)
    }
}
