import Foundation

/// What fx's release CDN says each channel points at — the two files `fx
/// upgrade` itself reads (`upgrade_helpers.fetchTarget`).
///
/// - stable: `https://releases.fx.sh/latest.txt`, one tag (`v0.0.12` on
///   2026-10-01), the leading `v` dropped as fx drops it;
/// - dev: `https://releases.fx.sh/dev.json`, `{"version", "commit"}` — on
///   2026-10-01 `0.0.12` at `d44cd84ae19c8b642797f431a04df6e53c66a13e`.
///
/// fx's own HTTP client takes no proxy from the environment (it never calls
/// `initDefaultProxies`; measured 2026-10-01: `fx upgrade` with `https_proxy`,
/// `http_proxy`, `HTTPS_PROXY` and `ALL_PROXY` all at a dead `127.0.0.1:9`
/// upgraded anyway), so these are read the way the app reads any feed.
public struct FxRelease: Sendable {

    public static let base = URL(string: "https://releases.fx.sh")!

    public enum Latest: Sendable, Equatable {
        case stable(version: String)
        case dev(version: String, revision: String)
    }

    public enum Failure: Error, Equatable {
        case http(Int)
        case unreadable
    }

    let session: URLSession

    public init(session: URLSession = .updates) {
        self.session = session
    }

    public func latest(channel: FxSettings.Channel) async throws -> Latest {
        switch channel {
        case .stable:
            let text = String(decoding: try await get(Self.base.appendingPathComponent("latest.txt")), as: UTF8.self)
            guard let version = Self.parseStable(text) else { throw Failure.unreadable }
            return .stable(version: version)
        case .dev:
            guard let latest = Self.parseDev(try await get(Self.base.appendingPathComponent("dev.json"))) else {
                throw Failure.unreadable
            }
            return latest
        }
    }

    static func parseStable(_ text: String) -> String? {
        var version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.hasPrefix("v") { version.removeFirst() }
        return isVersion(version) ? version : nil
    }

    /// fx's `Target.parseDevManifest`: an object whose `version` is a version and
    /// whose `commit` is 7–64 hex digits.
    static func parseDev(_ data: Data) -> Latest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var version = json["version"] as? String, let commit = json["commit"] as? String
        else { return nil }
        if version.hasPrefix("v") { version.removeFirst() }
        guard isVersion(version), (7...64).contains(commit.count), commit.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return .dev(version: version, revision: commit)
    }

    /// `update_target.isValidVersion`: exactly three dot-separated runs of ASCII
    /// digits.
    static func isVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 10 && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// `update_target.compareVersions`: major, minor, patch as numbers.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ s: String) -> [UInt64] {
            var text = Substring(s)
            if text.hasPrefix("v") { text = text.dropFirst() }
            let split = text.split(separator: ".", omittingEmptySubsequences: false).map { UInt64($0) ?? 0 }
            return (0..<3).map { $0 < split.count ? split[$0] : 0 }
        }
        let (x, y) = (parts(a), parts(b))
        for (l, r) in zip(x, y) where l != r { return l < r ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        return data
    }
}

/// One install's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules, as agreed for fx:
/// 1. **Signature first, then `--version`** (`FxScanner`): nothing about a copy
///    is believed, and nothing is run, until it passes.
/// 2. **One-click is fx's own `upgrade`**, with no `--channel`: fx then keeps the
///    channel the user chose, and DuoUpdater never switches it. fx's background
///    auto-upgrade cannot be seen from the app (`FX_AUTO_UPGRADE` lives in the
///    user's shell), and fx gets one-click anyway.
/// 3. **Compared per channel the way fx compares** (`update_target.shouldInstall`).
/// 4. **Never race an upgrade already running** (`FxActivity`).
public struct FxCheck: Sendable {

    typealias Latest = @Sendable (FxSettings.Channel) async throws -> FxRelease.Latest

    let latest: Latest

    public init(release: FxRelease = FxRelease()) {
        self.init(latest: { try await release.latest(channel: $0) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: FxInstall, settings: FxSettings, busy: FxActivity.Busy?) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .fx, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: settings.channel.rawValue, state: state, oneClick: oneClick, withheld: withheld,
                note: note, detail: .fx(install))
        }

        if install.problem == .executableMissing {
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        }
        guard install.signature == .vercel else {
            return verdict(
                .unknown,
                note: "not signed by Vercel (Team \(FxScanner.teamIdentifier), \(FxScanner.signingIdentifier)): "
                    + "a dev-channel build, which is ad hoc signed, or another program named fx; not run",
                withheld: .wrongSigner)
        }
        if install.quarantined {
            return verdict(.unknown, note: "quarantined, so not run to read its version", withheld: .versionUnreadable)
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "fx --version printed no version", withheld: .versionUnreadable)
        }
        let target: FxRelease.Latest
        do {
            target = try await latest(settings.channel)
        } catch {
            return verdict(.unknown, note: "could not read the \(settings.channel.rawValue) channel: \(error)",
                           withheld: .channelUnreadable)
        }

        switch target {
        case .stable(let latest):
            let state: CLIToolState
            switch FxRelease.compare(installed, latest) {
            case .orderedAscending: state = .updateAvailable
            case .orderedSame: state = .upToDate
            case .orderedDescending: state = .ahead
            }
            guard state == .updateAvailable else { return verdict(state, latest: latest) }
            if let busy {
                return verdict(state, latest: latest, note: busy.description, withheld: .busy)
            }
            guard let executable = install.executable else {
                return verdict(.unknown, latest: latest, note: "no executable to run", withheld: .broken)
            }
            // The verified file, not the path: for a symlink this is what fx
            // replaces anyway (its own resolved executable path), and running it
            // directly leaves no window for the link to be pointed elsewhere.
            return verdict(
                state, latest: latest,
                oneClick: CLIToolCommand(executable: executable, arguments: ["upgrade"], pathPrefix: nil))

        case .dev(let version, let revision):
            // fx installs whenever the build's channel differs from the selected
            // one, then compares revisions within dev. A copy that passed the
            // signature check is a stable build (dev builds are ad hoc signed, see
            // `FxInstall`), so on `dev` fx would always replace it: an update.
            //
            // Not offered: what it installs is a dev build, which fails the same
            // check this copy just passed — DuoUpdater would replace a binary it
            // trusts with one it refuses to run.
            let label = "\(version)-\(revision.prefix(7))"
            return verdict(
                .updateAvailable, latest: label,
                note: "the dev channel ships ad hoc signed builds (no Developer ID): reported only",
                withheld: .unsupportedInstaller)
        }
    }
}
