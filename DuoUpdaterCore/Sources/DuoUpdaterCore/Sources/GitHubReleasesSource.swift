import Foundation

/// One app's mapping to a GitHub repository whose Releases drive its version.
public struct GitHubReleaseRule: Sendable {
    /// `CFBundleIdentifier` of the installed app.
    public let bundleID: String
    /// Repo owner, e.g. "rustdesk".
    public let owner: String
    /// Repo name, e.g. "rustdesk".
    public let repo: String
    /// When true, the latest *stable* release isn't what we want (e.g. a Preview
    /// channel publishes prereleases): fetch the releases list and take the
    /// first tag the pattern matches. When false, use `/releases/latest`.
    public let usePrereleases: Bool
    /// Regex applied to a release's `tag_name`; capture group 1 is the version
    /// (e.g. strip a leading `v`, or a `.stable_00` suffix).
    public let versionPattern: String

    /// The release channel this rule's endpoint serves. The source refuses to
    /// apply the rule unless the installed app is on the SAME channel, so a
    /// stable rule can never be served to a nightly install that shares the
    /// bundle id. Defaults to `.stable`.
    public let channel: ReleaseChannel

    /// Regex matched against each release asset's *filename* to pick the macOS
    /// installer to one-click install in place. nil keeps the rule detection-only
    /// (the default and safe stance): we surface the version and link to the
    /// releases page, never install an artifact. Only set this once the asset is
    /// confirmed to be a notarized build signed by the **same Team ID** as the
    /// installed app — `VendorInstaller` enforces that gate, but author defensively.
    public let installAssetPattern: String?
    /// Archive format of the matched asset, so the installer unpacks it correctly.
    /// Required when `installAssetPattern` is set; ignored otherwise.
    public let installerKind: VendorInstallerKind?

    public init(
        bundleID: String,
        owner: String,
        repo: String,
        usePrereleases: Bool = false,
        versionPattern: String = #"v?([0-9]+(?:\.[0-9]+)+)"#,
        installAssetPattern: String? = nil,
        installerKind: VendorInstallerKind? = nil,
        channel: ReleaseChannel = .stable
    ) {
        self.bundleID = bundleID
        self.channel = channel
        self.owner = owner
        self.repo = repo
        self.usePrereleases = usePrereleases
        self.versionPattern = versionPattern
        self.installAssetPattern = installAssetPattern
        self.installerKind = installerKind
    }

    /// First release asset whose filename matches `installAssetPattern`. Pure and
    /// static so the arch/format selection is unit-testable without a fetch.
    static func installableAsset(
        from assets: [(name: String, url: URL)], matching pattern: String
    ) -> URL? {
        installableAsset(from: assets, matching: pattern, preferring: .current)
    }

    /// Arch-aware asset selection. Among the assets matching `pattern`, prefer one
    /// built for `arch`, then an arch-neutral one, and only fall back to a
    /// foreign-arch asset when nothing better matched — so a loose pattern that
    /// matches both an `…-aarch64.dmg` and an `…-x86_64.dmg` still lands the right
    /// build on the right Mac instead of picking whichever GitHub listed first.
    ///
    /// Recipes whose pattern already pins the arch (the current registry anchors
    /// `aarch64`) are unaffected — there's only one match, so it's returned as
    /// before. This just makes a future broad pattern safe.
    static func installableAsset(
        from assets: [(name: String, url: URL)],
        matching pattern: String,
        preferring arch: HostArch
    ) -> URL? {
        let matches = assets.filter {
            $0.name.range(of: pattern, options: .regularExpression) != nil
        }
        guard !matches.isEmpty else { return nil }

        func has(_ tokens: [String], _ name: String) -> Bool {
            let lower = name.lowercased()
            return tokens.contains { lower.contains($0) }
        }

        // 1. An asset explicitly built for this Mac's architecture.
        if let native = matches.first(where: {
            has(arch.assetTokens, $0.name) && !has(arch.foreignTokens, $0.name)
        }) { return native.url }

        // 2. An arch-neutral asset (a universal build, or a name with no arch
        //    marker at all) — safe for either machine.
        if let neutral = matches.first(where: {
            !has(arch.assetTokens, $0.name) && !has(arch.foreignTokens, $0.name)
        }) { return neutral.url }

        // 3. Nothing native or neutral matched — fall back to the first match
        //    (best effort; the pattern author constrained the set deliberately).
        return matches.first?.url
    }

    var slug: String { "\(owner)/\(repo)" }
}

