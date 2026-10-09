import Foundation

/// nvm's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`NvmScanner`): the version is the
///    `nvm --version` case of `nvm.sh`.
/// 2. **Compared on GitHub's `releases/latest`** (`NvmRelease`), only toward a
///    newer version.
/// 3. **The update is the README's**: the newer tag's `install.sh`, run again
///    (`NvmUpdater`), into the install's own directory, touching no shell
///    profile.
/// 4. **Exempt from the trust rule** (`CLIToolTrust`), by the user's decision
///    of 2026-10-09: nvm is shell scripts, with nothing to check a signature or
///    a hash of. What is checked after the run is that `nvm.sh` names the new
///    version.
/// 5. **Never through `sudo`**: a directory this user cannot write is
///    reported with the command (`manualCommand`).
/// 6. **A checkout is updated only with a git that is not `/usr/bin/git`**
///    (`NvmUpdater.git`): without one there is no click and no command, since
///    the installer itself would stop and ask for the Command Line Tools.
/// 7. **Never race DuoUpdater's own run of the installer** (`NvmActivity`).
public struct NvmCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String
    typealias Git = @Sendable () -> String?

    let latest: Latest
    let git: Git

    public init(release: NvmRelease = NvmRelease()) {
        self.init(latest: { try await release.latest() }, git: { NvmUpdater.git() })
    }

    /// The seam tests use, so no verdict depends on the network or the Mac.
    init(latest: @escaping Latest, git: @escaping Git) {
        self.latest = latest
        self.git = git
    }

    public func status(of install: NvmInstall, busy: NvmActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil, note: String? = nil,
            withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .nvm, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .nvm(install))
        }

        guard let installed = install.version else {
            return verdict(.unknown, note: "nvm.sh has no nvm --version case to read", withheld: .versionUnreadable)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch NvmRelease.Failure.rateLimited(let status) {
            return verdict(.unknown, note: "\(NvmRelease.Failure.rateLimited(status))", withheld: .rateLimited)
        } catch {
            return verdict(.unknown, note: "could not read nvm's latest release: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        let command = Self.updateCommand(version: newest)
        // Rule 5.
        guard install.writable else {
            return verdict(state, latest: newest, note: "\(install.directory) cannot be written without sudo",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        // Rule 6.
        if install.layout == .git, git() == nil {
            return verdict(state, latest: newest,
                           note: "\(install.directory) is a git checkout, and no git but /usr/bin/git's Command Line Tools stub was found",
                           withheld: .updaterMissing)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    /// `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v<version>/install.sh | bash`,
    /// as the README writes it. What `NvmUpdater` runs is its equivalent without
    /// the pipe (the script downloaded whole, then run), with the install's
    /// directory as `NVM_DIR` and no profile.
    static func updateCommand(version: String) -> CLIToolCommand {
        CLIToolCommand(executable: "curl",
                       arguments: ["-o-", NvmRelease.installer(version: version).absoluteString, "|", "bash"],
                       pathPrefix: nil)
    }
}
