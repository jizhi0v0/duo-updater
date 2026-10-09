import Foundation

/// One Lorca CLI install's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`LorcaScanner`): the version is compiled
///    into the file.
/// 2. **Compared on the signed `lorca-cli.json`** (`LorcaRelease`), what `lorca
///    update` reads, and only toward a newer version.
/// 3. **The update is Lorca's own `lorca update`**, on the install's own file.
///    It checks the archive against the signed manifest, makes sure the new
///    binary starts and names the manifest's version, and renames it into
///    place. Through a running `lorca serve` it hands the work to it, which
///    does the same and restarts itself once no bot is at work.
/// 4. **The trust rule** (`CLIToolTrust`): lorca is only ever ad hoc signed, so
///    it is run only when it is byte for byte its version's published build
///    (`LorcaVerifier`). Once that release's digest is known the check compares
///    the file here and withholds a copy that differs as `.unverified`; until
///    then the click downloads the archive and compares first.
/// 5. **Only what `lorca update` can update**: the releases before 0.1.11 have
///    no `lorca update` — the install script is their only way forward — and
///    a folder this user cannot write to it cannot stage into; both are reported.
/// 6. **The user's own setting**: `auto_update: false` in `~/.lorca/settings.json`
///    (`lorca update --auto off`) is reported with the command, not run.
/// 7. **Never race a change already running** (`LorcaActivity`).
/// 8. **Past the Mac app's `lorca serve`**: when the app's own copy holds the
///    default port (`LorcaActivity.appServe`), the command names a free port
///    instead (`--port <n>`), where nothing answers, so `lorca update` installs
///    over its own file as it does with no serve running — measured 2026-10-09
///    with the app running: `lorca --port 4999 update` exited 0 where `lorca
///    update` failed.
public struct LorcaCheck: Sendable {

    typealias Latest = @Sendable () async throws -> LorcaRelease.Manifest
    /// Whether the file is its version's published build, when the release's
    /// digest is already known; nil when it is not. Blocking.
    typealias KnownVerdict = @Sendable (_ binary: String, _ version: String, _ target: String) -> Bool?

    /// A loopback port nothing listens on, nil when none could be had. Blocking.
    typealias FreePort = @Sendable () -> Int?

    let latest: Latest
    let knownVerdict: KnownVerdict
    let freePort: FreePort

    public init(release: LorcaRelease = LorcaRelease()) {
        let verifier = LorcaVerifier()
        self.init(latest: { try await release.latest() },
                  knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest, knownVerdict: @escaping KnownVerdict, freePort: @escaping FreePort = LorcaCheck.freeLoopbackPort) {
        self.latest = latest
        self.knownVerdict = knownVerdict
        self.freePort = freePort
    }

    public func status(of install: LorcaInstall, busy: LorcaActivity.Busy?, appServe: pid_t? = nil) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .lorca, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .lorca(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no lorca version is compiled into the file", withheld: .versionUnreadable)
        case nil:
            break
        }
        guard let installed = install.version, let binary = install.binary else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest().version
        } catch {
            return verdict(.unknown, note: "could not read lorca-cli.json: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if !install.hasUpdateCommand {
            return verdict(state, latest: newest,
                           note: "lorca \(installed) predates lorca update (\(LorcaInstall.firstUpdatingVersion)): run its install script again",
                           withheld: .unsupportedInstaller)
        }
        guard let target = install.target else {
            return verdict(state, latest: newest, note: "not an arm64 lorca", withheld: .unverified)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        if !install.writable {
            return verdict(state, latest: newest,
                           note: "lorca update cannot write beside \(binary)", withheld: .unsupportedInstaller)
        }
        let knownVerdict = self.knownVerdict
        if await offCooperativePool({ knownVerdict(binary, installed, target) }) == false {
            return verdict(state, latest: newest,
                           note: "not byte for byte the lorca \(installed) Lorca published: not run",
                           withheld: .unverified)
        }
        let command: CLIToolCommand
        if appServe != nil {
            let freePort = self.freePort
            guard let port = await offCooperativePool({ freePort() }) else {
                return verdict(state, latest: newest,
                               note: "the Lorca app's lorca serve holds port \(LorcaActivity.defaultPort), and no free port was found to update past it",
                               withheld: .busy)
            }
            command = Self.updateCommand(binary: binary, port: port)
        } else {
            command = Self.updateCommand(binary: binary)
        }
        if !install.autoUpdate {
            return verdict(state, latest: newest, note: "auto_update is off in ~/.lorca/settings.json: reported only",
                           withheld: .autoUpdateOff, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    /// `<binary> update`. lorca renames over its own canonical path, so the file
    /// itself is run, not a link to it.
    static func updateCommand(binary: String, port: Int? = nil) -> CLIToolCommand {
        CLIToolCommand(executable: binary, arguments: (port.map { ["--port", String($0)] } ?? []) + ["update"],
                       pathPrefix: nil)
    }

    /// A port the kernel hands out for `127.0.0.1:0`, released at once. Blocking.
    static func freeLoopbackPort() -> Int? {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, length) == 0 && getsockname(socket, $0, &length) == 0
            }
        }
        guard bound else { return nil }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    /// Whether something accepts connections on `127.0.0.1:port`. Blocking.
    static func isListening(_ port: Int) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = UInt16(port).bigEndian
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
