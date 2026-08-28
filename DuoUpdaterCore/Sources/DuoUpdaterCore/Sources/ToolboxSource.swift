import Foundation

/// Decides whether a JetBrains-Toolbox-managed app has an update. Every answer
/// comes from a LIVE query, because Toolbox's own files record only what it has
/// INSTALLED — never what's available (see below) — so they can't answer the
/// question at all.
///
/// Strategy, per tool:
///   1. JetBrains IDEs (have a product code, e.g. "IU"): ask the public JetBrains
///      releases API for the latest build in its channel.
///   2. Android Studio (Google, code "AI"): Google's live stable feed. Only the
///      NEWEST install of the product follows it; a retained older copy abstains
///      so it can't nag about a cross-major jump.
///   3. Air/Fleet (NO product code): the Sparkle feed, but RETARGETED to the
///      channel Toolbox actually tracks. The app's baked-in SUFeedURL points at
///      'nightly' (262.x) even on a Public Preview install — wrong channel — so we
///      swap the channel segment to Toolbox's quality ("eap") to reach the Public
///      Preview feed.
/// In every case the comparison is the live build id vs Toolbox's `installedBuild`
/// (`state.json`), which share one 3-part namespace — NOT the app's
/// CFBundleShortVersionString, which for Air/Fleet is a divergent SHIP-runtime
/// track (261.617 vs the managed 261.474.x) and would mis-compare. The action
/// stays "open Toolbox"; we never install a build ourselves.
///
/// No offline fallback exists, by design. Toolbox's `history.toolBuilds` reads
/// like an "available builds" cache but is an INSTALL history — its newest entry
/// is, by construction, the build already installed. Comparing against it can only
/// ever answer "up to date", which is a lie dressed as an answer when the live
/// query is what actually failed. We return nil instead and the row says
/// "managed by Toolbox" until a live query succeeds.
public struct ToolboxSource: Sendable {

    public struct Verdict: Sendable, Hashable {
        public let hasUpdate: Bool
        /// Display version of the latest, e.g. "2026.1.3".
        public let latestVersion: String
        /// Build number of the latest, e.g. "262.7132.23". Used to disambiguate an
        /// EAP/nightly bump that keeps the same marketing version ("2026.2 → 2026.2"
        /// really being 262.6653.22 → 262.7132.23) — the UI surfaces the build then.
        /// nil when a source doesn't expose a distinct build id.
        public let latestBuild: String?
        /// The latest build's release-notes page, when the source exposes one.
        /// JetBrains' releases API carries a per-build `notesLink` (a YouTrack
        /// article); we surface it so a Toolbox-managed IDE without a structured
        /// `ChangelogRecipe` still shows real notes in a web view instead of the
        /// "no changelog" placeholder. nil for sources that publish none (Google's
        /// Android Studio feed, Air/Fleet Sparkle).
        public let changelogURL: URL?

        public init(hasUpdate: Bool, latestVersion: String, latestBuild: String? = nil, changelogURL: URL? = nil) {
            self.hasUpdate = hasUpdate
            self.latestVersion = latestVersion
            self.latestBuild = latestBuild
            self.changelogURL = changelogURL
        }
    }

    private let inventory: ToolboxInventory
    private let session: URLSession

    public init(inventory: ToolboxInventory = ToolboxInventory(), session: URLSession = .shared) {
        self.inventory = inventory
        self.session = session
    }

    /// Toolbox's latest-vs-installed verdict for this app, or nil when we can't
    /// answer: not a Toolbox tool, or the live query for it didn't land. Nil is an
    /// abstention (the row falls back to a plain "managed by Toolbox" label), never
    /// an implied "up to date" — see the type doc on why there's no offline answer.
    public func verdict(for app: InstalledApp) async -> Verdict? {
        guard let tool = inventory.tool(forApp: app.path) else { return nil }

        // Android Studio (Google, code "AI" — not on the JetBrains API). Only the
        // NEWEST install of the product follows Google's live stable feed; an older
        // retained copy (a kept-around Koala) abstains, so it can't nag about a
        // cross-major jump to the current release.
        if tool.productCode == "AI" {
            guard tool.isNewestOfProduct, let latest = try? await androidStudioLatest() else {
                return nil
            }
            return Self.verdict(latestBuild: latest.build, display: latest.version, tool: tool)
        }

        // Air/Fleet have no JetBrains product code; their update lives in a
        // channel-correct Sparkle feed, which reports a bare build id — so compare
        // it against the build Toolbox records as installed, the one value that
        // shares the feed's 3-part namespace (and the one the row displays).
        guard let code = tool.productCode else {
            guard let raw = app.sparkleFeedURL,
                  let feed = Self.retargetChannel(raw, to: tool.channelType),
                  let latest = try? await sparkleLatest(feed)
            else { return nil }
            return Verdict(hasUpdate: VersionComparator.isNewer(latest, than: tool.installedBuild),
                           latestVersion: latest, latestBuild: latest)
        }

        // JetBrains IDEs: the live releases API is the only source; no answer, no
        // verdict.
        guard let latest = try? await apiLatest(code: code, type: tool.channelType) else {
            return nil
        }
        return Self.verdict(latestBuild: latest.build, display: latest.version,
                            tool: tool, changelogURL: latest.notesLink)
    }