/// Resolves updates for apps distributed through GitHub Releases. Kept separate
/// from `VendorProbeSource` because GitHub is one uniform mechanism (one API,
/// shared rate limit, tag-name parsing) rather than a pile of bespoke endpoints.
///
/// Detection only — like a vendor probe, the result is flagged manual-install:
/// we surface the new version and link to the releases page; we never install a
/// GitHub artifact over a differently-sourced build.
///
/// When no rule maps to an app, returns nil (not applicable). When a rule *does*
/// exist but the fetch fails (network, rate limit, bad status), it throws — so
/// the row surfaces a retryable `.error` instead of a dead "unknown" that reads
/// the same as "no source at all". A parse miss (releases fetched, none match
/// the pattern) still returns nil.
public struct GitHubReleasesSource: UpdateSource {
    public let name = "GitHub"

    /// A GitHub fetch that failed in a way worth retrying (vs. simply not
    /// applying). 403/429 are almost always the unauthenticated 60/hour limit.
    enum GitHubError: LocalizedError {
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .badStatus(403), .badStatus(429):
                return "GitHub rate limit reached — retry shortly"
            case .badStatus(let code):
                return "GitHub returned HTTP \(code)"
            }
        }
    }

    /// Keyed by bundle id → the rules for that id, one per release channel.
    /// Most apps have a single (stable) rule; channels that share a bundle id
    /// list several and are disambiguated by the installed app's detected channel.
    private let rules: [String: [GitHubReleaseRule]]
    private let session: URLSession
    private let token: String?

    public init(
        rules: [GitHubReleaseRule] = GitHubReleaseRegistry.rules,
        token: String? = nil,
        session: URLSession = .updates
    ) {
        self.rules = Dictionary(grouping: rules, by: { $0.bundleID })
        self.token = token
        self.session = session
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // Toolbox-managed apps update through Toolbox — never offer a GitHub
        // artifact over a Toolbox install (no cross-channel mixing).
        guard !app.isToolboxManaged else { return nil }
        guard let bundleID = app.bundleID, let candidates = rules[bundleID] else {
            return nil  // no rule for this app — not applicable
        }
        // Channel gate: pick the rule whose channel matches the installed app's,
        // and refuse if none does. When channels share a bundle id, this selects
        // the right endpoint; when only a stable rule exists, a detected
        // nightly/beta install finds no match and is skipped rather than offered
        // a cross-channel build.
        guard let rule = candidates.first(where: { $0.channel == app.releaseChannel }) else {
            Log.source.info(
                "GitHub skip \(bundleID, privacy: .public): no rule for app channel \(app.releaseChannel.rawValue, privacy: .public)")
            return nil
        }
        // A rule exists: let a fetch failure throw, so the checker turns it into
        // a retryable `.error` row rather than swallowing it into a nil that's
        // indistinguishable from "no source for this app".
        return try await resolve(rule)
    }

    private func resolve(_ rule: GitHubReleaseRule) async throws -> RemoteVersion? {
        let endpoint = rule.usePrereleases
            ? "https://api.github.com/repos/\(rule.slug)/releases?per_page=20"
            : "https://api.github.com/repos/\(rule.slug)/releases/latest"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        // Authenticated requests get 5000/hour instead of 60/hour per IP.
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        Log.source.debug("GitHub GET \(endpoint, privacy: .public) (auth=\(self.token != nil, privacy: .public))")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else {
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
            Log.source.error("GitHub \(rule.slug, privacy: .public): HTTP \(http.statusCode, privacy: .public) (ratelimit-remaining=\(remaining, privacy: .public))")
            throw GitHubError.badStatus(http.statusCode)
        }

        // Walk releases in document order (GitHub returns newest first) and take
        // the first whose tag the pattern matches — for prerelease channels this
        // skips interleaved stable releases.
        let releases = Self.releases(from: data, list: rule.usePrereleases)
        for release in releases {
            if let version = VendorProbeRecipe.extractVersion(from: release.tag, pattern: rule.versionPattern) {
                let page = release.htmlURL ?? URL(string: "https://github.com/\(rule.slug)/releases")
                let body = release.body.flatMap { $0.isEmpty ? nil : $0 }
                let structured = body.flatMap {
                    GitHubMarkdownParser.parse(body: $0, version: version, date: release.publishedAt)
                }

                // When the rule names an installable asset and this release ships
                // a matching one, offer a one-click in-place install (the Team-ID
                // gate in VendorInstaller still guards the swap). Otherwise stay
                // detection-only: link to the releases page, install nothing.
                let installURL = rule.installAssetPattern.flatMap {
                    GitHubReleaseRule.installableAsset(from: release.assets, matching: $0)
                }
                let installable = installURL != nil && rule.installerKind != nil

                await RecipeHealth.shared.recordSuccess(id: rule.slug, source: name)
                return RemoteVersion(
                    shortVersion: version,
                    version: nil,
                    downloadURL: installURL
                        ?? URL(string: "https://github.com/\(rule.slug)/releases"),
                    sourceName: name,
                    requiresManualInstaller: !installable,
                    vendorInstallerKind: installable ? rule.installerKind : nil,
                    releaseNotesHTML: structured == nil ? body : nil,
                    structuredChangelog: structured,
                    changelogURL: page
                )
            }
        }
        Log.source.error("GitHub \(rule.slug, privacy: .public): \(releases.count, privacy: .public) releases fetched, none matched /\(rule.versionPattern, privacy: .public)/")
        // Fetched fine but nothing matched the version pattern — the breakage
        // shape a tag-format change produces. Surface it in diagnostics.
        await RecipeHealth.shared.recordMiss(
            id: rule.slug, source: name,
            detail: "\(releases.count) releases fetched, none matched the version pattern")
        return nil
    }

    /// A GitHub release reduced to the fields we use: tag, notes body, page URL,
    /// date, and downloadable assets (filename → URL, for installer selection).
    private struct Release {
        let tag: String
        let body: String?
        let htmlURL: URL?
        let publishedAt: String?
        let assets: [(name: String, url: URL)]
    }

    /// Extract releases from either a single release object or a list.
    private static func releases(from data: Data, list: Bool) -> [Release] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let objects: [[String: Any]]
        if list {
            objects = json as? [[String: Any]] ?? []
        } else {
            objects = (json as? [String: Any]).map { [$0] } ?? []
        }
        return objects.compactMap { obj in
            guard let tag = obj["tag_name"] as? String else { return nil }
            let assets: [(name: String, url: URL)] = (obj["assets"] as? [[String: Any]] ?? [])
                .compactMap { asset in
                    guard let name = asset["name"] as? String,
                          let urlString = asset["browser_download_url"] as? String,
                          let url = URL(string: urlString) else { return nil }
                    return (name, url)
                }
            return Release(
                tag: tag,
                body: obj["body"] as? String,
                htmlURL: (obj["html_url"] as? String).flatMap { URL(string: $0) },
                publishedAt: obj["published_at"] as? String,
                assets: assets
            )
        }
    }
}

