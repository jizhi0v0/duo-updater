import Foundation

/// Reads JetBrains Toolbox's local files to learn which apps it manages and the
/// per-tool context needed to check for updates. The *installed* facts here
/// (path, productCode, installed build, channel) come from `state.json`, which
/// Toolbox writes at install time and which stay accurate even when Toolbox
/// isn't running. The "latest available build" it also caches
/// (`channels/<id>.json`) can go stale if Toolbox hasn't refreshed — so that
/// part is only a *fallback*; `ToolboxSource` prefers a live API when it can.
///
/// Two installs can share a bundle id (Android Studio Koala *and* Otter are both
/// `com.google.android.studio`), so everything is keyed by resolved install path.
public struct ToolboxInventory: Sendable {

    /// Per-tool context for an update check.
    public struct Tool: Sendable, Hashable {
        /// JetBrains product code from `state.json` ("IU", "AI", …). nil for
        /// tools without one (Air/Fleet). Drives the live API lookup.
        public let productCode: String?
        /// Release channel for the API: "release" or "eap".
        public let channelType: String
        /// Human-facing version Toolbox shows, reduced to its numeric core
        /// ("Otter 3 Feature Drop 2025.2.3" → "2025.2.3", "261.474 Public
        /// Preview" → "261.474"). The on-disk `CFBundleShortVersionString` is
        /// often truncated ("2025.2") or build-shaped ("261.617"), so this is the
        /// accurate string to display as the installed version.
        public let displayVersion: String
        /// Installed build number, e.g. "261.24374.151".
        public let installedBuild: String
        /// The version line this tool is PINNED to in Toolbox ("keep version" —
        /// the channel's `version_filter`, e.g. "2025.2.3"), or nil when it
        /// freely tracks the latest. A pinned tool must not be nagged about an
        /// update that crosses its line (a kept 2025.2.x shouldn't surface 2025.3).
        public let pinnedLine: String?
        /// Newest build Toolbox has cached locally (the stale-able fallback).
        public let localLatestVersion: String?
        public let localLatestBuild: String?
        /// True when this is the newest install of its product code on the
        /// machine. When several copies share a product (Android Studio Koala +
        /// Otter), only the newest tracks a live feed; older retained copies stay
        /// on the local cache so they don't nag about a cross-major upgrade.
        public let isNewestOfProduct: Bool

        public init(
            productCode: String?, channelType: String, installedBuild: String,
            localLatestVersion: String?, localLatestBuild: String?,
            isNewestOfProduct: Bool = true,
            displayVersion: String = "", pinnedLine: String? = nil
        ) {
            self.productCode = productCode
            self.channelType = channelType
            self.installedBuild = installedBuild
            self.localLatestVersion = localLatestVersion
            self.localLatestBuild = localLatestBuild
            self.isNewestOfProduct = isNewestOfProduct
            self.displayVersion = displayVersion
            self.pinnedLine = pinnedLine
        }
    }

    private let managedPaths: Set<String>
    private let toolsByPath: [String: Tool]

    public init(stateURL: URL? = nil) {
        let url = stateURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/JetBrains/Toolbox/state.json")

        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tools = json["tools"] as? [[String: Any]]
        else {
            self.managedPaths = []
            self.toolsByPath = [:]
            return
        }

        let channelsDir = url.deletingLastPathComponent().appendingPathComponent("channels")

        // First pass: collect the raw facts + the newest installed build per
        // product code (to flag retained older copies).
        struct Raw { let path: String; let productCode: String?; let channelType: String
                     let installedBuild: String; let localVersion: String?; let localBuild: String?
                     let displayVersion: String; let pinnedLine: String? }
        var paths = Set<String>()
        var raws: [Raw] = []
        var newestBuildByCode: [String: String] = [:]
        for tool in tools {
            guard let loc = tool["installLocation"] as? String else { continue }
            let resolved = URL(fileURLWithPath: loc).resolvingSymlinksInPath().path
            paths.insert(resolved)
            guard let installedBuild = tool["buildNumber"] as? String else { continue }
            let channel = (tool["channelId"] as? String)
                .flatMap { Self.channelInfo(channelsDir: channelsDir, channelId: $0) }
            let code = tool["productCode"] as? String
            let display = (tool["displayVersion"] as? String).map(Self.numericVersion(from:)) ?? ""
            raws.append(Raw(path: resolved, productCode: code, channelType: channel?.type ?? "release",
                            installedBuild: installedBuild, localVersion: channel?.version, localBuild: channel?.build,
                            displayVersion: display, pinnedLine: channel?.pinnedLine))
            if let code {
                if let cur = newestBuildByCode[code] {
                    if VersionComparator.isNewer(installedBuild, than: cur) { newestBuildByCode[code] = installedBuild }
                } else {
                    newestBuildByCode[code] = installedBuild
                }
            }
        }

        var byPath = [String: Tool]()
        for r in raws {
            let isNewest = r.productCode.map { newestBuildByCode[$0] == r.installedBuild } ?? true
            byPath[r.path] = Tool(
                productCode: r.productCode, channelType: r.channelType,
                installedBuild: r.installedBuild,
                localLatestVersion: r.localVersion, localLatestBuild: r.localBuild,
                isNewestOfProduct: isNewest,
                displayVersion: r.displayVersion, pinnedLine: r.pinnedLine)
        }
        self.managedPaths = paths
        self.toolsByPath = byPath
    }