    /// Rewrite a Fleet/Air Sparkle feed URL to a different channel: the path is
    /// `…/fleet-feed/AIR/<channel>/macos_aarch64/feed.xml`, and the build ships
    /// it hardcoded to 'nightly' even on a Public Preview install — we swap in the
    /// channel Toolbox really tracks (its quality filter → "eap"/"release").
    static func retargetChannel(_ feed: URL, to channelType: String) -> URL? {
        guard var comps = URLComponents(url: feed, resolvingAgainstBaseURL: false) else { return nil }
        var segs = feed.pathComponents.filter { $0 != "/" }
        guard let i = segs.firstIndex(of: "fleet-feed"), i + 2 < segs.count else { return nil }
        segs[i + 2] = channelType
        comps.path = "/" + segs.joined(separator: "/")
        return comps.url
    }

    /// Newest build from a single-item Fleet/Air Sparkle appcast
    /// (`<sparkle:version>261.584.13</sparkle:version>`).
    private func sparkleLatest(_ feed: URL) async throws -> String? {
        var request = URLRequest(url: feed)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.versionFeedData(
            for: request, label: "Toolbox sparkle feed")
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        let body = String(decoding: data, as: UTF8.self)
        return VendorProbeRecipe.extractVersion(
            from: body, pattern: #"<sparkle:version>([0-9.]+)</sparkle:version>"#)
    }

    /// Shape a live latest-build answer into a verdict against what Toolbox has
    /// installed, applying the "keep version" pin. Internal so the pin rules can be
    /// tested directly — they're the half of this file with no network in their path.
    static func verdict(
        latestBuild: String, display: String, tool: ToolboxInventory.Tool,
        changelogURL: URL? = nil
    ) -> Verdict {
        // "Keep version" pin: the user told Toolbox to stay on a version line, so
        // never nag about a build that leaves it. JetBrains/Google build numbers
        // encode the line in their leading branch component (252 == 2025.2,
        // 253 == 2025.3), so an update is in-line only when its branch matches the
        // installed build's — a same-line patch still surfaces; a cross-major jump
        // (the kept Android Studios → 2025.3) is suppressed, and we report the
        // installed version as "latest" so nothing downstream sees a phantom bump.
        if tool.pinnedLine != nil,
           Self.branch(of: latestBuild) != Self.branch(of: tool.installedBuild) {
            let installedDisplay = tool.displayVersion.isEmpty ? display : tool.displayVersion
            // Report the installed build as "latest" too, so nothing downstream sees
            // a phantom bump from the cross-line build we're suppressing.
            return Verdict(hasUpdate: false, latestVersion: installedDisplay,
                           latestBuild: tool.installedBuild, changelogURL: changelogURL)
        }
        return Verdict(hasUpdate: VersionComparator.isNewer(latestBuild, than: tool.installedBuild),
                       latestVersion: display, latestBuild: latestBuild, changelogURL: changelogURL)
    }

    /// The leading (branch) component of a build number — "252" of
    /// "252.28238.7.2523.14688667". Empty for an empty string.
    private static func branch(of build: String) -> Substring {
        build.prefix { $0 != "." }
    }

    /// Latest STABLE Android Studio from Google's update feed — the first
    /// `<build>` in the `status="release"` channel. The build number is
    /// `AI-253.32098.…`; we strip `AI-` to compare against `state.json`'s build.
    private func androidStudioLatest() async throws -> (version: String, build: String)? {
        let url = URL(string: "https://dl.google.com/android/studio/patches/updates.xml")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.versionFeedData(
            for: request, label: "Android Studio updates.xml")
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        let body = String(decoding: data, as: UTF8.self)

        // Grab the opening tag of the first <build> inside the release channel,
        // then pull its attributes (order-independent).
        guard let tag = Self.firstMatch(
            in: body, pattern: #"status="release"[\s\S]*?(<build\s[^>]*>)"#)
        else { return nil }
        guard let build = Self.firstMatch(in: tag, pattern: #"number="AI-([0-9.]+)""#)
        else { return nil }
        // version attr is like "Panda 4 | 2025.3.4 Patch 1" — keep the numeric
        // part after the codename for a cleaner "→ 2025.3.4 Patch 1".
        let raw = Self.firstMatch(in: tag, pattern: #"version="([^"]+)""#) ?? build
        let version = raw.components(separatedBy: " | ").last ?? raw
        return (version, build)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        VendorProbeRecipe.extractVersion(from: text, pattern: pattern)
    }

    /// Latest (version, build, notesLink) for a JetBrains product code in a
    /// channel. `notesLink` is the build's YouTrack release-notes article when the
    /// API carries one (nil otherwise). Returns nil for unknown codes (e.g.
    /// Android Studio's "AI" → empty `{}`) so the caller falls back to the cache.
    private func apiLatest(code: String, type: String) async throws
        -> (version: String, build: String, notesLink: URL?)? {
        let endpoint = "https://data.services.jetbrains.com/products/releases?code=\(code)&latest=true&type=\(type)"
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.versionFeedData(
            for: request, label: "Toolbox feed")
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Shape: { "<APICODE>": [ { "version": "2026.1.2", "build": "261.…",
        //          "notesLink": "https://youtrack.jetbrains.com/articles/…", … } ] }
        for (_, value) in json {
            if let releases = value as? [[String: Any]],
               let first = releases.first,
               let version = first["version"] as? String,
               let build = first["build"] as? String {
                let notes = (first["notesLink"] as? String).flatMap(URL.init(string:))
                return (version, build, notes)
            }
        }
        return nil
    }
}