/// The verified bundleID → GitHub repo table. Every entry was confirmed against
/// the live Releases API to yield the app's current version.
public enum GitHubReleaseRegistry {
    public static let rules: [GitHubReleaseRule] = [
        // Zed Stable — same repo, but stable ships as non-prerelease tags
        // (`vX.Y.Z`, no `-pre`). `usePrereleases: false` (default) reads
        // `/releases/latest`, which GitHub computes excluding prereleases, so it
        // returns the newest stable (`v1.5.3`) and never a `-pre` build; the
        // default pattern strips the `v` → `1.5.3`, matching the installed
        // `dev.zed.Zed`'s `CFBundleShortVersionString`. Channel-gated to `.stable`
        // (default) so it can't be served to the Preview install that ships under
        // a different bundle id anyway. Detection-only: a `Zed-aarch64.dmg` asset
        // ships, but its Team ID isn't confirmed against the install and Zed has
        // its own updater, so no `installAssetPattern` — same stance as Preview.
        // Closes the stable-channel version gap the 2026-06-04 audit surfaced
        // (Homebrew `auto_updates` falls through, no `SUFeedURL`).
        GitHubReleaseRule(
            bundleID: "dev.zed.Zed",
            owner: "zed-industries", repo: "zed"),

        // Zed Preview — the Preview channel ships as prereleases (`vX.Y.Z-pre`).
        // MUST declare `channel: .preview`: the Preview install detects as
        // `.preview`, and the source's channel gate refuses any rule whose channel
        // doesn't match the install. Without this the rule defaults to `.stable`
        // and the gate skips it, leaving a real Preview install with no source
        // (regressed when the channel gate landed; caught by the live `--check`).
        GitHubReleaseRule(
            bundleID: "dev.zed.Zed-Preview",
            owner: "zed-industries", repo: "zed",
            usePrereleases: true,
            versionPattern: #"v([0-9]+\.[0-9]+\.[0-9]+)-pre"#,
            channel: .preview),

        // Pearcleaner — tags have no `v` prefix.
        GitHubReleaseRule(
            bundleID: "com.alienator88.Pearcleaner",
            owner: "alienator88", repo: "Pearcleaner"),

        // RustDesk — tags have no `v` prefix. One-click installs the arm64 dmg
        // asset (`rustdesk-<ver>-aarch64.dmg`): the official GitHub build is a
        // notarized Developer ID app, Team ID HZF9JMC8YN (zhou huabing), matching
        // the installed copy — so the VendorInstaller Team-ID gate passes. arm64
        // only, like the other Apple-silicon recipes; an Intel asset also ships
        // (`…-x86_64.dmg`) but we don't select it.
        GitHubReleaseRule(
            bundleID: "com.carriez.rustdesk",
            owner: "rustdesk", repo: "rustdesk",
            // Anchor the whole filename (`rustdesk-<ver>-aarch64.dmg`) rather than
            // just the suffix, so a future flavored arm64 dmg (e.g. a `-sciter`
            // build) can't be picked by position instead of the canonical asset.
            installAssetPattern: #"^rustdesk-[0-9.]+-aarch64\.dmg$"#,
            installerKind: .dmg),

        // Alcove — dedicated releases repo, no `v` prefix.
        GitHubReleaseRule(
            bundleID: "com.henrikruscon.Alcove",
            owner: "henrikruscon", repo: "alcove-releases"),

        // Macs Fan Control — tags carry a `v` prefix (stripped by the pattern).
        GitHubReleaseRule(
            bundleID: "com.crystalidea.macsfancontrol",
            owner: "crystalidea", repo: "macs-fan-control"),

        // Stats — macOS menu-bar system monitor. Tags carry a `v` prefix
        // (stripped by the default pattern). Stable channel, no prereleases.
        // Detection-only: a single `Stats.dmg` asset ships, but its Team ID isn't
        // confirmed against the installed copy, so no installAssetPattern.
        GitHubReleaseRule(
            bundleID: "eu.exelban.Stats",
            owner: "exelban", repo: "stats"),

        // DBeaver Community — tags are bare dotted versions (no `v` prefix), e.g.
        // `26.1.0`; the `dbeaver/dbeaver` repo tracks the Community version scheme,
        // so /releases/latest matches the installed CE version directly.
        // Detection-only.
        GitHubReleaseRule(
            bundleID: "org.jkiss.dbeaver.core.product",
            owner: "dbeaver", repo: "dbeaver"),

        // Beekeeper Studio (Community) — tags carry a `v` prefix (v5.8.1),
        // stripped by the default pattern. Betas ship as `vX.Y.Z-beta.N` flagged
        // prerelease, so usePrereleases=false / `/releases/latest` correctly skips
        // them. Detection-only.
        GitHubReleaseRule(
            bundleID: "io.beekeeperstudio.desktop",
            owner: "beekeeper-studio", repo: "beekeeper-studio"),

        // Insomnia — Kong/insomnia is a monorepo whose Releases are tagged per
        // package (`core@X.Y.Z` is the Insomnia desktop app; `lib@…`/`inso@…` are
        // sibling packages). `/releases/latest` could resolve to a non-core
        // release, so scan the list (usePrereleases) and take the first tag the
        // pattern matches. The `core@`-anchored pattern matches ONLY the app's
        // tags — lib@/inso@ yield no capture and are skipped — and since GitHub
        // returns newest-first, the first `core@` hit is the latest; interleaved
        // `core@…-beta.N` sort after the stable release of the same line.
        // Detection-only.
        GitHubReleaseRule(
            bundleID: "com.insomnia.app",
            owner: "Kong", repo: "insomnia",
            usePrereleases: true,
            versionPattern: #"core@([0-9]+\.[0-9]+\.[0-9]+)"#),

        // Zen Browser — stable tags carry a trailing letter suffix (e.g.
        // "1.20.1b"). That suffix is PART of the CFBundleShortVersionString, so
        // the pattern MUST keep the trailing [a-z] — stripping it would read as a
        // perpetual update/downgrade. Zen also publishes a rolling "twilight"
        // prerelease; /releases/latest (usePrereleases: false) excludes it.
        // Detection-only.
        GitHubReleaseRule(
            bundleID: "app.zen-browser.zen",
            owner: "zen-browser", repo: "desktop",
            usePrereleases: false,
            versionPattern: #"([0-9]+\.[0-9]+(?:\.[0-9]+)?[a-z]?)"#),

        // GitHub Desktop — both production and beta/test builds publish here, and
        // beta/test tags are interleaved AHEAD of production in the releases list
        // (e.g. `release-3.5.12-beta2` sits above `release-3.5.12`). Betas are
        // prerelease=true and `/releases/latest` resolves to the production tag,
        // so usePrereleases=false. The `$`-anchored pattern is belt-and-suspenders:
        // it captures only the bare X.Y.Z from a plain `release-X.Y.Z` tag and
        // refuses any `-beta`/`-test` suffix. Detection-only.
        GitHubReleaseRule(
            bundleID: "com.github.GitHubClient",
            owner: "desktop", repo: "desktop",
            usePrereleases: false,
            versionPattern: #"release-([0-9]+\.[0-9]+\.[0-9]+)$"#),
    ]
}