    /// Test seam: managed paths only.
    public init(managedPaths: Set<String>) {
        self.managedPaths = Set(
            managedPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        self.toolsByPath = [:]
    }

    /// Test seam: managed paths plus per-path tool context.
    public init(managedPaths: Set<String>, tools: [String: Tool]) {
        self.managedPaths = Set(
            managedPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        self.toolsByPath = Dictionary(uniqueKeysWithValues: tools.map {
            (URL(fileURLWithPath: $0.key).resolvingSymlinksInPath().path, $0.value)
        })
    }

    public func isManaged(appPath: URL) -> Bool {
        managedPaths.contains(appPath.resolvingSymlinksInPath().path)
    }

    public func tool(forApp appPath: URL) -> Tool? {
        toolsByPath[appPath.resolvingSymlinksInPath().path]
    }

    /// Reduce Toolbox's verbose `displayVersion` to its dotted-numeric core so it
    /// reads like the rest of the UI. "Otter 3 Feature Drop 2025.2.3" → "2025.2.3"
    /// (the leading codename digit "3" is not part of a dotted run); "261.474
    /// Public Preview" → "261.474". Falls back to the raw string when there's no
    /// dotted version in it.
    static func numericVersion(from raw: String) -> String {
        VendorProbeRecipe.extractVersion(from: raw, pattern: #"([0-9]+(?:\.[0-9]+)+)"#) ?? raw
    }

    /// Channel cache: the highest `build.id` + its `version.name` (both nil when
    /// Toolbox hasn't cached this channel's builds yet), the configured release
    /// channel ("release"/"eap" from the quality filter), and the pinned version
    /// line ("keep version" — the `version_filter.name`, nil when absent).
    private static func channelInfo(channelsDir: URL, channelId: String)
        -> (version: String?, build: String?, type: String, pinnedLine: String?)? {
        let file = channelsDir.appendingPathComponent("\(channelId).json")
        guard
            let data = try? Data(contentsOf: file),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let channel = json["channel"] as? [String: Any]
        else { return nil }

        // Quality filter: order_value 10000 == Release; higher == EAP/Beta/etc.
        // version_filter is present only when the user pinned a version line.
        var type = "release"
        var pinnedLine: String?
        if let filter = channel["updateFilter"] as? [String: Any] {
            if let quality = filter["quality_filter"] as? [String: Any],
               let order = quality["order_value"] as? Int, order > 10000 {
                type = "eap"
            }
            pinnedLine = (filter["version_filter"] as? [String: Any])?["name"] as? String
        }

        // The cached "available builds" can be empty — Toolbox hasn't fetched this
        // channel yet (common for a freshly-added EAP tool). That must NOT erase the
        // channel TYPE we just read: `type` is what routes `ToolboxSource` to the
        // right live API track (eap vs release). Returning nil here used to collapse
        // the whole channel to the "release" default at the call site, which sent an
        // EAP install to the stable feed and reported it as up to date (hiding it).
        // So keep type + pin; leave version/build nil so the live query is used.
        var best: (version: String, build: String)?
        if let history = channel["history"] as? [String: Any],
           let toolBuilds = history["toolBuilds"] as? [[String: Any]] {
            for entry in toolBuilds {
                guard let build = entry["build"] as? [String: Any],
                      let id = build["id"] as? String,
                      let version = entry["version"] as? [String: Any],
                      let name = version["name"] as? String
                else { continue }
                if best == nil || VersionComparator.isNewer(id, than: best!.build) {
                    best = (name, id)
                }
            }
        }
        return (best?.version, best?.build, type, pinnedLine)
    }
}
