import Foundation

/// Obelus's verdict, as every tool's verdict is shaped (`CLIToolStatus`): one
/// for `obg`, one for `ob`.
///
/// The rules:
/// 1. **Read from disk, never run** (`ObelusScanner`): the version is compiled
///    into the file, and DuoUpdater never runs Obelus at all.
/// 2. **Compared on the latest release's `SHA256SUMS`** (`ObelusRelease`), the
///    release the installer installs, and only toward a newer version.
/// 3. **The update is the vendor's installer** — Obelus has no self-update — run
///    with `--bin` the row's binary, `--dir` its own directory and `--version`
///    the release checked here (`ObelusUpdater`).
/// 4. **The trust rule** (`CLIToolTrust`), on what the installer leaves: Obelus
///    is only ever ad hoc signed, so the new file must be byte for byte its
///    version's published build (`ObelusVerifier`, on the release's own
///    `SHA256SUMS`). So a click is offered only when the latest `SHA256SUMS`
///    names this binary's archive; without it the update is reported with the
///    command (`manualCommand`).
/// 5. **Never through a link or into a directory this user cannot write**: the
///    installer would replace a link with a file, and has no `sudo` fallback.
///    Both are reported with the command.
/// 6. **Never race the installer already running** (`ObelusActivity`).
public struct ObelusCheck: Sendable {

    typealias Latest = @Sendable () async throws -> ObelusRelease.Published

    let latest: Latest

    public init(release: ObelusRelease = ObelusRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: ObelusInstall, busy: ObelusActivity.Busy?) async -> CLIToolStatus {
        status(of: install, busy: busy, published: await published())
    }

    /// `latest`, its error kept for the verdict.
    func published() async -> Result<ObelusRelease.Published, any Error> {
        do { return .success(try await latest()) } catch { return .failure(error) }
    }

    /// The verdict on an answer already asked for: both rows of one check read
    /// the same `SHA256SUMS`.
    func status(
        of install: ObelusInstall, busy: ObelusActivity.Busy?, published answer: Result<ObelusRelease.Published, any Error>
    ) -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .obelus, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, name: install.name.rawValue, detail: .obelus(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no Obelus version found in the file", withheld: .versionUnreadable)
        case nil:
            break
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        let published: ObelusRelease.Published
        switch answer {
        case .success(let answer): published = answer
        case .failure(let error):
            return verdict(.unknown, note: "could not read Obelus's latest release: \(error)",
                           withheld: .channelUnreadable)
        }
        let newest = published.version
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        let command = Self.installCommand(install.name, directory: Self.directory(of: install))
        if install.linked {
            return verdict(state, latest: newest,
                           note: "\(install.path) links to \(install.binary ?? "?"), which the installer would replace with a file",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        if !install.writable {
            return verdict(state, latest: newest,
                           note: "the installer cannot write \(Self.directory(of: install)) without administrator rights",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        // Rule 4: what the installer leaves could not be checked.
        guard published.archiveDigests[install.name] != nil else {
            return verdict(state, latest: newest,
                           note: "the Obelus \(newest) SHA256SUMS names no \(ObelusRelease.archiveName(install.name, version: newest)), so what the installer leaves could not be checked",
                           withheld: .unverified, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    /// The directory the installer is pointed at: the one holding the path the
    /// scan found (`~/.local/bin`, its default).
    static func directory(of install: ObelusInstall) -> String {
        (install.path as NSString).deletingLastPathComponent
    }

    /// The installer as Obelus's README gives it, `curl -fsSL <install.sh> | sh`,
    /// with the binary and directory spelled out. What `ObelusUpdater` runs is
    /// its equivalent without the pipe, pinned to the release checked
    /// (`--version`).
    static func installCommand(_ binary: ObelusInstall.Binary, directory: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl",
            arguments: ["-fsSL", ObelusUpdater.installer.absoluteString, "|", "sh", "-s", "--",
                        "--bin", binary.rawValue, "--dir", directory],
            pathPrefix: nil)
    }
}
