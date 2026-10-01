import Foundation

/// One global npm package as its row's detail pane reads it: the install
/// (`NpmInstall`) and what the check decided about it.
///
/// Two versions can matter at once. `offered` is what one-click installs — the
/// newest version this prefix's node runs, and `CLIToolStatus.latestVersion`
/// whenever there is one. `gap` is set when the tag's own version is newer still
/// but needs a newer runtime: openclaw at 2026.3.28 under node 24.13.0 on
/// 2026-10-02 is offered 2026.6.35, while 2026.9.7 needs Node `>=24.16.0 <25 ||
/// >=26.1.0`. So the app can say both — "update to 2026.6.35" and "2026.9.7 needs
/// Node ≥ 24.16.0". With no runnable newer version, `offered` is nil, the status
/// is withheld `.runtimeTooOld` and its `latestVersion` is the tag's.
public struct NpmPackage: Sendable, Equatable {

    /// A newer release this prefix cannot run.
    public struct RuntimeGap: Sendable, Equatable, Codable {
        public let version: String
        /// Its `engines.node` and `engines.npm`, as written.
        public let node: String?
        public let npm: String?
        /// The prefix's node version it was held against.
        public let nodeVersion: String?
        /// The lowest node above `nodeVersion` that `node` accepts — for "needs
        /// Node ≥ X"; nil when the range does not start above it (an npm
        /// requirement, or a range that only caps).
        public let minimumNode: String?

        public init(version: String, node: String?, npm: String?, nodeVersion: String?, minimumNode: String?) {
            self.version = version
            self.node = node
            self.npm = npm
            self.nodeVersion = nodeVersion
            self.minimumNode = minimumNode
        }

        /// "needs Node ≥ 24.16.0" / "needs Node >=24.16.0 <25 || >=26.1.0" / "needs npm >=10".
        public var requirement: String {
            if let minimumNode { return "needs Node ≥ \(minimumNode)" }
            if let node { return "needs Node \(node)" }
            if let npm { return "needs npm \(npm)" }
            return "needs a newer runtime"
        }
    }

    /// Which command a one-click runs.
    public enum Updater: String, Sendable, Equatable, Codable {
        /// `<prefix>/bin/node <prefix>/bin/npm install -g --prefix <prefix> --engine-strict <name>@<version>`.
        case npm
        /// `openclaw update --tag <version>`, by this prefix's node.
        case openclaw
    }

    public let install: NpmInstall
    /// The dist-tag followed; nil when the registry was not asked.
    public let tag: String?
    /// The tag's version.
    public let newest: String?
    public let offered: String?
    public let gap: RuntimeGap?
    /// Versions above the installed one (`NpmPick.pending`), whose release notes
    /// the row shows; the installed version alone when nothing is newer.
    public let pending: [String]
    public let updater: Updater?

    public init(
        install: NpmInstall, tag: String? = nil, newest: String? = nil, offered: String? = nil,
        gap: RuntimeGap? = nil, pending: [String] = [], updater: Updater? = nil
    ) {
        self.install = install
        self.tag = tag
        self.newest = newest
        self.offered = offered
        self.gap = gap
        self.pending = pending
        self.updater = updater
    }

    /// A package known only by its path and version — what the app's tests build.
    public init(path: String, version: String?) {
        let prefix = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        self.init(install: NpmInstall(
            path: path, name: URL(fileURLWithPath: path).lastPathComponent, version: version, manifestName: nil,
            prefix: NodePrefix(path: prefix.path, source: .system, layoutNodeVersion: nil),
            runtime: NpmRuntime(node: nil, npm: nil, npmVersion: nil, nodeSignature: nil, nodeQuarantined: false,
                                nodeVersion: nil)))
    }

    public var path: String { install.path }
    public var version: String? { install.version }
}
