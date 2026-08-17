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

    /// First release asset whose filename matches `installAssetPattern`, with
    /// its declared byte size (for shortest-first "Update All" ordering). Pure
    /// and static so the arch/format selection is unit-testable without a fetch.
    static func installableAsset(
        from assets: [(name: String, url: URL, size: Int64?)], matching pattern: String
    ) -> (url: URL, size: Int64?)? {
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
        from assets: [(name: String, url: URL, size: Int64?)],
        matching pattern: String,
        preferring arch: HostArch,
        allowingIntelTranslation canRunIntel: Bool = HostArch.canRunIntelBuilds
    ) -> (url: URL, size: Int64?)? {
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
        }) { return (native.url, native.size) }

        // 2. An arch-neutral asset (a universal build, or a name with no arch
        //    marker at all) — safe for either machine.
        if let neutral = matches.first(where: {
            !has(arch.assetTokens, $0.name) && !has(arch.foreignTokens, $0.name)
        }) { return (neutral.url, neutral.size) }

        // 3. Everything that matched is built for the OTHER architecture. Offering
        //    it is only better than offering nothing while the machine can still
        //    RUN it — an Intel build on Apple silicon, and only for as long as
        //    Rosetta covers apps (see `HostArch.canRunIntelBuilds`). Otherwise
        //    resolve nothing: the row stays detection-only, showing the version and
        //    linking to the releases page, instead of swapping in a bundle that
        //    will not launch. The reverse direction is never offered — an arm64
        //    build has never run on an Intel Mac.
        guard arch == .arm64, canRunIntel else { return nil }
        return matches.first.map { ($0.url, $0.size) }
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
                // The phrase "rate limit" is the contract `UpdateStatus.isRateLimitError`
                // matches on to drive the rate-limit UI nudges — keep it in the string.
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
        return try await resolve(rule).remote
    }

    /// Run one rule and report everything that happened — the counterpart to
    /// `VendorProbeSource.probeDiagnostic`, so an automated sweep can judge
    /// GitHub rules by the same taxonomy as vendor recipes.
    ///
    /// Kept on the source, not in the sweeping tool, so it shares this type's
    /// endpoint construction, token handling and cache policy. The "body sample"
    /// is the tag list — for a GitHub rule the tags *are* the surface a version
    /// pattern is written against, and they're what you need to repair one.
    public func resolveDiagnostic(_ rule: GitHubReleaseRule) async -> ProbeOutcome {
        let started = DispatchTime.now()
        func elapsed() -> Int {
            Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
        }
        func outcome(
            remote: RemoteVersion?, failure: ProbeFailure?, tags: [String] = [], status: Int? = nil
        ) -> ProbeOutcome {
            ProbeOutcome(
                recipeID: "github:\(rule.slug):\(rule.channel.rawValue)",
                bundleID: rule.bundleID, channel: rule.channel,
                remote: remote, failure: failure, httpStatus: status,
                bodySample: tags.isEmpty ? nil : tags.joined(separator: "\n"),
                elapsedMs: elapsed())
        }

        do {
            let resolved = try await resolve(rule)
            if let remote = resolved.remote {
                return outcome(remote: remote, failure: nil, tags: resolved.tags)
            }
            // Fetched fine, no tag matched — the shape a tag-format change makes.
            return outcome(
                remote: nil,
                failure: .versionPatternNoMatch(
                    sampleBytes: resolved.tags.joined(separator: "\n").utf8.count),
                tags: resolved.tags)
        } catch GitHubError.badStatus(let code) {
            return outcome(remote: nil, failure: .httpStatus(code), status: code)
        } catch {
            return outcome(remote: nil, failure: Self.transportFailure(error))
        }
    }

    private static func transportFailure(_ error: Error) -> ProbeFailure {
        let urlError = error as? URLError
        return .transport(
            urlErrorCode: urlError?.errorCode ?? (error as NSError).code,
            urlError?.localizedDescription ?? error.localizedDescription)
    }

    /// Also returns the tags it examined: on a pattern miss those are the only
    /// evidence of *why*, and `resolveDiagnostic` has no other way to see them.
    private func resolve(
        _ rule: GitHubReleaseRule
    ) async throws -> (remote: RemoteVersion?, tags: [String]) {
        let endpoint = rule.usePrereleases
            ? "https://api.github.com/repos/\(rule.slug)/releases?per_page=20"
            : "https://api.github.com/repos/\(rule.slug)/releases/latest"
        guard let url = URL(string: endpoint) else { return (nil, []) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        // Authenticated requests get 5000/hour instead of 60/hour per IP.
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        Log.source.debug("GitHub GET \(endpoint, privacy: .public) (auth=\(self.token != nil, privacy: .public))")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return (nil, []) }
        guard (200..<300).contains(http.statusCode) else {
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
            Log.source.error("GitHub \(rule.slug, privacy: .public): HTTP \(http.statusCode, privacy: .public) (ratelimit-remaining=\(remaining, privacy: .public))")
            throw GitHubError.badStatus(http.statusCode)
        }

        // Walk releases in document order (GitHub returns newest first) and take
        // the first whose tag the pattern matches — for prerelease channels this
        // skips interleaved stable releases.
        let releases = Self.releases(from: data, list: rule.usePrereleases)
        // Every matching release that carries a publish date — backfills the app's
        // visible release history into the timeline at no extra network cost (these
        // are the same releases we already fetched). A single-`latest` fetch yields
        // just one entry; a prerelease-channel list yields the whole page.
        let history: [ReleaseHistoryEntry] = releases.compactMap { release in
            guard let v = VendorProbeRecipe.extractVersion(from: release.tag, pattern: rule.versionPattern),
                  let date = ReleaseDate.parse(release.publishedAt) else { return nil }
            return ReleaseHistoryEntry(version: v, publishedAt: date)
        }
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
                let asset = rule.installAssetPattern.flatMap {
                    GitHubReleaseRule.installableAsset(from: release.assets, matching: $0)
                }
                let installable = asset?.url != nil && rule.installerKind != nil

                await RecipeHealth.shared.recordSuccess(id: rule.slug, source: name)
                return (RemoteVersion(
                    shortVersion: version,
                    version: nil,
                    downloadURL: asset?.url
                        ?? URL(string: "https://github.com/\(rule.slug)/releases"),
                    // The release page — an asset URL would download the archive.
                    pageURL: page,
                    downloadSize: asset?.size,
                    sourceName: name,
                    requiresManualInstaller: !installable,
                    vendorInstallerKind: installable ? rule.installerKind : nil,
                    releaseNotesHTML: structured == nil ? body : nil,
                    structuredChangelog: structured,
                    changelogURL: page,
                    publishedAt: ReleaseDate.parse(release.publishedAt),
                    releaseHistory: history
                ), releases.map(\.tag))
            }
        }
        Log.source.error("GitHub \(rule.slug, privacy: .public): \(releases.count, privacy: .public) releases fetched, none matched /\(rule.versionPattern, privacy: .public)/")
        // Fetched fine but nothing matched the version pattern — the breakage
        // shape a tag-format change produces. Surface it in diagnostics.
        await RecipeHealth.shared.recordMiss(
            id: rule.slug, source: name,
            detail: "\(releases.count) releases fetched, none matched the version pattern")
        return (nil, releases.map(\.tag))
    }

    /// A GitHub release reduced to the fields we use: tag, notes body, page URL,
    /// date, and downloadable assets (filename → URL + declared size, for
    /// installer selection and shortest-first "Update All" ordering).
    private struct Release {
        let tag: String
        let body: String?
        let htmlURL: URL?
        let publishedAt: String?
        let assets: [(name: String, url: URL, size: Int64?)]
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
            let assets: [(name: String, url: URL, size: Int64?)] = (obj["assets"] as? [[String: Any]] ?? [])
                .compactMap { asset in
                    guard let name = asset["name"] as? String,
                          let urlString = asset["browser_download_url"] as? String,
                          let url = URL(string: urlString) else { return nil }
                    let size = (asset["size"] as? NSNumber)?.int64Value
                    return (name, url, size)
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
        // MARK: - AI desktop clients (verified 2026-08-17)

        // OpenCode Desktop — the stable tag and the app's marketing/build versions
        // are the same bare numeric value after stripping `v`. The release carries
        // native arm64 and x64 dmgs; `installableAsset` selects the host-native one.
        // Mounted arm64 dmg: ai.opencode.desktop, Team 5NZ4Q7NXJ4, notarized.
        GitHubReleaseRule(
            bundleID: "ai.opencode.desktop",
            owner: "anomalyco", repo: "opencode",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^opencode-desktop-mac-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg),

        // OpenChamber — electron-builder publishes both architectures beside
        // Windows/Linux/mobile artifacts. Keep the extension and mac token
        // anchored; the architecture-aware selector chooses arm64 or x64.
        // Mounted arm64 dmg: dev.openchamber.desktop, Team 5J7WJGPA2Q, notarized.
        GitHubReleaseRule(
            bundleID: "dev.openchamber.desktop",
            owner: "openchamber", repo: "openchamber",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenChamber-[0-9.]+-mac-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg),

        // Jan ships a universal macOS zip whose app reports the release tag's
        // version verbatim. Mounted/extracted zip: jan.ai.app, Team F8AH6NHVY5,
        // notarized. Pin the desktop asset; the same release carries source and
        // dependency archives plus Linux/Windows builds.
        GitHubReleaseRule(
            bundleID: "jan.ai.app",
            owner: "janhq", repo: "jan",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^jan-mac-universal-[0-9.]+\.zip$"#,
            installerKind: .zip),

        // Zed Stable — same repo, but stable ships as non-prerelease tags
        // (`vX.Y.Z`, no `-pre`). `usePrereleases: false` (default) reads
        // `/releases/latest`, which GitHub computes excluding prereleases, so it
        // returns the newest stable (`v1.5.3`) and never a `-pre` build; the
        // default pattern strips the `v` → `1.5.3`, matching the installed
        // `dev.zed.Zed`'s `CFBundleShortVersionString`. Channel-gated to `.stable`
        // (default) so it can't be served to the Preview install that ships under
        // a different bundle id anyway. Closes the stable-channel version gap the
        // 2026-06-04 audit surfaced (Homebrew `auto_updates` falls through, no
        // `SUFeedURL`).
        //
        // Best-effort one-click: the stable `/releases/latest` ships `Zed-aarch64.dmg`,
        // whose `Zed.app` is a notarized Developer ID build (Team MQ55VZLNZQ, Zed
        // Industries) with bundle id dev.zed.Zed — verified 2026-06-06 to match the
        // install, so the swap passes the VendorInstaller gate. Zed has a robust
        // built-in updater, so this is a fallback for when that hasn't kept up, not a
        // replacement for it. arm64 only (a `Zed-x86_64.dmg` also ships).
        GitHubReleaseRule(
            bundleID: "dev.zed.Zed",
            owner: "zed-industries", repo: "zed",
            installAssetPattern: #"^Zed-aarch64\.dmg$"#,
            installerKind: .dmg),

        // Zed Preview — the Preview channel ships as prereleases (`vX.Y.Z-pre`).
        // MUST declare `channel: .preview`: the Preview install detects as
        // `.preview`, and the source's channel gate refuses any rule whose channel
        // doesn't match the install. Without this the rule defaults to `.stable`
        // and the gate skips it, leaving a real Preview install with no source
        // (regressed when the channel gate landed; caught by the live `--check`).
        //
        // Best-effort one-click, same as stable: the Preview prerelease ships its own
        // `Zed-aarch64.dmg` whose `Zed Preview.app` is the same Team MQ55VZLNZQ build,
        // bundle id dev.zed.Zed-Preview — verified 2026-06-06 to match the install.
        // The rule resolves the right tag (prerelease), so each channel gets its own
        // dmg/bundle id; the gate enforces the Team match. arm64 only.
        GitHubReleaseRule(
            bundleID: "dev.zed.Zed-Preview",
            owner: "zed-industries", repo: "zed",
            usePrereleases: true,
            versionPattern: #"v([0-9]+\.[0-9]+\.[0-9]+)-pre"#,
            installAssetPattern: #"^Zed-aarch64\.dmg$"#,
            installerKind: .dmg,
            channel: .preview),

        // Pearcleaner — tags have no `v` prefix. One-click installs the universal
        // `Pearcleaner.dmg`: verified 2026-06-06 the dmg's `Pearcleaner.app` is a
        // notarized Developer ID build (Team BK8443AXLU, Marius Lupascu) reporting
        // CFBundleShortVersionString 5.4.3 == tag, bundle id com.alienator88.Pearcleaner
        // matching the install — so the in-place swap passes the VendorInstaller gate.
        // The universal dmg avoids the arch-specific `-arm`/`-intel` zips. No self-
        // updater (a Sparkle-less menu utility), so a plain one-click, not best-effort.
        GitHubReleaseRule(
            bundleID: "com.alienator88.Pearcleaner",
            owner: "alienator88", repo: "Pearcleaner",
            installAssetPattern: #"^Pearcleaner\.dmg$"#,
            installerKind: .dmg),

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

        // Alcove — handled by `AlcoveUpdateSource` (licensed api.tryalcove.com), with
        // a public `update.tryalcove.com` VendorProbeRecipe as the no-credential
        // fallback. The `henrikruscon/alcove-releases` mirror this rule used to read
        // LAGS the real release (2026-06-14: stuck at 1.7.2 while the vendor served
        // 1.7.3) — but so does every public surface, including update.tryalcove.com
        // (2026-06-17: still 1.7.3 while the licensed channel already had 1.7.4). Only
        // the licensed channel is authoritative; see `AlcoveUpdateSource`.

        // Macs Fan Control — tags carry a `v` prefix (stripped by the pattern).
        // One-click installs `macsfancontrol.zip`, which wraps `Macs Fan Control.app`:
        // verified 2026-06-06 it's a notarized Developer ID build (Team ACC5R6RH47,
        // Ilya Parniuk) reporting version 1.5.21 == tag, bundle id
        // com.crystalidea.macsfancontrol matching the install → passes the gate. Two
        // other zips ship (`_legacy` for old macOS, the Windows `_setup.exe`); the
        // bare `macsfancontrol.zip` is the current-macOS app. Swapped in place like
        // the other zip recipes. No Sparkle, so a plain one-click.
        GitHubReleaseRule(
            bundleID: "com.crystalidea.macsfancontrol",
            owner: "crystalidea", repo: "macs-fan-control",
            installAssetPattern: #"^macsfancontrol\.zip$"#,
            installerKind: .zip),

        // Stats — macOS menu-bar system monitor. Tags carry a `v` prefix
        // (stripped by the default pattern). Stable channel, no prereleases.
        //
        // One-click: the single `Stats.dmg` asset was verified 2026-08-08 against
        // v3.0.10 — `Stats.app` at the dmg root (beside the usual /Applications
        // symlink), bundle id eu.exelban.Stats, notarized Developer ID build signed
        // by Team RP2S87B72W (Serhiy Mytrovtsiy), matching the installed copy, so
        // the swap passes the VendorInstaller gate. Its
        // `CFBundleShortVersionString` (3.0.10) equals the tag, so the probed
        // version is the marketing version we compare against — no build-number
        // trap. Stats has its own in-app updater but ships no Sparkle feed, so this
        // is a plain one-click.
        GitHubReleaseRule(
            bundleID: "eu.exelban.Stats",
            owner: "exelban", repo: "stats",
            installAssetPattern: #"^Stats\.dmg$"#,
            installerKind: .dmg),

        // DBeaver Community — tags are bare dotted versions (no `v` prefix), e.g.
        // `26.1.0`; the `dbeaver/dbeaver` repo tracks the Community version scheme,
        // so /releases/latest matches the installed CE version directly.
        //
        // One-click verified 2026-08-09 on 26.1.4: `dbeaver-ce-<ver>-macos-aarch64.dmg`
        // holds `DBeaver.app`, bundle id org.jkiss.dbeaver.core.product, Team
        // 42B6MDKMW8, spctl "Notarized Developer ID". The pattern pins `aarch64` so
        // the x86_64 asset published alongside it can never be picked on an Apple
        // Silicon Mac.
        GitHubReleaseRule(
            bundleID: "org.jkiss.dbeaver.core.product",
            owner: "dbeaver", repo: "dbeaver",
            installAssetPattern: #"^dbeaver-ce-[0-9.]+-macos-aarch64\.dmg$"#,
            installerKind: .dmg),

        // Beekeeper Studio (Community) — tags carry a `v` prefix (v5.8.1),
        // stripped by the default pattern. Betas ship as `vX.Y.Z-beta.N` flagged
        // prerelease, so usePrereleases=false / `/releases/latest` correctly skips
        // them.
        //
        // Best-effort one-click: the `Beekeeper-Studio-<ver>-arm64.dmg` asset wraps
        // `Beekeeper Studio.app` — verified 2026-06-06 a notarized Developer ID build
        // (Team 7KK583U8H2, Matthew Rathbone) reporting version 5.8.1 == tag, bundle
        // id io.beekeeperstudio.desktop. Electron app with its own updater, so a
        // fallback. The filename carries the version, so the pattern stays version-
        // agnostic; arm64 (the bare `…-<ver>.dmg` is NOT universal — checked with
        // `file` on 6.0.1, it is a single x86_64 slice — and a `-mac.zip` also ships,
        // so the arm64 anchor is what keeps an Intel build off an arm64 Mac). Not
        // installed on the author's machine — the VendorInstaller Team-gate enforces
        // the match against whatever is installed.
        GitHubReleaseRule(
            bundleID: "io.beekeeperstudio.desktop",
            owner: "beekeeper-studio", repo: "beekeeper-studio",
            installAssetPattern: #"^Beekeeper-Studio-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // Insomnia (stable) — Kong/insomnia is a monorepo whose Releases are tagged
        // per package (`core@X.Y.Z` is the Insomnia desktop app; `lib@…`/`inso@…`
        // are sibling packages). `/releases/latest` could resolve to a non-core
        // release, so scan the list (usePrereleases) and take the first tag the
        // pattern matches — lib@/inso@ yield no capture and are skipped.
        //
        // The `$` anchor is load-bearing: Kong publishes prerelease tags
        // (`core@13.0.0-beta.0`) BEFORE the matching stable, and a prerelease of a
        // *new* line sorts newest — first in the list. An unanchored
        // `core@(X.Y.Z)` captured `13.0.0` out of `core@13.0.0-beta.0` and pushed a
        // beta onto stable users as "13.0.0" (and the `-beta.0` dmg name then failed
        // `installAssetPattern`, so the row showed "Open", not even "Update"). With
        // `$`, only suffix-free stable tags (`core@12.6.0`) match; the beta channel,
        // if/when added, is a separate `channel: .beta` rule. (The earlier comment's
        // "betas sort after the stable of the same line" assumption was simply wrong
        // when a brand-new line debuts as a prerelease.)
        //
        // Best-effort one-click: the `Insomnia.Core-<ver>.dmg` (universal) wraps
        // `Insomnia.app` — verified 2026-06-06 a notarized Developer ID build (Team
        // FX44YY62GV, Kong Inc.) reporting version 12.6.0 == tag, bundle id
        // com.insomnia.app. The sibling `inso-macos-*` assets are the CLI, not the
        // desktop app — the `Insomnia.Core-` anchor excludes them. Electron app with
        // its own updater, so a fallback; not installed locally, so the Team-gate
        // enforces the match at install time.
        GitHubReleaseRule(
            bundleID: "com.insomnia.app",
            owner: "Kong", repo: "insomnia",
            usePrereleases: true,
            versionPattern: #"core@([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^Insomnia\.Core-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // Zen Browser — stable tags carry a trailing letter suffix (e.g.
        // "1.20.1b"). That suffix is PART of the CFBundleShortVersionString, so
        // the pattern MUST keep the trailing [a-z] — stripping it would read as a
        // perpetual update/downgrade. Zen also publishes a rolling "twilight"
        // prerelease; /releases/latest (usePrereleases: false) excludes it.
        //
        // Best-effort one-click: the `zen.macos-universal.dmg` wraps `Zen.app` —
        // verified 2026-06-06 a notarized Developer ID build (Team 9V5K9TP787, Mauro
        // Baladés) reporting version 1.20.2b == tag (the trailing `b` kept, matching
        // CFBundleShortVersionString), bundle id app.zen-browser.zen. A Firefox fork
        // with its own updater, so a fallback; not installed locally, so the Team-gate
        // enforces the match at install time.
        GitHubReleaseRule(
            bundleID: "app.zen-browser.zen",
            owner: "zen-browser", repo: "desktop",
            usePrereleases: false,
            versionPattern: #"([0-9]+\.[0-9]+(?:\.[0-9]+)?[a-z]?)"#,
            installAssetPattern: #"^zen\.macos-universal\.dmg$"#,
            installerKind: .dmg),

        // GitHub Desktop — TWO channels share ONE bundle id (com.github.GitHubClient)
        // AND one app name ("GitHub Desktop"): Stable ships `release-X.Y.Z` tags,
        // Beta ships `release-X.Y.Z-betaN` prereleases, interleaved AHEAD of
        // production in the list (`release-3.5.12-beta2` sits above `release-3.5.12`).
        // Unlike Zed (separate bundle ids per channel), the ONLY channel signal is
        // the installed version string's `-betaN` suffix — `ReleaseChannel.detect`'s
        // step-5 `-beta[0-9]+` shape flips a `3.5.12-beta2` install to `.beta`, and
        // the channel gate then serves it the beta rule below, never this stable one.
        // Both verified end-to-end 2026-06-06: stable `GitHub.Desktop-arm64.zip`
        // (3.5.12) and beta (3.5.12-beta2) are the same notarized Developer ID build
        // (Team VEKTX9H2N7, GitHub), same bundle id; the beta is the copy installed
        // on this machine. Squirrel self-updater, so one-click is a best-effort
        // fallback. arm64 only (a `-x64.zip` also ships), swapped in place.
        //
        // Stable: `/releases/latest` resolves to the production tag (betas are
        // prerelease=true), so usePrereleases=false; the `$`-anchored pattern
        // captures only the bare X.Y.Z and refuses any `-beta`/`-test` suffix.
        GitHubReleaseRule(
            bundleID: "com.github.GitHubClient",
            owner: "desktop", repo: "desktop",
            usePrereleases: false,
            versionPattern: #"release-([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^GitHub\.Desktop-arm64\.zip$"#,
            installerKind: .zip),

        // GitHub Desktop Beta — same repo/asset, `channel: .beta` so the gate serves
        // it only to a `-betaN`-detected install. usePrereleases scans the list and
        // takes the first `release-X.Y.Z-betaN` tag (newest beta, since GitHub
        // returns newest-first); the pattern KEEPS the `-betaN` so the captured
        // `3.5.12-beta2` equals the installed CFBundleShortVersionString (no phantom
        // update/downgrade against the stable 3.5.12). Same `GitHub.Desktop-arm64.zip`
        // one-click as stable.
        GitHubReleaseRule(
            bundleID: "com.github.GitHubClient",
            owner: "desktop", repo: "desktop",
            usePrereleases: true,
            versionPattern: #"release-([0-9]+\.[0-9]+\.[0-9]+-beta[0-9]+)$"#,
            installAssetPattern: #"^GitHub\.Desktop-arm64\.zip$"#,
            installerKind: .zip,
            channel: .beta),

        // Ollama — Electron app distributed via an `auto_updates` Homebrew cask,
        // which falls through `HomebrewCaskSource` and leaves no `SUFeedURL`, so
        // the installed copy drifts (0.24.0 while GitHub ships v0.30.6) with no
        // detection source — only a changelog recipe. The macOS app is the same
        // GitHub `/releases/latest`: ollama.com/install.sh and ollama.com/download
        // both 307→ github releases/latest/download (`Ollama-darwin.zip` / the
        // `Ollama.dmg` asset). Tags carry a `v` prefix (`v0.30.6`), stripped by the
        // default pattern → `0.30.6`. Verified end-to-end 2026-06-06: the .app inside
        // the latest zip self-reports CFBundleShortVersionString 0.30.6 (homogeneous,
        // no ghost update). Stable channel, no prereleases (`/releases/latest`).
        //
        // Best-effort one-click: the `Ollama-darwin.zip` asset IS a notarized
        // Developer ID build, Team 3MU9H2V9Y9 (Infra Technologies) matching the
        // install, so the in-place swap passes the VendorInstaller Team-ID gate.
        // Ollama ships its own updater, but it drifts in practice (seen stuck on
        // 0.24.0 while GitHub was on v0.30.6), so rather than refuse to act we offer
        // the swap as a fallback when its updater hasn't kept up. The zip wraps
        // `Ollama.app`, swapped in place like the other zip recipes. Ollama runs a
        // background `ollama serve`, so after the swap the live process is still the
        // old build and the row lands in `needsRestart` → the standard Restart action
        // quits every `com.electron.ollama` instance and reopens it on the new build.
        GitHubReleaseRule(
            bundleID: "com.electron.ollama",
            owner: "ollama", repo: "ollama",
            installAssetPattern: #"^Ollama-darwin\.zip$"#,
            installerKind: .zip),

        // MARK: - 2026-08-16 coverage batch
        //
        // Candidates came from the Homebrew 365-day cask install ranking crossed
        // against this registry, then triaged by DOWNLOADING each real artifact,
        // mounting it read-only and reading its Info.plist + `codesign`/`spctl`.
        // (The sweep's raw evidence lives outside the repo — `docs/` is gitignored —
        // so each rule below carries its own findings inline instead of citing it.)
        // Every rule below therefore states a bundle id, Team ID and notarization
        // status read off the very asset its `installAssetPattern` selects — not off
        // the vendor's download page. Apps that turned out to ship a usable
        // `SUFeedURL` are deliberately absent: `SparkleAppcastSource` already covers
        // them with no rule at all.
        //
        // One shared caveat, repeated on the two rules it reaches. When an app's
        // `CFBundleShortVersionString` has no patch component AND its
        // `CFBundleVersion` is a small dotless counter, `UpdateChecker.evaluate`'s
        // "the vendor folded the build into the version" fallback rebuilds the
        // installed side as short + "." + build — "3.5" + "1" = "3.5.1" — and can
        // read a genuine x.y.1 release as already installed. Of the artifacts
        // inspected for this batch only Anki and noTunes have that shape. The others
        // are safe for one of two DIFFERENT reasons, worth keeping straight: a dotted
        // `CFBundleVersion` skips the fallback outright (that is the only thing the
        // guard tests), while a three-component short version still RUNS it — the
        // rebuilt string is simply four components, which is very unlikely to match
        // a real release. The second group is practically safe, not structurally
        // immune: four-component versions do exist in this batch (OpenLens reports
        // 6.5.2-366), and there it is the dotted build that keeps it off this path.

        // CC Switch — Claude Code / Codex profile switcher, no Sparkle, ships one
        // macOS dmg per release (`CC-Switch-v<ver>-macOS.dmg`, beside a .zip and a
        // .tar.gz of the same build). Tags are `vX.Y.Z` → default pattern. One-click:
        // that dmg's `CC Switch.app` is com.ccswitch.desktop, Team R8UR22V2F9,
        // notarized — same identity as the install, so the swap passes the gate.
        GitHubReleaseRule(
            bundleID: "com.ccswitch.desktop",
            owner: "farion1231", repo: "cc-switch",
            installAssetPattern: #"^CC-Switch-v[0-9.]+-macOS\.dmg$"#,
            installerKind: .dmg),

        // Bruno — API client, Electron, no Sparkle. Each release ships BOTH
        // `bruno_<ver>_arm64_mac.dmg` and `bruno_<ver>_x64_mac.dmg`, so the pattern
        // pins arm64 rather than relying on ordering. One-click verified: the arm64
        // dmg holds com.usebruno.app, Team W7LPPWA48L, notarized.
        GitHubReleaseRule(
            bundleID: "com.usebruno.app",
            owner: "usebruno", repo: "bruno",
            installAssetPattern: #"^bruno_[0-9.]+_arm64_mac\.dmg$"#,
            installerKind: .dmg),

        // LocalSend — detection only, on purpose. The newest release (v1.18.1)
        // carries ONLY Android artifacts (four .apk files); the macOS dmg was last
        // attached to v1.18.0, so there is no dmg on the tag we read and no install
        // URL to resolve. Detection is still right (tag → 1.18.1 vs the installed
        // 1.18.0), so we surface the version and link out. Revisit the one-click when
        // upstream attaches a macOS dmg to the tag it marks latest — not merely when
        // it attaches assets. (The v1.18.0 dmg is org.localsend.localsendApp,
        // Team 3W7H4PYMCV, notarized — the gate would pass, the URL is what's missing.)
        GitHubReleaseRule(
            bundleID: "org.localsend.localsendApp",
            owner: "localsend", repo: "localsend"),

        // qBittorrent — DETECTION ONLY, and this is upstream's own signature, not
        // a property of where we read from: the macOS dmg on GitHub is the SAME
        // artifact SourceForge serves, signed `Authority=qbittorrent macos` with
        // `TeamIdentifier=not set` (a self-made certificate, not a Developer ID),
        // and `spctl -a -t install` rejects it. Verified 2026-08-16 by downloading
        // `qbittorrent-5.2.3.dmg` (48,317,381 B) straight from this repo's release
        // and mounting it — org.qbittorrent.qBittorrent, 5.2.3, universal, and
        // rejected. No `installAssetPattern`, so the row shows the version and
        // opens qbittorrent.org.
        //
        // Read here rather than from SourceForge (where this app lived until
        // 2026-08-16) because the tag IS the release — SourceForge's
        // `best_release.json` answers with a Windows `.exe` at top level and hides
        // the dmg under `platform_releases.mac`, and its edge WAF needs the UA
        // override the remaining SourceForge recipes carry.
        //
        // Tag shape is `release-5.2.3`, so the pattern is anchored rather than
        // left to the default `v?(…)`: the repo also carries old `v3.3.x` tags,
        // and an unanchored match on a stray digit is exactly how a version
        // silently becomes wrong.
        GitHubReleaseRule(
            bundleID: "org.qbittorrent.qBittorrent",
            owner: "qbittorrent", repo: "qBittorrent",
            versionPattern: #"^release-([0-9]+(?:\.[0-9]+)+)$"#),

        // Hidden Bar — the app DOES carry a Sparkle feed
        // (`SUFeedURL = api.amore.computer/v1/apps/com.dwarvesv.minimalbar/appcast.xml`),
        // which is why it looks covered from the outside and isn't: fetched
        // 2026-08-16 the feed answers 200 with a well-formed `<channel>` — title,
        // link, description — and **no `<item>` at all**. `SparkleAppcastSource`
        // finds nothing, returns nil, and the row falls through to here as
        // "unknown" with nothing failing anywhere. An empty feed is exactly the
        // shape a broken recipe can't be told from a healthy one, so the version
        // comes from the tags instead, which are real (`v1.10`).
        //
        // One-click verified 2026-08-16 by unpacking `Hidden-Bar-v1.10-macos.zip`:
        // `Hidden Bar.app`, com.dwarvesv.minimalbar, 1.10, universal, Team
        // W777S7V8TN (Dwarves Foundation Company Limited), notarized Developer ID.
        GitHubReleaseRule(
            bundleID: "com.dwarvesv.minimalbar",
            owner: "dwarvesf", repo: "hidden",
            installAssetPattern: #"^Hidden-Bar-v[0-9.]+-macos\.zip$"#,
            installerKind: .zip),

        // XQuartz — ships as a pkg, so this takes the system-installer route the
        // Office/AweSun packages use (`UpdatePolicy.requiresInstaller` already
        // covers `"GitHub"` + `.pkg`): we download the official package and hand it
        // to macOS, which prompts for the administrator password itself. Nothing
        // here swaps a bundle — X11 installs far more than `XQuartz.app`
        // (`/opt/X11`, launchd jobs), and an in-place app swap would leave all of
        // it stale.
        //
        // The installed app lives in `/Applications/Utilities`, which the scanner
        // covers. Verified 2026-08-16 against the real 2.8.6 pkg (122,035,963 B):
        // `pkgutil --check-signature` reports "Developer ID Installer: Apple Inc. -
        // XQuartz (NA574AWV7E)", notarized and timestamped, and its `Distribution`
        // declares `org.xquartz.X11` at version 2.8.6 — the same id the installed
        // bundle reports.
        //
        // Tags are `XQuartz-2.8.6`; the release also carries `.dSYMS.tar.bz2` and
        // `.sha256sum`/`.sha512sum` siblings, so the asset pattern is anchored to
        // the exact pkg name rather than "the first thing that looks like a build".
        GitHubReleaseRule(
            bundleID: "org.xquartz.X11",
            owner: "XQuartz", repo: "XQuartz",
            versionPattern: #"^XQuartz-([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^XQuartz-[0-9.]+\.pkg$"#,
            installerKind: .pkg),

        // UTM — virtualiser. The repo publishes v5.x as PRERELEASES while stable
        // sits at v4.7.5, so `usePrereleases` stays false: `/releases/latest` is
        // exactly the stable train, and a v5 prerelease can never be pushed at a
        // stable install. The asset name is constant (`UTM.dmg`, universal).
        // One-click: com.utmapp.UTM, Team WDNLXAD4W8, notarized.
        GitHubReleaseRule(
            bundleID: "com.utmapp.UTM",
            owner: "utmapp", repo: "UTM",
            installAssetPattern: #"^UTM\.dmg$"#,
            installerKind: .dmg),

        // kitty — terminal. The repo carries a rolling `nightly` prerelease tag, so
        // again `/releases/latest` (not the list) is what keeps a stable install on
        // stable. One dmg per release, `kitty-<ver>.dmg`, universal.
        // One-click: net.kovidgoyal.kitty, Team NTY7FVCEKP, notarized.
        GitHubReleaseRule(
            bundleID: "net.kovidgoyal.kitty",
            owner: "kovidgoyal", repo: "kitty",
            installAssetPattern: #"^kitty-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // DB Browser for SQLite — the repo also publishes rolling `nightly` and
        // `continuous` prereleases, both excluded by `/releases/latest`. The release
        // carries Windows/Linux artifacts too, so the pattern anchors the single
        // macOS dmg and, importantly, the `SQLite` product: a `…for.SQLCipher…dmg`
        // (a different app) ships from the same builds.
        // One-click: net.sourceforge.sqlitebrowser, Team C34AV33YLK, notarized.
        GitHubReleaseRule(
            bundleID: "net.sourceforge.sqlitebrowser",
            owner: "sqlitebrowser", repo: "sqlitebrowser",
            installAssetPattern: #"^DB\.Browser\.for\.SQLite-v[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // draw.io desktop — each release ships arm64/x64/universal dmgs, arm64 and
        // x64 zips and a Windows zip; the pattern pins the arm64 dmg (the universal
        // one is 100 MB larger for no benefit here). One-click: com.jgraph.drawio.desktop,
        // Team UZEUFB4N53, notarized.
        GitHubReleaseRule(
            bundleID: "com.jgraph.drawio.desktop",
            owner: "jgraph", repo: "drawio-desktop",
            installAssetPattern: #"^draw\.io-arm64-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // Podman Desktop — the release also carries `podman-desktop-airgap-<ver>-
        // arm64.dmg`, a 1.1 GB bundle-everything build. The `^podman-desktop-<ver>-`
        // anchor keeps the airgap variant out; without it a substring match would
        // hand the user a gigabyte download for the same app.
        // One-click: io.podmandesktop.PodmanDesktop, Team HYSCB8KRL2, notarized.
        GitHubReleaseRule(
            bundleID: "io.podmandesktop.PodmanDesktop",
            owner: "containers", repo: "podman-desktop",
            installAssetPattern: #"^podman-desktop-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // Bitwarden — the ONLY rule here that can't read `/releases/latest`: the
        // monorepo tags every client, and the newest release is usually `web-…` or
        // `cli-…`, not the desktop app (on 2026-08-16 `/releases/latest` was
        // `web-v2026.7.1` while the desktop app sat at `desktop-v2026.7.0`). Reading
        // the list and taking the first tag matching `desktop-v` is what keeps the
        // desktop version from tracking the web client's. The `$` anchor is
        // defensive rather than observed: every `desktop-v` tag in the newest 100
        // releases is bare and non-prerelease, and the anchor keeps a future
        // suffixed one (a release candidate, say) from reading as stable.
        //
        // Depends on a window the rule doesn't control: the list request is one page
        // (`per_page=20`, set by the source above, not by the rule). Measured over
        // the newest 100
        // releases, consecutive `desktop-v` tags are at most 7 apart, so the desktop
        // tag sits well inside that page today — but a long burst of web/cli/browser
        // releases would push it off the page, and the rule would then resolve
        // nothing, which surfaces as the row going quiet rather than as an error.
        //
        // One-click: the universal dmg is com.bitwarden.desktop, Team LTZ2PFU5D6,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.bitwarden.desktop",
            owner: "bitwarden", repo: "clients",
            usePrereleases: true,
            versionPattern: #"desktop-v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Bitwarden-[0-9.]+-universal\.dmg$"#,
            installerKind: .dmg),

        // VSCodium — VS Code without the Microsoft build. Tags are bare
        // `1.126.04524` (the trailing group is VSCodium's own build stamp and IS
        // part of the installed CFBundleShortVersionString, so the default pattern's
        // multi-dot capture keeps it). The release carries every platform plus a
        // `vscodium-cli-darwin-arm64-…tar.gz`; the pattern picks the app zip.
        // One-click: com.vscodium, Team VC39D2VNQ7, notarized.
        GitHubReleaseRule(
            bundleID: "com.vscodium",
            owner: "VSCodium", repo: "vscodium",
            installAssetPattern: #"^VSCodium-darwin-arm64-[0-9.]+\.zip$"#,
            installerKind: .zip),

        // balenaEtcher — an arm64 and an x64 dmg ship together (plus darwin zips of
        // the same builds), so the pattern pins the arm64 dmg.
        // One-click: io.balena.etcher, Team 66H43P8FRG, notarized.
        GitHubReleaseRule(
            bundleID: "io.balena.etcher",
            owner: "balena-io", repo: "etcher",
            installAssetPattern: #"^balenaEtcher-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // Caffeine — one constant `Caffeine.dmg` per release, tags are bare `1.1.4`.
        // One-click: com.intelliscapesolutions.caffeine, Team YD6LEYT6WZ, notarized.
        GitHubReleaseRule(
            bundleID: "com.intelliscapesolutions.caffeine",
            owner: "IntelliScape", repo: "caffeine",
            installAssetPattern: #"^Caffeine\.dmg$"#,
            installerKind: .dmg),

        // Godot — tags are `4.7.1-stable` (and `4.7-stable` for a .0 release), which
        // the default pattern reduces to what the app reports. The release is a wall
        // of platform artifacts; the pattern must exclude `…_mono_macos.universal.zip`,
        // the .NET-enabled build, which is a DIFFERENT distribution of the same
        // bundle id — installing it over a plain install would silently switch the
        // user's editor flavour. One-click: org.godotengine.godot, Team 6K46PWY5DM,
        // notarized.
        GitHubReleaseRule(
            bundleID: "org.godotengine.godot",
            owner: "godotengine", repo: "godot",
            installAssetPattern: #"^Godot_v[0-9.]+-stable_macos\.universal\.zip$"#,
            installerKind: .zip),

        // KeePassXC — arm64 and x86_64 dmgs ship together; pin arm64. Patch respins
        // append a revision to the FILENAME but not the tag (`KeePassXC-2.7.11-1-
        // arm64.dmg` under tag `2.7.11`), so the version part of the pattern stays
        // loose while the arch stays anchored.
        //
        // Caveat, stated plainly because the tests cannot close it: a respun release
        // keeps BOTH files (tag 2.7.11 ships `-2.7.11-1-arm64.dmg` AND
        // `-2.7.11-arm64.dmg`), so the pattern matches more than one asset and
        // `installableAsset` — first arch-native match wins — is settled by whatever
        // order GitHub happens to return. That order is undocumented (the Releases
        // API states no sort for assets); what this repo's listings actually show,
        // observed 2026-08-16, is case-insensitive by filename — `keepassxc-2.7.12-
        // src.tar.xz` comes back ahead of `KeePassXC-2.7.12-Win64…`, which plain
        // byte order could never produce. Under both that order and byte order the
        // digit sorts ahead of a letter, so `-1-` comes before the plain name and the
        // respin is what installs — which is what we want, but by observation, not by
        // contract. The same ordering means a SECOND respin would LOSE: `-1-` also
        // sorts before `-2-`, so `-2` would be passed over.
        // `keepassxcRespinIsTheAssetSelected` pins the selection semantics on the
        // real 2.7.11 asset list and records the `-2` case as a known issue, so the
        // gap stays visible instead of looking closed. The blast radius is small and
        // bounded: every candidate is the same version, same Team G2S7P7J672 and
        // notarized, so the worst case is a superseded packaging of the version the
        // user was going to get anyway — never a cross-train swap.
        // One-click: org.keepassxc.keepassxc, Team G2S7P7J672, notarized.
        GitHubReleaseRule(
            bundleID: "org.keepassxc.keepassxc",
            owner: "keepassxreboot", repo: "keepassxc",
            installAssetPattern: #"^KeePassXC-[0-9.\-]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // Sequel Ace — tags are `production/5.4.0-20109` (marketing version plus the
        // build number); the default pattern's first match is the marketing version,
        // which is what the app reports. `beta/…` tags and some respun `production/…`
        // tags are published as prereleases, so `/releases/latest` is what keeps a
        // stable install on the production train.
        // One-click: com.sequel-ace.sequel-ace, Team NKQ4HJ66PX, notarized.
        GitHubReleaseRule(
            bundleID: "com.sequel-ace.sequel-ace",
            owner: "Sequel-Ace", repo: "Sequel-Ace",
            installAssetPattern: #"^Sequel-Ace-[0-9.]+\.zip$"#,
            installerKind: .zip),

        // SwiftBar — the newest release is often a beta prerelease (`v2.1.2-beta-3`),
        // so `/releases/latest` is what pins the rule to stable. The asset carries
        // the build number (`SwiftBar.v2.1.1.b597.zip`) that the tag doesn't, so the
        // pattern matches the version-plus-build shape rather than the tag.
        // One-click: com.ameba.SwiftBar, Team X93LWC49WV, notarized.
        GitHubReleaseRule(
            bundleID: "com.ameba.SwiftBar",
            owner: "swiftbar", repo: "SwiftBar",
            installAssetPattern: #"^SwiftBar\.v[0-9.]+\.b[0-9]+\.zip$"#,
            installerKind: .zip),

        // OpenMTP — Android file transfer. arm64/x64 dmgs and zips of the same build
        // ship together; pin the arm64 dmg.
        // One-click: io.ganeshrvel.openmtp, Team 6UR4H85SA2, notarized.
        GitHubReleaseRule(
            bundleID: "io.ganeshrvel.openmtp",
            owner: "ganeshrvel", repo: "openmtp",
            installAssetPattern: #"^openmtp-[0-9.]+-mac-arm64\.dmg$"#,
            installerKind: .dmg),

        // Headlamp — the repo interleaves `headlamp-helm-<ver>` and
        // `headlamp-plugin-<ver>` tags with the app's own `v<ver>`, and those chart
        // releases can be published after the app's, which would make GitHub's
        // "latest" a chart. Reading the LIST and anchoring `^v…$` takes the newest
        // APP tag instead. (No prereleases in this repo, so the list can't hand back
        // a preview build.) One-click: com.microsoft.Headlamp, Team 5N2JF58U87,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.microsoft.Headlamp",
            owner: "headlamp-k8s", repo: "headlamp",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Headlamp-[0-9.]+-mac-arm64\.dmg$"#,
            installerKind: .dmg),

        // LuLu — Objective-See's firewall. One universal dmg per release,
        // `LuLu_<ver>.dmg`. One-click: com.objective-see.lulu.app, Team VBG97UB4TA,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.objective-see.lulu.app",
            owner: "objective-see", repo: "LuLu",
            installAssetPattern: #"^LuLu_[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // noTunes — tags are `vX.Y` (two components), which the default pattern
        // handles. One-click: digital.twisted.noTunes, Team JP6WW46Y42, notarized.
        //
        // Carries the same latent shape as Anki (see the batch header): the app
        // reports `CFBundleShortVersionString` 3.5 with `CFBundleVersion` 1, so if
        // upstream ever tags a three-component `v3.5.1`, `evaluate`'s folded-build
        // fallback would rebuild the installed side as "3.5.1" and call it current.
        // Not reachable today — every tag this repo has published (v1.0 through
        // v3.5) is two-component — but it is the same trap, not a different one.
        GitHubReleaseRule(
            bundleID: "digital.twisted.noTunes",
            owner: "tombonez", repo: "noTunes",
            installAssetPattern: #"^noTunes-[0-9.]+\.zip$"#,
            installerKind: .zip),

        // MarkEdit — takes the UNIVERSAL dmg (`MarkEdit-<ver>.dmg`), not the
        // `-apple-silicon` one beside it. Verified with `file`: the plain dmg is a
        // universal binary (x86_64 + arm64) while `-apple-silicon` is a single arm64
        // slice — and `apple-silicon` was not a token the asset picker recognised, so
        // pinning it read as arch-neutral and would have offered an arm64-only build
        // to an Intel Mac. (The token is recognised now, but the universal dmg is
        // still the better pin: one artifact that runs everywhere, no arch branch.)
        // The `[0-9.]+\.dmg$` anchor also keeps `-apple-silicon.dmg` out, and the
        // `UpdateArchive*.zip` payloads are for MarkEdit's own updater, not for us.
        // One-click: app.cyan.markedit, Team TCKG8FBVG6, notarized — verified on the
        // universal dmg.
        GitHubReleaseRule(
            bundleID: "app.cyan.markedit",
            owner: "MarkEdit-app", repo: "MarkEdit",
            installAssetPattern: #"^MarkEdit-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // Clash Verge Rev — aarch64 and x64 dmgs ship together; pin aarch64.
        // One-click: io.github.clash-verge-rev.clash-verge-rev, Team JPH3Z7PPBB,
        // notarized.
        GitHubReleaseRule(
            bundleID: "io.github.clash-verge-rev.clash-verge-rev",
            owner: "clash-verge-rev", repo: "clash-verge-rev",
            installAssetPattern: #"^Clash\.Verge_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),

        // Freelens — the OpenLens fork. `-macos-amd64` and `-macos-arm64` dmgs ship
        // together; pin arm64. One-click: app.freelens.Freelens, Team TFR6NT55MB,
        // notarized.
        GitHubReleaseRule(
            bundleID: "app.freelens.Freelens",
            owner: "freelensapp", repo: "freelens",
            installAssetPattern: #"^Freelens-[0-9.]+-macos-arm64\.dmg$"#,
            installerKind: .dmg),

        // KeepingYouAwake — tags are bare `1.6.8`, one zip per release.
        // One-click: info.marcel-dierkes.KeepingYouAwake, Team 5KESHV9W85, notarized.
        GitHubReleaseRule(
            bundleID: "info.marcel-dierkes.KeepingYouAwake",
            owner: "newmarcel", repo: "KeepingYouAwake",
            installAssetPattern: #"^KeepingYouAwake-[0-9.]+\.zip$"#,
            installerKind: .zip),

        // Espanso — text expander. The macOS asset name carries NO version
        // (`Espanso-Mac-Universal.dmg`), so the pattern is a literal. Older releases
        // shipped the same name as a .zip; if upstream flips back, the install URL
        // simply resolves nothing (a warning) instead of grabbing a wrong artifact.
        // One-click: com.federicoterzi.espanso, Team 6424323YUH, notarized.
        GitHubReleaseRule(
            bundleID: "com.federicoterzi.espanso",
            owner: "espanso", repo: "espanso",
            installAssetPattern: #"^Espanso-Mac-Universal\.dmg$"#,
            installerKind: .dmg),

        // Tabby — terminal. macOS arm64/x86_64 dmgs and zips plus "portable" zips
        // ship together; pin the arm64 dmg.
        // One-click: org.tabby, Team V4JSMC46SY, notarized.
        GitHubReleaseRule(
            bundleID: "org.tabby",
            owner: "Eugeny", repo: "tabby",
            installAssetPattern: #"^tabby-[0-9.]+-macos-arm64\.dmg$"#,
            installerKind: .dmg),

        // Moonlight — game streaming client. The release also carries
        // `Moonlight-SteamLink-<ver>.zip` and `MoonlightPortable-*` builds, which are
        // different targets; the `^Moonlight-<ver>.dmg$` anchor takes only the Mac app.
        // One-click: com.moonlight-stream.Moonlight, Team 45U78722YL, notarized.
        GitHubReleaseRule(
            bundleID: "com.moonlight-stream.Moonlight",
            owner: "moonlight-stream", repo: "moonlight-qt",
            installAssetPattern: #"^Moonlight-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // Handy — aarch64 and x64 dmgs ship together; pin aarch64.
        // One-click: com.pais.handy, Team UWFLB4GC25, notarized.
        GitHubReleaseRule(
            bundleID: "com.pais.handy",
            owner: "cjpais", repo: "Handy",
            installAssetPattern: #"^Handy_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),

        // battery — CLI-plus-menu-bar battery limiter. Recent releases ship an
        // arm64 dmg and zip; pin the dmg.
        // One-click: co.palokaj.battery, Team CAWM399GFD, notarized.
        GitHubReleaseRule(
            bundleID: "co.palokaj.battery",
            owner: "actuallymentor", repo: "battery",
            installAssetPattern: #"^battery-[0-9.]+-mac-arm64\.dmg$"#,
            installerKind: .dmg),

        // Another Redis Desktop Manager — mac arm64/x64 dmgs plus Windows/Linux
        // artifacts; pin the mac arm64 dmg.
        // One-click: me.qii404.another-redis-desktop-manager, Team 68JN8DV835,
        // notarized.
        GitHubReleaseRule(
            bundleID: "me.qii404.another-redis-desktop-manager",
            owner: "qishibo", repo: "AnotherRedisDesktopManager",
            installAssetPattern: #"^Another-Redis-Desktop-Manager-mac-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // Goose (block/goose) — the `goose-*-apple-darwin.tar.gz` assets beside the
        // app are the CLI and `goose-source-*.zip` is a source drop, so the app is
        // anchored by literal name. BOTH macOS builds are matched: `Goose.zip` is
        // arm64-ONLY (checked with `file`: a single arm64 slice, not a universal
        // binary) and `Goose_intel_mac.zip` is the Intel build. Matching only
        // `Goose.zip` would look arch-neutral to `installableAsset` — the name
        // carries no arch token — so an Intel Mac would be handed an arm64 app that
        // cannot launch, and the install gate would not catch it (it checks
        // signature, Team and bundle id, never architecture). With both matched the
        // arch preference resolves it: `intel` is an x86_64 token, so an Intel Mac
        // takes `Goose_intel_mac.zip` while Apple silicon falls through to the
        // token-free `Goose.zip`.
        // One-click: com.electron.goose, Team 5N2JF58U87, notarized — verified on
        // BOTH assets.
        GitHubReleaseRule(
            bundleID: "com.electron.goose",
            owner: "block", repo: "goose",
            installAssetPattern: #"^Goose(_intel_mac)?\.zip$"#,
            installerKind: .zip),

        // PureMac — a dmg and a zip of the same build ship together; take the dmg.
        // One-click: com.puremac.app, Team H3WXHVTP97, notarized.
        GitHubReleaseRule(
            bundleID: "com.puremac.app",
            owner: "momenbasel", repo: "PureMac",
            installAssetPattern: #"^PureMac-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // MiddleClick — the asset name carries no version (`MiddleClick.zip`).
        // One-click: art.ginzburg.MiddleClick, Team R2294BC6J8, notarized.
        GitHubReleaseRule(
            bundleID: "art.ginzburg.MiddleClick",
            owner: "artginzburg", repo: "MiddleClick",
            installAssetPattern: #"^MiddleClick\.zip$"#,
            installerKind: .zip),

        // UnnaturalScrollWheels — bare tags, one dmg per release.
        // One-click: com.theron.UnnaturalScrollWheels, Team VH8UL6UKQL, notarized.
        GitHubReleaseRule(
            bundleID: "com.theron.UnnaturalScrollWheels",
            owner: "ther0n", repo: "UnnaturalScrollWheels",
            installAssetPattern: #"^UnnaturalScrollWheels-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // Anki — tags are date-shaped with a zero-padded month (`26.08.1`) while the
        // app reports `26.8.1`. That is NOT a mismatch for us: `VersionComparator`
        // compares digit runs numerically, so 08 == 8 and the two read as the same
        // version — no phantom update.
        //
        // Apple-silicon and Intel dmgs ship together, and BOTH are in the pattern for
        // the same reason as Goose above: `-mac-apple` carries no token that
        // `installableAsset` recognises as an architecture, so pinning it alone would
        // read as arch-neutral and hand an Intel Mac the Apple-silicon build. With
        // both matched, `intel` selects the x86_64 dmg on an Intel Mac and the
        // token-free `-mac-apple` wins on Apple silicon. Team ZL66D3NMZM and
        // notarization verified on BOTH dmgs.
        //
        // KNOWN GAP (verified on this machine 2026-08-16, not a rule bug): Anki
        // stamps `CFBundleVersion` as a literal "1" for every build. When the
        // installed short version has no patch component (26.08 → app reports
        // "26.8"), `UpdateChecker.evaluate`'s "vendor folded the build into the
        // version" fallback rebuilds it as "26.8" + "1" = "26.8.1" and concludes the
        // app is already current — hiding exactly the x.y → x.y.1 patch. Every other
        // step (26.8.1 → 26.9) reports normally. Fixing it means tightening that
        // fallback (it exists for Oray-style 5-digit builds), which is a change to
        // shared logic, not to this rule.
        // One-click: net.ankiweb.anki, Team ZL66D3NMZM, notarized.
        GitHubReleaseRule(
            bundleID: "net.ankiweb.anki",
            owner: "ankitects", repo: "anki",
            installAssetPattern: #"^anki-[0-9.]+-mac-(apple|intel)\.dmg$"#,
            installerKind: .dmg),

        // Raspberry Pi Imager — the ONE app here whose own
        // `CFBundleShortVersionString` keeps the `v` (`v2.0.11`), so the pattern
        // captures the `v` too; stripping it (the default) would leave every
        // comparison against a string the app never reports. `-rc` tags are
        // published as prereleases, and `/releases/latest` skips them.
        // One-click: com.raspberrypi.rpi-imager, Team 8RDZTRXE62, notarized.
        GitHubReleaseRule(
            bundleID: "com.raspberrypi.rpi-imager",
            owner: "raspberrypi", repo: "rpi-imager",
            versionPattern: #"^(v[0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^rpi-imager-v[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // OpenLens — the build number after the dash IS part of the installed
        // version (`6.5.2-366`), so the pattern captures it; the default would stop
        // at 6.5.2 and read every release as a downgrade. arm64 dmg out of the four
        // macOS artifacts. One-click: com.electron.open-lens, Team HGC72W36QJ,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.electron.open-lens",
            owner: "MuhammedKalkan", repo: "OpenLens",
            versionPattern: #"v([0-9]+(?:\.[0-9]+)+-[0-9]+)"#,
            installAssetPattern: #"^OpenLens-[0-9.\-]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // MARK: Detection-only — the published build can't pass the install gate
        //
        // Each of these resolves a correct version, but its macOS artifact is NOT a
        // notarized Developer ID build (ad-hoc signed or unsigned), so
        // `VendorInstaller` would refuse the swap anyway. Leaving
        // `installAssetPattern` nil states that up front: we surface the version and
        // send the user to the releases page. Verified 2026-08-16 by running
        // `codesign`/`spctl` on the downloaded artifact.

        // Alacritty — ad-hoc signed, no Team ID.
        GitHubReleaseRule(
            bundleID: "org.alacritty",
            owner: "alacritty", repo: "alacritty"),

        // Flameshot — ad-hoc signed, no Team ID.
        GitHubReleaseRule(
            bundleID: "org.flameshot.Flameshot",
            owner: "flameshot-org", repo: "flameshot"),

        // MarkText — ad-hoc signed, no Team ID.
        GitHubReleaseRule(
            bundleID: "com.github.marktext.marktext",
            owner: "marktext", repo: "marktext"),

        // darktable — ad-hoc signed. Tags are `release-5.6.0`; the default pattern
        // takes the version out of them.
        GitHubReleaseRule(
            bundleID: "org.darktable",
            owner: "darktable-org", repo: "darktable"),

        // OWASP ZAP — unsigned.
        GitHubReleaseRule(
            bundleID: "org.zaproxy.zap.ZAP",
            owner: "zaproxy", repo: "zaproxy"),

        // BlueBubbles server — Developer ID signed (Team WPV275H8W7) but NOT
        // notarized, so the gate rejects it.
        GitHubReleaseRule(
            bundleID: "com.BlueBubbles.BlueBubbles-Server",
            owner: "BlueBubblesApp", repo: "bluebubbles-server"),

        // Wine (staging) — Gcenx's macOS builds are unsigned, and ship as `.tar.xz`,
        // which the installer doesn't unpack. Detection only. Each release tags one
        // upstream version and carries BOTH a `wine-devel-` and a `wine-staging-`
        // tarball, so this rule is safe for the staging bundle id — see the note
        // below for why the stable bundle id gets no rule.
        GitHubReleaseRule(
            bundleID: "org.winehq.wine-staging.wine",
            owner: "Gcenx", repo: "macOS_Wine_builds"),

        // Deliberately NOT covered — Wine (stable), `org.winehq.wine-stable.wine`.
        // The same repo's releases are the devel/staging train (11.15 on
        // 2026-08-16) while a stable install sits on its own much older line
        // (11.0_1). A rule keyed on `/releases/latest` would tell every stable user
        // that a devel build is their update. Distinguishing the trains needs
        // per-asset filtering (`wine-stable-*`), which a release rule can't express.

        // Deliberately NOT covered — WezTerm (`com.github.wez.wezterm`). Its
        // Info.plist reports a placeholder `0.1.0` for every build while releases are
        // tagged by timestamp (`20240203-110809-5046fc22`). There is no pair of
        // strings to compare, so any rule here would either be silent or permanently
        // claim an update.

        // Deliberately NOT covered — Maestro (`com.maestro.app`). The repo's recent
        // releases are all `cli-<ver>` (the CLI, now at 2.x) while the desktop app's
        // last `v<ver>` tag is 0.17.3 and no longer appears in the newest 60
        // releases. `/releases/latest` today resolves to `cli-2.8.0`, so a rule keyed
        // on this repo would report the CLI's version as the app's. Revisit if the
        // desktop app resumes its own release train.

        // Deliberately NOT covered — ungoogled-chromium. Its builds carry the SAME
        // bundle id as upstream Chromium (`org.chromium.Chromium`) and a version
        // string in the same shape, so a rule keyed on that id would offer
        // ungoogled builds to a plain Chromium install (and vice versa) with nothing
        // in the version to tell the two trains apart. Revisit only with a signal
        // that distinguishes the builds on disk.

        // MARK: - 2026-08-16, second pass
        //
        // These five reached the earlier sweep's "unclassified" pile only because
        // their artifact was too big to download that day — nothing about them is
        // hard. Each line below again states what was read off the very asset the
        // pattern selects, on a mounted copy of the real download.

        // Rancher Desktop — io.rancherdesktop.app, Team 2Q6FHJR3H3, notarized.
        // The release also ships a `-mac.aarch64.zip`; the dmg is the cask's choice
        // and the one verified here.
        GitHubReleaseRule(
            bundleID: "io.rancherdesktop.app",
            owner: "rancher-sandbox", repo: "rancher-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Rancher\.Desktop-[0-9.]+\.aarch64\.dmg$"#,
            installerKind: .dmg),

        // Cherry Studio — com.kangfenmao.CherryStudio, Team 87242QY66T, notarized.
        // The release carries Linux and Windows artifacts with `arm64` in their
        // names too, so the pattern is anchored on the dmg extension.
        GitHubReleaseRule(
            bundleID: "com.kangfenmao.CherryStudio",
            owner: "CherryHQ", repo: "cherry-studio",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Cherry-Studio-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // RedisInsight — org.RedisLabs.RedisInsight-V2, Team UUK47G4BAZ, notarized.
        // Tagged WITHOUT a leading `v` (`3.8.0`). Reached here from the vendor
        // pile: its S3 host does publish an electron-builder manifest, but only
        // under a path that embeds the major version
        // (`…/public/upgrades-v3/latest-mac.yml`), so a probe would have to know
        // the answer to ask the question — and the release lives on plain GitHub
        // Releases regardless, which needs no recipe at all.
        GitHubReleaseRule(
            bundleID: "org.RedisLabs.RedisInsight-V2",
            owner: "redis", repo: "RedisInsight",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Redis-Insight-mac-arm64\.dmg$"#,
            installerKind: .dmg),

        // Upscayl — org.upscayl.Upscayl, Team W2T4W74X87, notarized. (Homebrew's
        // cask says `org.upscayl.app`; the mounted bundle says otherwise, and the
        // bundle wins.) One universal dmg, no per-architecture asset — the name
        // carries no arch token to match on, and the post-download architecture
        // gate is what makes that safe.
        GitHubReleaseRule(
            bundleID: "org.upscayl.Upscayl",
            owner: "upscayl", repo: "upscayl",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^upscayl-[0-9.]+-mac\.dmg$"#,
            installerKind: .dmg),

        // WailBrew — io.github.wickenico.wailbrew, Team 2MC8SWF35Z, notarized.
        // The cask's zap block lists two candidate ids (a rename left `dev.wailbrew`
        // behind); the shipped Info.plist settles it. Note the asset is a zip whose
        // signature only survives `ditto -x -k` — plain `unzip` breaks the seal and
        // makes a good bundle look tampered with.
        GitHubReleaseRule(
            bundleID: "io.github.wickenico.wailbrew",
            owner: "wickenico", repo: "WailBrew",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^wailbrew-v[0-9.]+\.zip$"#,
            installerKind: .zip),

        // Deliberately NOT covered — FreeCAD (`org.freecad.FreeCAD`). Its bundle
        // ships an EMPTY `CFBundleShortVersionString` and puts 1.1.3 in
        // `CFBundleVersion` alone. `AppScanner` drops any bundle with no marketing
        // version — that guard is what keeps helper bundles (URL handlers, login
        // items) out of the list — so FreeCAD never reaches a source at all and a
        // rule here would be dead code. Fixing it means changing what the scanner
        // admits, which is a much larger call than one app.
        //
        // Re-audit trigger: the empty string comes from the conda bundler's
        // `Info.plist.template`. The project's newer rattler-build path fills the
        // short version in, so the day a rattler-built dmg ships, FreeCAD becomes
        // ordinary — tag `1.1.3` (no `v`), asset
        // `FreeCAD_<ver>-macOS-arm64-py<n>.dmg`. Check the shipped plist, not the
        // release notes.
    ]
}
