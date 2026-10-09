import Foundation

/// nvm's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// Detection and the command only, by design: nvm is shell scripts with no
/// signature and no published checksum, so nothing of it passes the trust rule
/// (`CLIToolTrust`); its installer edits shell profiles; and nvm runs inside the
/// user's own shell. A newer release is reported with the README's update —
/// the newer tag's `install.sh`, run again — for the user to run
/// (`manualCommand`). Nothing is ever run by DuoUpdater.
public struct NvmCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String

    let latest: Latest

    public init(release: NvmRelease = NvmRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: NvmInstall) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, note: String? = nil, withheld: CLIToolWithheld? = nil,
            manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .nvm, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: nil, withheld: withheld, note: note,
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
        return verdict(
            state, latest: newest,
            note: "nvm is unsigned shell scripts with no published checksum, and its installer edits shell profiles: reported only",
            withheld: .unsupportedInstaller, manualCommand: Self.updateCommand(version: newest))
    }

    /// `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v<version>/install.sh | bash`,
    /// as the README writes it. Only ever copied, never run.
    static func updateCommand(version: String) -> CLIToolCommand {
        CLIToolCommand(executable: "curl",
                       arguments: ["-o-", NvmRelease.installer(version: version).absoluteString, "|", "bash"],
                       pathPrefix: nil)
    }
}
