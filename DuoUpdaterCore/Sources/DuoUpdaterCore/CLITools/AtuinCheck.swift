import Foundation

/// One Atuin install's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`AtuinScanner`): the version is the
///    receipt's, for the copy the receipt names.
/// 2. **Compared on the user's channel** (`AtuinRelease`): `update_channel` in
///    Atuin's config, `stable` or `nightly`, as `atuin update` reads it; only
///    toward a newer version.
/// 3. **The update is Atuin's own `atuin update`**, on the install's own file:
///    axoupdater downloads the newer release's `atuin-installer.sh` and runs it
///    into the receipt's directory — never `setup.atuin.sh`, which also edits
///    the shell rc files and installs hooks into coding agents' configs.
/// 4. **The trust rule** (`CLIToolTrust`): atuin is only ever ad hoc signed, so
///    it is run only when it is byte for byte its version's published build
///    (`AtuinVerifier`). Once that release's digest is known the check compares
///    the file here and withholds a copy that differs as `.unverified`; until
///    then the click downloads the archive and compares first.
/// 5. **Only what `atuin update` updates**: a copy without the installer's
///    receipt, or one the receipt does not name, is reported (`atuin update`
///    refuses both); so is one in a directory this user cannot write to.
/// 6. **`update_check = false`** reports the update with the command
///    (`AtuinSettings`).
/// 7. **Never race a change already running** (`AtuinActivity`).
public struct AtuinCheck: Sendable {

    typealias Latest = @Sendable (_ channel: String) async throws -> String
    /// Whether the file is its version's published build, when the release's
    /// digest is already known; nil when it is not. Blocking.
    typealias KnownVerdict = @Sendable (_ binary: String, _ version: String, _ target: String) -> Bool?

    let latest: Latest
    let knownVerdict: KnownVerdict

    public init(release: AtuinRelease = AtuinRelease()) {
        let verifier = AtuinVerifier()
        self.init(latest: { try await release.latest(channel: $0) },
                  knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest, knownVerdict: @escaping KnownVerdict) {
        self.latest = latest
        self.knownVerdict = knownVerdict
    }

    public func status(of install: AtuinInstall, busy: AtuinActivity.Busy?) async -> CLIToolStatus {
        let channel = install.settings.channel
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .atuin, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: channel, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .atuin(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .noReceipt:
            return verdict(.unknown, note: "no install receipt from Atuin's installer: atuin update refuses it",
                           withheld: .unsupportedInstaller)
        case .receiptElsewhere:
            return verdict(.unknown, note: "Atuin's install receipt names another copy: atuin update refuses this one",
                           withheld: .unsupportedInstaller)
        case nil:
            break
        }
        guard let installed = install.version, let binary = install.binary, let directory = install.installDirectory else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        guard install.settings.channelIsKnown else {
            return verdict(.unknown, note: "Atuin's config names the channel \"\(channel)\", which atuin does not know",
                           withheld: .channelUnreadable)
        }
        let newest: String
        do {
            newest = try await latest(channel)
        } catch {
            return verdict(.unknown, note: "could not read atuin's \(channel) channel: \(error)",
                           withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch AtuinRelease.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        guard let target = install.target else {
            return verdict(state, latest: newest, note: "not an arm64 or x86_64 atuin", withheld: .unverified)
        }
        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        if !install.writable {
            return verdict(state, latest: newest,
                           note: "atuin update could not write to \((binary as NSString).deletingLastPathComponent)",
                           withheld: .unsupportedInstaller)
        }
        let knownVerdict = self.knownVerdict
        if await offCooperativePool({ knownVerdict(binary, installed, target) }) == false {
            return verdict(state, latest: newest,
                           note: "not byte for byte the atuin \(installed) atuinsh published: not run",
                           withheld: .unverified)
        }
        let command = Self.updateCommand(binary: binary, installDirectory: directory)
        if !install.settings.updateCheck {
            return verdict(state, latest: newest, note: "update_check = false in Atuin's config",
                           withheld: .autoUpdateOff, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    /// `<binary> update`, with the receipt's directory first on `PATH`: the
    /// installer it runs appends the directory to the shell rc files when the
    /// receipt's `modify_path` is true and the directory is not on `PATH`
    /// (`atuin-installer.sh`, `case :$PATH: in *:$_install_dir:*`), and a GUI
    /// process's `PATH` never has it. The prefix is the receipt's as written,
    /// which is what that test compares.
    static func updateCommand(binary: String, installDirectory: String) -> CLIToolCommand {
        CLIToolCommand(executable: binary, arguments: ["update"], pathPrefix: installDirectory)
    }
}
