import Foundation

/// terminal-mac's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`TerminalMacScanner`): the version and
///    build are the bundle's `Info.plist`. Nothing of the app is executed by a
///    check.
/// 2. **Compared on the release's tag, marketing first then build**
///    (`VersionSide`): the marketing version is frozen across builds, so
///    `0.2.0 (5)` against `0.2.0 (6)` is an update and only the build says so.
/// 3. **The update is the vendor's installer** (`TerminalMacUpdater`): the
///    archive pinned to the release checked, its sha256 checked against
///    GitHub's published digest, then the archive's own `install.sh`. There is
///    no self-update command.
/// 4. **A launcher the installer would refuse is reported, not clicked**: a
///    plain file, a link outside the installer's layout, a foreign bundle, or
///    a prefix this user cannot write. The row hands over the vendor's pinned
///    `get.sh` command instead.
/// 5. **Never race an installer already running** (`TerminalMacActivity`).
public struct TerminalMacCheck: Sendable {

    typealias Latest = @Sendable () async throws -> TerminalMacRelease.Published

    let latest: Latest

    public init(release: TerminalMacRelease = TerminalMacRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: TerminalMacInstall, busy: TerminalMacActivity.Busy?) async -> CLIToolStatus {
        status(of: install, busy: busy, published: await published())
    }

    /// `latest`, its error kept for the verdict.
    func published() async -> Result<TerminalMacRelease.Published, any Error> {
        do { return .success(try await latest()) } catch { return .failure(error) }
    }

    /// The verdict on an answer already asked for: one check reads the release
    /// once, however many copies there are (one).
    func status(
        of install: TerminalMacInstall, busy: TerminalMacActivity.Busy?,
        published answer: Result<TerminalMacRelease.Published, any Error>
    ) -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .terminalMac, path: install.path,
                installedVersion: install.version == nil ? nil : install.displayVersion,
                latestVersion: latest, channel: nil, state: state, oneClick: oneClick, withheld: withheld,
                note: note, manualCommand: manualCommand, detail: .terminalMac(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .notInstallerLayout:
            return verdict(.unknown,
                           note: "\(install.path) is not the launcher the installer leaves, so it would refuse to replace it",
                           withheld: .unsupportedInstaller)
        case .foreignBundle:
            return verdict(.unknown, note: "\(install.binary ?? install.path) is not terminal-mac's bundle",
                           withheld: .unsupportedInstaller)
        case .versionUnreadable:
            return verdict(.unknown, note: "the bundle's Info.plist carries no readable version and build",
                           withheld: .versionUnreadable)
        case nil:
            break
        }
        guard let installed = install.version, let installedBuild = install.build else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }

        let published: TerminalMacRelease.Published
        switch answer {
        case .success(let answer): published = answer
        case .failure(let error):
            if let failure = error as? TerminalMacRelease.Failure, case .rateLimited = failure {
                return verdict(.unknown, note: "could not read terminal-mac's latest release: \(error)",
                               withheld: .rateLimited)
            }
            if let refused = error as? GitHubRateLimitGate.Refused {
                return verdict(.unknown, note: refused.localizedDescription, withheld: .rateLimited)
            }
            return verdict(.unknown, note: "could not read terminal-mac's latest release: \(error)",
                           withheld: .channelUnreadable)
        }

        let newest = published.displayVersion
        let state: CLIToolState
        if VersionComparator.isNewer(published.side, than: VersionSide(marketing: installed, build: installedBuild)) {
            state = .updateAvailable
        } else if VersionComparator.isSame(published.side,
                                           as: VersionSide(marketing: installed, build: installedBuild)) {
            state = .upToDate
        } else {
            state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        let command = Self.installCommand(published: published, prefix: install.prefix ?? "~/.local")
        if !install.writable {
            return verdict(state, latest: newest,
                           note: "the installer cannot write \(install.prefix ?? "the install prefix") without administrator rights",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    /// The command the row shows and hands over: the release's own `get.sh`,
    /// pinned to the tag checked, passed the prefix the install is under.
    static func installCommand(published: TerminalMacRelease.Published, prefix: String) -> CLIToolCommand {
        let script = TerminalMacRelease.getScriptURL(tag: published.tag).absoluteString
        return CLIToolCommand(
            executable: "curl",
            arguments: ["-fsSL", script, "|", "bash", "-s", "--", "--prefix", prefix],
            pathPrefix: nil,
            // `display` joins arguments with spaces; a prefix can hold one, or a
            // quote. The updater passes the prefix as one argument and needs no
            // quoting, but the command a person copies is a shell line.
            shellLine: "curl -fsSL \(script) | bash -s -- --prefix \(NvmCheck.shellQuoted(prefix))")
    }
}
