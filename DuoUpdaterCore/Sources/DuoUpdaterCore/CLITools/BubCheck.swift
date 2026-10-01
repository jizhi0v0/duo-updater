import Foundation

/// Each bub install's verdict: is there a newer release on PyPI, and may
/// DuoUpdater apply it — and if so, with exactly which command.
///
/// The rules, as agreed for this tool:
/// 1. **The documented command, for bub alone.** One-click is `bub update bub`,
///    run by the install's own `bin/bub` — never a bare `bub update`, which also
///    upgrades every plugin in `~/.bub/bub-project`.
/// 2. **Same place, same installer.** Only the official installer's venv
///    (`~/.bub/.venv`) is offered. A `uv tool` or pipx venv is reported only:
///    `bub update` would sync bub's own uv project into it.
/// 3. **Never race a change already running** (`BubActivity`).
///
/// bub has no auto-update and no setting that turns updates off, so there is no
/// settings gate here.
public struct BubCheck: Sendable {

    /// The version a plain `bub` requirement resolves to (`BubRelease`).
    typealias Latest = @Sendable () async throws -> String
    /// The uv `bub update` will run, or nil when there is none it would find.
    typealias UVLocator = @Sendable (BubInstall) -> String?

    let latest: Latest
    let uv: UVLocator

    public init(release: BubRelease = BubRelease(), home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(latest: { try await release.latestVersion() }, uv: { Self.uv(for: $0, home: home) })
    }

    /// The seam tests use, so no verdict depends on the network or on which uv
    /// this Mac has.
    init(latest: @escaping Latest, uv: @escaping UVLocator) {
        self.latest = latest
        self.uv = uv
    }

    /// Every install's status, asking PyPI at most once.
    public func statuses(
        of installs: [BubInstall], busy: (BubInstall) -> BubActivity.Busy?
    ) async -> [CLIToolStatus] {
        var cached: Result<String, Error>?
        var statuses: [CLIToolStatus] = []
        for install in installs {
            let busy = busy(install)
            statuses.append(await status(of: install, busy: busy) {
                if let cached { return try cached.get() }
                let result: Result<String, Error>
                do { result = .success(try await latest()) } catch { result = .failure(error) }
                cached = result
                return try result.get()
            })
        }
        return statuses
    }

    func status(of install: BubInstall, busy: BubActivity.Busy?) async -> CLIToolStatus {
        await status(of: install, busy: busy, latest: latest)
    }

    private func status(
        of install: BubInstall, busy: BubActivity.Busy?, latest: () async throws -> String
    ) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .bub, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .bub(install))
        }

        if let problem = install.problem {
            return verdict(.unknown, note: Self.describe(problem), withheld: .broken)
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "no single bub dist-info to read the version from",
                           withheld: .versionUnreadable)
        }
        // A checkout or a URL is not a PyPI release, so comparing it with one says
        // nothing — and `bub update bub` would not move it to PyPI either: bub
        // rebuilds its requirement from this same `direct_url.json`
        // (`_build_bub_requirement`, bub 0.4.4 and 0.5.0), so the sync reinstalls
        // the editable path or the git URL it already has.
        if let source = install.directSource {
            return verdict(.unknown, note: "installed from \(Self.describe(source)), not from PyPI: not compared",
                           withheld: .unsupportedInstaller)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read PyPI: \(error)", withheld: .channelUnreadable)
        }

        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedSame: state = .upToDate
        case .orderedAscending: state = .updateAvailable
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        guard install.method == .installer else {
            return verdict(state, latest: newest,
                           note: "installed with \(Self.describe(install.method)), which updates it itself: reported only",
                           withheld: .unsupportedInstaller)
        }
        if install.project == .missingBub {
            return verdict(state, latest: newest,
                           note: "~/.bub/bub-project does not depend on bub (left by an interrupted bub update or install), so `bub update bub` would change nothing",
                           withheld: .projectIncomplete)
        }
        guard let uv = uv(install) else {
            return verdict(state, latest: newest, note: "uv not found: `bub update` needs it", withheld: .updaterMissing)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: Self.updateCommand(for: install, uv: uv))
    }

    /// `bub update bub`, run by this venv's own `bin/bub`, with the directory of
    /// the uv it is to use first on `PATH`.
    ///
    static func updateCommand(for install: BubInstall, uv: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: install.executable, arguments: ["update", "bub"],
            pathPrefix: (uv as NSString).deletingLastPathComponent)
    }

    // MARK: - uv

    /// The uv `bub update` will find, in the order it looks — or nil.
    ///
    /// bub's `_find_uv` (bub 0.4.4 and 0.5.0) searches the venv's own scripts
    /// directory, then `~/.local/bin`, then `PATH`. The first two win whatever
    /// `PATH` says, so they come first here too: the uv this check vouches for has
    /// to be the one bub runs. `~/.local/bin/uv` is where the official installer
    /// puts uv when it has to install it. Homebrew's uv (`/opt/homebrew/bin`,
    /// `/usr/local/bin` on Intel) is only reachable through `PATH`, which a GUI
    /// process does not have — hence `pathPrefix`, which puts this uv's directory
    /// first.
    static func uv(
        for install: BubInstall, home: URL,
        systemDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
    ) -> String? {
        let candidates = [
            URL(fileURLWithPath: install.path).appendingPathComponent("bin/uv").path,
            home.appendingPathComponent(".local/bin/uv").path,
        ] + systemDirectories.map { $0 + "/uv" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Wording

    static func describe(_ problem: BubInstall.Problem) -> String {
        switch problem {
        case .executableMissing: return "bin/bub is missing from the environment"
        case .interpreterMissing: return "the environment's Python is gone, so bub cannot start"
        case .packageMissing: return "bin/bub is there but the bub package is not"
        }
    }

    static func describe(_ source: BubInstall.DirectSource) -> String {
        switch source {
        case .editable: return "an editable checkout"
        case .vcs: return "a version-control URL"
        case .localPath: return "a local path"
        case .archive: return "a direct URL"
        }
    }

    static func describe(_ method: BubInstall.Method) -> String {
        switch method {
        case .installer: return "the bub installer"
        case .uvTool: return "uv tool (`uv tool upgrade bub`)"
        case .pipx: return "pipx (`pipx upgrade bub`)"
        }
    }
}
