import Foundation

/// zoxide's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`ZoxideScanner`): the version is compiled
///    into the file, and DuoUpdater never runs zoxide at all.
/// 2. **Compared on GitHub's `releases/latest`** (`ZoxideRelease`), what the
///    installer installs, and only toward a newer version.
/// 3. **The update is the vendor's installer** — zoxide has no self-update — run
///    with `--bin-dir` the install's own directory (`ZoxideUpdater`). It installs
///    the latest release, whatever that is when it runs; it takes no version.
/// 4. **The trust rule** (`CLIToolTrust`), on what the installer leaves: zoxide
///    is only ever ad hoc signed, so the new file must be byte for byte its
///    version's published build (`ZoxideVerifier`, on the release's GitHub
///    `digest`, which the user accepted as zoxide's published hash on
///    2026-10-09). So a click is offered only when the latest release carries a
///    digest for this Mac's archive; without one the update is reported with
///    the command (`manualCommand`).
/// 5. **Never through `sudo`**: the installer falls back to `sudo cp` when it
///    cannot write the directory. Such an install, and a link to a copy
///    elsewhere (which `cp` writes through), are reported with the command.
/// 6. **Never race the installer already running** (`ZoxideActivity`).
public struct ZoxideCheck: Sendable {

    typealias Latest = @Sendable () async throws -> ZoxideRelease.Published

    let latest: Latest

    public init(release: ZoxideRelease = ZoxideRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: ZoxideInstall, busy: ZoxideActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .zoxide, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .zoxide(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no zoxide version found in the file", withheld: .versionUnreadable)
        case nil:
            break
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        let published: ZoxideRelease.Published
        do {
            published = try await latest()
        } catch ZoxideRelease.Failure.rateLimited(let status) {
            return verdict(.unknown, note: "\(ZoxideRelease.Failure.rateLimited(status))", withheld: .rateLimited)
        } catch {
            return verdict(.unknown, note: "could not read zoxide's latest release: \(error)",
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

        let command = Self.installCommand(binDirectory: Self.binDirectory(of: install))
        if install.linked {
            return verdict(state, latest: newest,
                           note: "\(install.path) links to \(install.binary ?? "?"), which the installer would write through",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        if !install.writable {
            return verdict(state, latest: newest,
                           note: "the installer would need sudo to write \(Self.binDirectory(of: install))",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        guard let target = install.target else {
            return verdict(state, latest: newest, note: "not an arm64 or x86_64 zoxide", withheld: .unverified,
                           manualCommand: command)
        }
        // Rule 4: what the installer leaves could not be checked.
        guard published.archiveDigests[target] != nil else {
            return verdict(state, latest: newest,
                           note: "the zoxide \(newest) release names no digest for its \(target) archive, so what the installer leaves could not be checked",
                           withheld: .unverified, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    /// The directory the installer is pointed at: the one holding the path the
    /// scan found (`~/.local/bin`, its default).
    static func binDirectory(of install: ZoxideInstall) -> String {
        (install.path as NSString).deletingLastPathComponent
    }

    /// The installer as zoxide's README gives it, `curl -sSfL <install.sh> | sh`,
    /// with the install's own directory spelled out. What `ZoxideUpdater` runs is
    /// its equivalent without the pipe (the script downloaded whole, then run).
    static func installCommand(binDirectory: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl",
            arguments: ["-sSfL", ZoxideUpdater.installer.absoluteString, "|", "sh", "-s", "--", "--bin-dir", binDirectory],
            pathPrefix: nil)
    }
}
