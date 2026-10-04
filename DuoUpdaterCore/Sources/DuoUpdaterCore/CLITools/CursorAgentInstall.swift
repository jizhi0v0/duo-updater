import Foundation

/// Cursor's command-line agent (`agent`, formerly `cursor-agent`) as its installer
/// leaves it, identified by **its launcher**, `~/.local/bin/agent`.
///
/// The layout, from the vendor's installer (`curl https://cursor.com/install -fsS
/// | bash`, read 2026-10-04 at 2026.10.01-e373342) and installs of 2026.05.16-0338208
/// and 2026.10.01-e373342 made with it in a scratch HOME the same day:
/// - `~/.local/share/cursor-agent/versions/<version>/` holds one release, ~591 MB:
///   `cursor-agent` (a bash script that execs the `node` beside it on
///   `index.js`), that `node` (Node.js Foundation's Developer ID, Team
///   `HX7739G8FX`), the bundle's JavaScript, and native helpers — `rg` in every
///   release, `crepectl`, `cursorsandbox`, `cursor-agent-worker-sea` in newer
///   ones — signed by Anysphere Incorporated, Team `DCNK4UB866`. Versions are
///   `<YYYY.MM.DD>-<commit>`.
/// - `~/.local/bin/agent` and `~/.local/bin/cursor-agent` → `…/versions/<version>/cursor-agent`,
///   absolute symlinks the installer rewrites. The installer hard-codes both from
///   `$HOME`; it edits no shell rc file, only prints the line to add.
/// - The installer **is** the version: the script served at cursor.com/install
///   names one release (`FINAL_DIR=…/versions/2026.10.01-e373342`) and downloads
///   `downloads.cursor.com/lab/<version>/darwin/<arm64|x64>/agent-cli-package.tar.gz`
///   with no checksum (`CursorAgentRelease`).
/// - The CLI updates itself: two seconds after every start it asks Cursor's
///   backend for its channel's version and installs it under
///   `~/.local/share/cursor-agent/.install.lock`, then removes all but the two
///   newest versions not in use (`cleanup-install-versions`), unless its channel
///   is `static` (`update-core.ts`, `install-core-posix.ts` in the 2026.10.01
///   bundle). DuoUpdater's click is for a copy that has not been run in a while.
///
/// Nothing here runs the agent: the version is the directory's name.
public struct CursorAgentInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// No launcher points into a version directory.
        case launcherElsewhere
        /// The version directory has no `cursor-agent` script or `node`.
        case versionIncomplete
        /// The directory's name is not a `<date>-<commit>` version.
        case versionUnreadable
    }

    /// `~/.local/bin/agent` (or `cursor-agent` when only that link exists).
    public let path: String
    /// `~/.local/share/cursor-agent`.
    public let root: String
    public let version: String?
    public let problem: Problem?

    public init(path: String, root: String? = nil, version: String?, problem: Problem? = nil) {
        self.path = path
        self.root = root ?? URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("share/cursor-agent").path
        self.version = version
        self.problem = problem
    }

    /// `versions/<version>`, when the version is known.
    public var directory: String? {
        version.map { "\(root)/versions/\($0)" }
    }
}

/// Cursor's CLI setting that decides an offer: `channel` in
/// `~/.cursor/cli-config.json`. `static` turns its updates off entirely — `agent
/// update` prints "Skipping update check for static channel" and the background
/// check never runs — so DuoUpdater reports and offers nothing either.
public struct CursorAgentSettings: Sendable, Equatable, Codable {

    /// As written; nil when unset (the CLI's default, `prod`).
    public var channel: String?

    public init(channel: String? = nil) {
        self.channel = channel
    }

    public var updatesDisabled: Bool { channel == "static" }

    public static func location(home: URL) -> URL {
        home.appendingPathComponent(".cursor/cli-config.json")
    }

    /// Blocking file read; only `channel` is taken (the file also holds
    /// permissions and preferences).
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CursorAgentSettings {
        guard let data = try? Data(contentsOf: location(home: home)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = json["channel"] as? String, !channel.isEmpty, channel.count <= 64
        else { return CursorAgentSettings() }
        return CursorAgentSettings(channel: channel)
    }
}

/// Finds the agent through its launchers. Network-free, and nothing is run.
public struct CursorAgentScanner: Sendable {

    /// Anysphere Incorporated: the release's native helpers.
    public static let teamIdentifier = "DCNK4UB866"

    public typealias SignatureCheck = @Sendable (_ file: URL, _ team: String) -> CLIToolTrust.Signature

    let home: URL
    let checkSignature: SignatureCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = { CLIToolTrust.signature(of: $0, teamIdentifier: $1) }
    ) {
        self.home = home
        self.checkSignature = checkSignature
    }

    var bin: URL { home.appendingPathComponent(".local/bin") }
    var root: URL { home.appendingPathComponent(".local/share/cursor-agent") }
    var versions: URL { root.appendingPathComponent("versions") }

    /// The agent, or nothing: no `cursor-agent` data directory means no install.
    public func scan() -> CursorAgentInstall? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: versions.path) else { return nil }
        let launchers = ["agent", "cursor-agent"].map { bin.appendingPathComponent($0) }
        let primary = launchers.first { (try? fm.destinationOfSymbolicLink(atPath: $0.path)) != nil } ?? launchers[0]
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: primary.path) else {
            return CursorAgentInstall(path: primary.path, root: root.path, version: nil, problem: .launcherElsewhere)
        }
        let target = URL(fileURLWithPath: destination, relativeTo: primary.deletingLastPathComponent()).standardizedFileURL
        let directory = target.deletingLastPathComponent()
        guard target.lastPathComponent == "cursor-agent",
              directory.deletingLastPathComponent().standardizedFileURL.path == versions.standardizedFileURL.path
        else {
            return CursorAgentInstall(path: primary.path, root: root.path, version: nil, problem: .launcherElsewhere)
        }
        let version = directory.lastPathComponent
        guard CursorAgentRelease.isVersion(version) else {
            return CursorAgentInstall(path: primary.path, root: root.path, version: nil, problem: .versionUnreadable)
        }
        guard fm.isExecutableFile(atPath: target.path),
              fm.isExecutableFile(atPath: directory.appendingPathComponent("node").path)
        else {
            return CursorAgentInstall(path: primary.path, root: root.path, version: version, problem: .versionIncomplete)
        }
        return CursorAgentInstall(path: primary.path, root: root.path, version: version)
    }

    /// Whether a version directory is the vendors' build: its `node` signed by
    /// the Node.js Foundation and its `rg` by Anysphere. Blocking.
    public func isTrusted(_ directory: URL) -> Bool {
        checkSignature(directory.appendingPathComponent("node"), NpmScanner.nodeTeamIdentifier) == .vendor
            && checkSignature(directory.appendingPathComponent("rg"), Self.teamIdentifier) == .vendor
    }
}
