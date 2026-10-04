import Foundation

/// Cursor's CLI verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Read from disk, never run** (`CursorAgentScanner`).
/// 2. **Compared on the installer's version** (`CursorAgentRelease`), and only
///    toward a newer one.
/// 3. **One-click is the vendor's documented install command**, `curl
///    https://cursor.com/install -fsS | bash`, which installs the version the
///    check read; `CursorAgentUpdater` runs its equivalent without the pipe. The
///    agent is never run, so nothing of it needs trusting first; what the
///    installer leaves must be the vendors' build.
/// 4. **The CLI's own setting is respected**: channel `static` turns updates
///    off, so nothing is offered; an install already running is not raced
///    (`CursorAgentActivity`).
public struct CursorAgentCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String

    let latest: Latest

    public init(release: CursorAgentRelease = CursorAgentRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    static let command = CLIToolCommand(
        executable: "curl", arguments: [CursorAgentRelease.installerURL.absoluteString, "-fsS", "|", "bash"], pathPrefix: nil)

    public func status(
        of install: CursorAgentInstall, settings: CursorAgentSettings, busy: CursorAgentActivity.Busy?
    ) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .cursorAgent, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: settings.channel ?? "prod", state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .cursorAgent(install))
        }

        switch install.problem {
        case .launcherElsewhere:
            return verdict(.unknown, note: "\(install.path) does not point into \(install.root)/versions", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "the launcher names no <date>-<commit> version", withheld: .versionUnreadable)
        case .versionIncomplete:
            return verdict(.unknown, note: "versions/\(install.version ?? "?") has no cursor-agent or node", withheld: .broken)
        case nil:
            break
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        if settings.updatesDisabled {
            return verdict(.unknown, note: "the CLI's channel is static, which turns its updates off", withheld: .updatesDisabled)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read Cursor's installer: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch CursorAgentRelease.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: Self.command)
    }
}
