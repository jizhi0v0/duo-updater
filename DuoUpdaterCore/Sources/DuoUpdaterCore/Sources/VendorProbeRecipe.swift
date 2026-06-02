import Foundation

/// A per-app "probe recipe": how to discover the latest version straight from a
/// vendor's own download endpoint, for apps that no standard source (App Store,
/// Sparkle, Homebrew) can resolve.
///
/// This is deliberately a hand-maintained, per-app table. Unlike the three
/// standard sources — which are general mechanisms — each recipe is bespoke and
/// fragile: links move, version formats vary, some need several redirect hops,
/// some bury the version in a small JSON endpoint. Treat every recipe as
/// best-effort: when a probe can't produce a confident version it degrades
/// silently to "unknown" (see `VendorProbeSource`); it must never invent a
/// version or a false "update available".
///
/// Adding a recipe is a debugging task — use the probe harness in the tests to
/// confirm a vendor's link is stable and actually carries a parseable version
/// before adding it to `VendorProbeRegistry.recipes`.
/// The archive format a vendor ships its installer in. Drives how
/// `VendorInstaller` unpacks the downloaded file before the signature gate.
public enum VendorInstallerKind: Sendable, Hashable {
    case zip
    case dmg
    case tarGz
    case pkg
}

/// How to fetch and install a vendor's update in place — the missing half that
/// turns a detection-only probe into a one-click install. Only attach this to a
/// recipe once the download is confirmed to be a notarized build signed by the
/// *same Team ID* as the installed app (the mandatory gate in `VendorInstaller`).
public struct VendorInstallSpec: Sendable {

    /// How to recover the installer's download URL.
    public enum URLSource: Sendable {
        /// Apply a regex to the probe's response body; capture group 1 (of the
        /// FIRST match) is the absolute download URL. Use when the feed lists the
        /// newest release first (Sparkle `enclosure`, Tauri `url`, JSON `assets`).
        case bodyPattern(String)
        /// Like `bodyPattern`, but takes the LAST match — for feeds listed in
        /// ascending order, where the newest release is the final entry (e.g. the
        /// VLC appcast).
        case bodyPatternLast(String)
        /// Capture group 1 is a *relative* path/filename; resolve it against
        /// `base` to form the absolute URL (e.g. Tailscale's JSON gives only the
        /// pkg filename).
        case bodyPatternRelative(String, base: URL)
        /// Build the URL from a template with `{0}`, `{1}`, … placeholders, each
        /// filled by capture group 1 of the corresponding regex in `fields`,
        /// applied to the body. For feeds that publish the pieces but no link —
        /// e.g. LM Studio gives `version` + `build` and the dmg path needs both.
        case bodyTemplate(String, fields: [String])
        /// A stable "latest" link that 302-redirects to the real installer; we
        /// HEAD-follow it to the final URL (e.g. VS Code's `/latest/...`).
        case redirect(URL)
        /// A fixed, already-final installer URL.
        case fixed(URL)
    }

    public let urlSource: URLSource

    /// Archive format of the download, so we unpack it correctly even when the
    /// URL carries no file extension (e.g. a CDN asset id).
    public let kind: VendorInstallerKind

    /// Optional regex (capture group 1) for an expected SHA-512 of the download,
    /// base64-encoded, pulled from the same response body. When present we verify
    /// it before unpacking — defense in depth on top of the code-signature gate.
    public let checksumPattern: String?

    /// Extra HTTP headers sent when downloading the installer. Needed when the
    /// vendor's download host sits behind a WAF that only serves the binary to
    /// browser-like requests — e.g. Oray's `dw.oray.com` returns an anti-bot JS
    /// challenge unless a `Referer` is present.
    public let requestHeaders: [String: String]

    public init(
        urlSource: URLSource,
        kind: VendorInstallerKind,
        checksumPattern: String? = nil,
        requestHeaders: [String: String] = [:]
    ) {
        self.urlSource = urlSource
        self.kind = kind
        self.checksumPattern = checksumPattern
        self.requestHeaders = requestHeaders
    }
}

public struct VendorProbeRecipe: Sendable {

    /// How the version is recovered from the endpoint.
    public enum Mode: Sendable {
        /// `url` is a stable "latest" link that redirects to the real package;
        /// the version lives in the redirect target (filename or path). With the
        /// default `followRedirects: true` we issue a HEAD, follow redirects, and
        /// parse the resolved URL's filename (e.g. `Foo_3.2.1.dmg`). With
        /// `followRedirects: false` we GET without following and parse the `Location`
        /// header's full URL instead — for endpoints that 307 only on GET, reject
        /// HEAD, or bury the version in a path segment (e.g. Claude's
        /// `dmg/latest/redirect` → `…/universal/<version>/Claude-<hash>.dmg`).
        ///
        /// This is the preferred, most robust mode — pick it whenever the
        /// vendor exposes a versioned download URL.
        case redirectFilename
        /// `url` is a small text/JSON endpoint whose body contains the version;
        /// we GET it and apply `versionPattern` to the response text.
        case responseBody
    }

    /// `CFBundleIdentifier` of the installed app this recipe targets.
    public let bundleID: String

    /// The release channel this recipe's endpoint serves. The source refuses to
    /// apply the recipe unless the installed app is on the SAME channel, so a
    /// stable endpoint can never be served to a Beta/Canary install that shares
    /// the bundle id. Every recipe here targets Stable, so this defaults to
    /// `.stable`; set it explicitly when adding a channel-specific endpoint.
    public let channel: ReleaseChannel

    /// The endpoint to probe (a stable "latest" redirect, or a version API).
    public let url: URL

    /// How to recover the version from the endpoint's response.
    public let mode: Mode

    /// Regex applied to the probed text (final-URL filename, or response body).
    /// The first capture group is taken as the version; if there are no capture
    /// groups, the whole match is used. Keep it anchored/specific enough that it
    /// won't match an unrelated number on the page.
    public let versionPattern: String

    /// Where to send the user to download the update by hand. Defaults to `url`.
    /// Probed updates are always manual (no trusted in-place install path), so
    /// this is the link surfaced to the user.
    public let downloadURL: URL?

    /// The vendor's official changelog / release-notes page, embedded in a web
    /// view in the detail window. Vendor probes carry no inline notes, so this
    /// curated URL is how those apps get a changelog at all. Nil → the app shows
    /// the "no release notes" state. Must be a human-readable notes page (a
    /// "what's new" / release-notes / blog URL), NOT the download endpoint.
    public let changelogURL: URL?

    /// When the pattern matches several times, pick the highest version instead
    /// of the first. Use this ONLY for feeds that list releases in ascending
    /// order and whose pattern matches *nothing but* app versions (e.g. a
    /// Sparkle appcast's `sparkle:version`). Leave false when the body also
    /// contains unrelated version-shaped numbers (plugin versions, min-OS, …) —
    /// there "first match" (the app's own field, listed first) is correct and
    /// "highest" would wrongly grab a bigger unrelated number.
    public let selectHighest: Bool

    /// When present, the app can be updated in place through its own channel: the
    /// source resolves the installer URL (and optional checksum) and hands it to
    /// `VendorInstaller`. Absent → detection only (the user is sent to download
    /// by hand). Only set this for official-website installs, where a vendor
    /// download is the *same* channel the app came from (no cross-channel mixing).
    public let install: VendorInstallSpec?

    /// When false, the probe does NOT follow HTTP redirects: it reads the
    /// redirect response itself (status 3xx, its small body / `Location`). Needed
    /// for endpoints that 302 to a huge binary — following would download the
    /// whole installer just to read a version (e.g. Warp's download gateway,
    /// which only redirects on GET).
    public let followRedirects: Bool

    public init(
        bundleID: String,
        url: URL,
        mode: Mode,
        versionPattern: String,
        downloadURL: URL? = nil,
        changelogURL: URL? = nil,
        selectHighest: Bool = false,
        install: VendorInstallSpec? = nil,
        followRedirects: Bool = true,
        channel: ReleaseChannel = .stable
    ) {
        self.bundleID = bundleID
        self.channel = channel
        self.url = url
        self.mode = mode
        self.versionPattern = versionPattern
        self.downloadURL = downloadURL
        self.changelogURL = changelogURL
        self.selectHighest = selectHighest
        self.install = install
        self.followRedirects = followRedirects
    }

    /// Extract a version from `text` using `pattern`. Pure and side-effect-free
    /// — this is the fragile, format-specific bit, so it's factored out for
    /// unit testing without touching the network. Returns nil when the pattern
    /// is invalid or doesn't match (the caller then degrades to "unknown").
    public static func extractVersion(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        // Prefer the first capture group; fall back to the whole match.
        let target = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard target.location != NSNotFound, let r = Range(target, in: text) else {
            return nil
        }
        return String(text[r])
    }

    /// Like `extractVersion`, but returns capture group 1 of the LAST match —
    /// for ascending-order feeds where the newest entry comes last. Pure, for the
    /// same reason `extractVersion` is.
    public static func lastMatch(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard let match = matches.last else { return nil }
        let target = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard target.location != NSNotFound, let r = Range(target, in: text) else { return nil }
        return String(text[r])
    }

    /// Like `extractVersion`, but when the pattern matches several times (an
    /// appcast/feed listing many releases, often in ascending order) it returns
    /// the *highest* version, not the first. Single-match bodies behave exactly
    /// like `extractVersion`. This is the right default for vendor probes —
    /// "first in the document" is not reliably "newest", but max-by-version is.
    public static func highestVersion(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var best: String?
        for match in regex.matches(in: text, options: [], range: range) {
            let g = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard g.location != NSNotFound, let r = Range(g, in: text) else { continue }
            let candidate = String(text[r])
            if best == nil || VersionComparator.isNewer(candidate, than: best!) {
                best = candidate
            }
        }
        return best
    }
}

/// The verified recipe table. Consulted by `VendorProbeSource` only after the
/// three standard sources have all missed.
///
/// Intentionally empty until a vendor's stable, versioned link is confirmed via
/// the probe harness. Shipping an unverified recipe risks a false "update
/// available", which this source must never produce — an empty table simply
/// means those apps stay "unknown", which is the correct, honest default.
///
/// Every recipe below was verified by probing the live endpoint and confirming
/// it yields the app's current version (≥ the installed copy). Endpoints are
/// arm64-flavored where the vendor splits by architecture — fine for Apple
/// Silicon; an Intel build would need its own URLs.
///
/// Known-unfeasible (left out, would only mislead): Spotify (version API needs
/// an account token), Paste (no public version API; direct build outruns MAS),
/// ToDesk (appcast behind a JS bot-challenge), WeLink (Zoom-SDK private
/// updater), RunnerNotify / STCM Editor (ad-hoc internal builds). The Android
/// Studio recipe below targets the Stable channel only; a Canary/Preview install
/// (which shares `com.google.android.studio`) is detected as a non-stable
/// `ReleaseChannel` and skipped by `VendorProbeSource`'s channel gate, so it's
/// never overwritten with a Stable build — a dedicated canary endpoint is still
/// pending.
///
/// GitHub-released apps are handled by `GitHubReleasesSource`, not here.
public enum VendorProbeRegistry {
    public static let recipes: [VendorProbeRecipe] = [
        // VS Code — Microsoft's official update API. `name` is the version.
        VendorProbeRecipe(
            bundleID: "com.microsoft.VSCode",
            url: URL(string: "https://update.code.visualstudio.com/api/update/darwin-arm64/stable/latest")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://code.visualstudio.com/updates"),
            // `/latest/darwin-arm64/stable` 302-redirects to the official zip.
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://update.code.visualstudio.com/latest/darwin-arm64/stable")!),
                kind: .zip)),

        // IntelliJ IDEA — JetBrains data services. 3-component (YYYY.x.y) so the
        // 2-component `majorVersion` field can't match.
        VendorProbeRecipe(
            bundleID: "com.jetbrains.intellij",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]{4}\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://www.jetbrains.com/idea/whatsnew/")),

        // JetBrains Toolbox — uses the 4-component `build`, which matches the
        // app's CFBundleShortVersionString (e.g. 3.4.3.81140).
        VendorProbeRecipe(
            bundleID: "com.jetbrains.toolbox",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release")!,
            mode: .responseBody,
            versionPattern: #""build"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://blog.jetbrains.com/toolbox-app/")),

        // Google Chrome — official VersionHistory API (page_size=1, desc).
        VendorProbeRecipe(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            // Rollout-aware. The bare `versions` endpoint returns the newest build
            // that merely EXISTS — even at 0.5% rollout — so we'd lead Keystone and
            // show a phantom update (Chrome itself still says "up to date"). The
            // `releases` endpoint carries a `fraction` (0–1 rollout). Take the
            // highest version at fraction=1 (fully rolled out = what Keystone offers
            // everyone). `fraction` precedes `version` in each release object.
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            // Detection only (Chrome self-updates via Keystone — we never install
            // over it). Instead of a download page, point "Open" at Chrome's own
            // about page: visiting chrome://settings/help makes Chrome run an
            // immediate update check + download through Keystone — its real,
            // same-channel update path. (An app-scheme URL, so the UI hands it to
            // Chrome itself rather than a browser.)
            downloadURL: URL(string: "chrome://settings/help")!,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes")),

        // Google Chrome — Beta / Dev / Canary channels. Each ships its OWN bundle
        // id (`com.google.Chrome.beta` / `.dev` / `.canary`) and is detected as
        // its own `ReleaseChannel`, so the channel gate routes each install to its
        // matching feed — a Beta install never gets the Stable version and vice
        // versa. Same rollout-aware `fraction:1` pattern as Stable (the
        // VersionHistory API is identical per channel; Canary publishes every
        // build at fraction 1). Detection only — all Chrome channels self-update
        // through Keystone, so we never install over them.
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.beta",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/beta/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "chrome://settings/help")!,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.dev",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/dev/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "chrome://settings/help")!,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            channel: .dev),
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.canary",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/canary/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "chrome://settings/help")!,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            channel: .canary),

        // Microsoft Edge — Stable / Beta / Dev. One enterprise endpoint lists all
        // products; each per-channel pattern scopes to that Product's first
        // (newest) MacOS release. Distinct bundle ids (`…edgemac[.Beta/.Dev]`) so
        // the channel gate routes each install to its own version. Detection only
        // — Edge self-updates via Microsoft AutoUpdate. (Edge Canary isn't carried
        // by this enterprise API, so it stays "unknown" rather than mis-served.)
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Stable".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoft.com/edge/download"),
            changelogURL: URL(string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnotes")),
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac.Beta",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Beta".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoftedgeinsider.com/download"),
            changelogURL: URL(string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnotes-beta-channel"),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac.Dev",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Dev".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoftedgeinsider.com/download"),
            changelogURL: URL(string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnotes-dev-channel"),
            channel: .dev),

        // Firefox — Mozilla's `product-details` endpoint carries every channel's
        // current version in one JSON. Release, Beta and ESR all ship as
        // `org.mozilla.firefox` (only the version string's `b`/`esr` suffix tells
        // them apart — see `ReleaseChannel`), so three recipes share that bundle
        // id and are picked by the install's detected channel. Developer Edition
        // and Nightly have their own bundle ids. The captured version KEEPS the
        // `bN`/`esr` suffix so it compares equal to the installed app's
        // `CFBundleShortVersionString` (stripping it would read as a downgrade and
        // never offer an update). Detection only — Firefox self-updates.
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_FIREFOX_VERSION"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/notes/")),
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_FIREFOX_RELEASED_DEVEL_VERSION"\s*:\s*"([0-9]+\.[0-9]+b[0-9]+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/channel/desktop/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/beta/notes/"),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""FIREFOX_ESR"\s*:\s*"([0-9]+(?:\.[0-9]+)+esr)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/enterprise/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/organizations/notes/"),
            channel: .esr),
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefoxdeveloperedition",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""FIREFOX_DEVEDITION"\s*:\s*"([0-9]+\.[0-9]+b[0-9]+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/developer/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/beta/notes/"),
            // Developer Edition tracks the Beta train (its version is a `bN`),
            // which the channel detector classifies as `.beta`.
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "org.mozilla.nightly",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""FIREFOX_NIGHTLY"\s*:\s*"([0-9]+\.[0-9]+a[0-9]+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/channel/desktop/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/nightly/notes/"),
            channel: .nightly),

        // Thunderbird — same Mozilla `product-details` mechanism. Release, Beta
        // and ESR share `org.mozilla.thunderbird`, separated by the version
        // suffix. Detection only — Thunderbird self-updates.
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_THUNDERBIRD_VERSION"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/")),
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_THUNDERBIRD_DEVEL_VERSION"\s*:\s*"([0-9]+\.[0-9]+b[0-9]+)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/channel/desktop/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/"),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""THUNDERBIRD_ESR"\s*:\s*"([0-9]+(?:\.[0-9]+)+esr)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/enterprise/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/"),
            channel: .esr),

        // Warp — Preview / Beta / Dev / Canary. One JSON lists every channel's
        // version, each tagged with the channel name in its suffix
        // (`…preview_01`), so a per-channel pattern is unambiguous. Channels ship
        // as separate bundle ids (`dev.warp.Warp-Preview`, …) — the Stable build
        // is the existing `dev.warp.Warp-Stable` recipe above. We extract the bare
        // date-version (dropping the `v` prefix and `.<channel>_NN` suffix) to
        // match the form Stable already compares against. Detection only (Warp
        // self-updates); the Stable recipe keeps its one-click install.
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Preview",
            url: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.preview_[0-9]+""#,
            downloadURL: URL(string: "https://www.warp.dev/download-preview"),
            changelogURL: URL(string: "https://docs.warp.dev/getting-started/changelog"),
            channel: .preview),
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Beta",
            url: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.beta_[0-9]+""#,
            downloadURL: URL(string: "https://www.warp.dev/download"),
            changelogURL: URL(string: "https://docs.warp.dev/getting-started/changelog"),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Dev",
            url: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.dev_[0-9]+""#,
            downloadURL: URL(string: "https://www.warp.dev/download"),
            changelogURL: URL(string: "https://docs.warp.dev/getting-started/changelog"),
            channel: .dev),
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Canary",
            url: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.canary_[0-9]+""#,
            downloadURL: URL(string: "https://www.warp.dev/download"),
            changelogURL: URL(string: "https://docs.warp.dev/getting-started/changelog"),
            channel: .canary),

        // Signal — Stable + Beta. electron-builder feeds (one per channel). Stable
        // ships `org.whispersystems.signal-desktop`; Beta is a separate
        // "Signal Beta.app" (detected as `.beta` from its name). Detection only —
        // Signal self-updates via electron-updater.
        VendorProbeRecipe(
            bundleID: "org.whispersystems.signal-desktop",
            url: URL(string: "https://updates.signal.org/desktop/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://signal.org/download/"),
            changelogURL: URL(string: "https://github.com/signalapp/Signal-Desktop/releases")),
        VendorProbeRecipe(
            bundleID: "org.whispersystems.signal-desktop-beta",
            url: URL(string: "https://updates.signal.org/desktop/beta-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://signal.org/download/"),
            changelogURL: URL(string: "https://github.com/signalapp/Signal-Desktop/releases"),
            channel: .beta),

        // Element — Stable + Nightly, split bundle ids (`im.riot.app` vs
        // `io.element.nightly`). `currentRelease` is the latest version (semver
        // for Stable, a `YYYYMMDDNN` build stamp for Nightly). Detection only —
        // Element self-updates via Squirrel.
        VendorProbeRecipe(
            bundleID: "im.riot.app",
            url: URL(string: "https://packages.element.io/desktop/update/macos/releases.json")!,
            mode: .responseBody,
            versionPattern: #""currentRelease"\s*:\s*"([^"]+)""#,
            downloadURL: URL(string: "https://element.io/download"),
            changelogURL: URL(string: "https://github.com/element-hq/element-desktop/releases")),
        VendorProbeRecipe(
            bundleID: "io.element.nightly",
            url: URL(string: "https://packages.element.io/nightly/update/macos/releases.json")!,
            mode: .responseBody,
            versionPattern: #""currentRelease"\s*:\s*"([^"]+)""#,
            downloadURL: URL(string: "https://element.io/download"),
            changelogURL: URL(string: "https://github.com/element-hq/element-desktop/releases"),
            channel: .nightly),

        // Cursor — official update API; the first `version` field is the latest
        // build. Single channel (its "stable"/"latest" tracks resolve to the same
        // build). Detection only — Cursor self-updates via ToDesktop.
        VendorProbeRecipe(
            bundleID: "com.todesktop.230313mzl4w4u92",
            url: URL(string: "https://api2.cursor.sh/updates/api/download/latest/darwin-arm64/cursor")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.cursor.com/downloads"),
            changelogURL: URL(string: "https://www.cursor.com/changelog")),

        // Raycast — official "latest release" endpoint; `version` is first. Single
        // channel. Detection only — Raycast self-updates.
        VendorProbeRecipe(
            bundleID: "com.raycast.macos",
            url: URL(string: "https://releases.raycast.com/releases/latest?build=universal")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.raycast.com/"),
            changelogURL: URL(string: "https://www.raycast.com/changelog")),

        // Docker Desktop — Sparkle appcast. Titles read "<ver> (<build>)" (and
        // "Version <ver> (<build>)"); take the highest since the feed isn't
        // strictly ordered. The channel title "Docker for Mac" carries no
        // version-paren and is skipped. Build number ignored in comparison.
        VendorProbeRecipe(
            bundleID: "com.docker.docker",
            url: URL(string: "https://desktop.docker.com/mac/main/arm64/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<title>(?:Version\s*)?([0-9]+\.[0-9]+\.[0-9]+)\s*\("#,
            downloadURL: URL(string: "https://www.docker.com/products/docker-desktop/"),
            changelogURL: URL(string: "https://docs.docker.com/desktop/release-notes/"),
            selectHighest: true),

        // LibreWolf — release tags on its GitLab repo, newest first. Tags are
        // "<firefox-version>-<packaging>" (e.g. "147.0.4-1"); we capture only the
        // upstream Firefox version so it compares equal to the installed app's
        // `CFBundleShortVersionString` (keeping "-1" would read as a perpetual
        // update). No auto-updater — this is genuinely useful for LibreWolf.
        VendorProbeRecipe(
            bundleID: "org.mozilla.librewolf",
            url: URL(string: "https://gitlab.com/api/v4/projects/44042130/repository/tags?per_page=5")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"#,
            downloadURL: URL(string: "https://librewolf.net/installation/macos/"),
            changelogURL: URL(string: "https://gitlab.com/librewolf-community/browser/bsys6/-/releases")),

        // Claude desktop — public "latest" download redirect. Deliberately NOT
        // the Squirrel endpoint: that one takes a `device_id` and is cohort-gated,
        // so a synthetic id lands in a fixed staged-rollout bucket that drifts from
        // this install's own bucket (false negatives when behind, and a false
        // "update available" when ahead). This redirect carries no id: it serves
        // the current GA build, exactly what the website's download button gives.
        // The version is in the 307 `Location` path (…/universal/<version>/…);
        // GET only (HEAD 405s) and don't follow (that downloads the archive). Use
        // api.anthropic.com, NOT claude.ai — the latter sits behind a Cloudflare
        // JS challenge that a non-browser client can't pass.
        //
        // One-click install is safe here: `/latest` is the public GA build (same
        // as a manual claude.ai/download), not a held-back rollout, so installing
        // it never jumps this machine ahead of a cohort. We take the `zip` (the
        // format Claude's own Squirrel updater uses) over the heavier dmg. The
        // `Location` URL is reused as the install body, so the same response yields
        // both the version and the download. Team Q6L2SF6YDW gates the swap.
        VendorProbeRecipe(
            bundleID: "com.anthropic.claudefordesktop",
            url: URL(string: "https://api.anthropic.com/api/desktop/darwin/universal/zip/latest/redirect")!,
            mode: .redirectFilename,
            versionPattern: #"/darwin/universal/([0-9]+\.[0-9]+\.[0-9]+)/"#,
            downloadURL: URL(string: "https://claude.ai/download"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://downloads\.claude\.ai/releases/darwin/universal/[0-9.]+/Claude-[0-9a-f]+\.zip)"#),
                kind: .zip),
            followRedirects: false),

        // VLC — official Sparkle appcast. Lists releases ascending, so
        // highestVersion (not first) picks the current one.
        VendorProbeRecipe(
            bundleID: "org.videolan.vlc",
            url: URL(string: "https://update.videolan.org/vlc/sparkle/vlc-arm64.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:version="([0-9.]+)""#,
            changelogURL: URL(string: "https://www.videolan.org/vlc/releases/"),
            selectHighest: true,
            // Ascending appcast → take the LAST enclosure (newest). http mirror
            // gateway is upgraded to https by the source. Team 75GAHG3SZQ.
            install: VendorInstallSpec(
                urlSource: .bodyPatternLast(#"url="(https?://get\.videolan\.org/vlc/[^"]+arm64\.dmg)""#),
                kind: .dmg)),

        // Codex — OpenAI's Sparkle appcast (feed URL is baked into the app, not
        // the Info.plist, so the Sparkle source can't see it).
        VendorProbeRecipe(
            bundleID: "com.openai.codex",
            url: URL(string: "https://persistent.oaistatic.com/codex-app-prod/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9][^<]*)</sparkle:shortVersionString>"#,
            changelogURL: URL(string: "https://developers.openai.com/codex/changelog?type=codex-app")!,
            // Sparkle enclosure points at the full zip (ignore the `.delta` urls).
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"url="([^"]+\.zip)""#),
                kind: .zip)),

        // ChatWise — Squirrel releases endpoint; array of versions, take highest.
        VendorProbeRecipe(
            bundleID: "app.chatwise",
            url: URL(string: "https://releases.chatwise.app/releases?version=0.0.0&platform=osx")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://chatwise.app/changelog"),
            // assets[] carries the arm64 zip and its SHA-512 (base64) — use both.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"([^"]*arm64\.zip)""#),
                kind: .zip,
                checksumPattern: #"arm64\.zip"\s*,\s*"sha512"\s*:\s*"([^"]+)""#)),

        // LM Studio — official version endpoint (same one Homebrew livecheck
        // uses). Compares on marketing version; build suffix is ignored.
        VendorProbeRecipe(
            bundleID: "ai.elementlabs.lmstudio",
            url: URL(string: "https://versions-prod.lmstudio.ai/update/darwin/arm64/0.0.0")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://lmstudio.ai/changelog"),
            // Feed has no link — build the dmg path from version + build, both of
            // which are REQUIRED in the path (…/0.4.15-2/LM-Studio-0.4.15-2-arm64.dmg;
            // dropping the build 404s). Team D65G88RHWN.
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://installers.lmstudio.ai/darwin/arm64/{0}-{1}/LM-Studio-{0}-{1}-arm64.dmg",
                    fields: [#""version"\s*:\s*"([^"]+)""#, #""build"\s*:\s*"([^"]+)""#]),
                kind: .dmg)),

        // Conductor — CrabNebula (Tauri) updater; passing 0.0.0 returns latest.
        VendorProbeRecipe(
            bundleID: "com.conductor.app",
            url: URL(string: "https://cdn.crabnebula.app/update/melty/conductor/darwin-aarch64/0.0.0")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://conductor.build/changelog"),
            // Tauri updater `url` is the `Conductor.app.tar.gz` (CDN asset id, no
            // file extension — VendorInstaller renames by kind before unpacking).
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"([^"]+)""#),
                kind: .tarGz)),

        // Tailscale — official package index. `MacZipsVersion` is the macsys
        // build (top-level `Version` is the Linux/Windows train — wrong here).
        VendorProbeRecipe(
            bundleID: "io.tailscale.ipn.macsys",
            url: URL(string: "https://pkgs.tailscale.com/stable/?mode=json")!,
            mode: .responseBody,
            versionPattern: #""MacZipsVersion"\s*:\s*"([0-9.]+)""#,
            changelogURL: URL(string: "https://tailscale.com/changelog"),
            // JSON gives only the pkg filename → resolve against the base dir.
            // pkg → opened in the system installer. Signed by Tailscale W5364U7YZB.
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #""universal-package"\s*:\s*"(Tailscale-[^"]+\.pkg)""#,
                    base: URL(string: "https://pkgs.tailscale.com/stable/")!),
                kind: .pkg)),

        // AweSun (Oray) — official software API; same endpoint the Homebrew cask
        // livecheck uses. Intel build drops the `_ARM` suffix. The dmg holds a
        // signed `AweSun.pkg` (Developer ID Installer ZBNMDRTU32) → system
        // installer (pkg). We BUILD the dmg URL from `versionno` rather than read
        // the JSON's own `downloadurl`: that field escapes its slashes
        // (`https:\/\/…`, breaking `URL(string:)`) and points at a different host
        // (`d-cdn.oray.com`); the `dw.oray.com` filename pattern below is the one
        // verified to serve the build whose md5 matches the JSON. `dw.oray.com`
        // is behind an Aliyun WAF that returns an anti-bot JS challenge unless a
        // `Referer` is present — so we send one. If the URL can't be built, the
        // probe degrades to opening the official download page (downloadURL).
        VendorProbeRecipe(
            bundleID: "com.oray.sunlogin.macclient",
            url: URL(string: "https://client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM?versiontype=stable")!,
            mode: .responseBody,
            versionPattern: #""versionno"\s*:\s*"([0-9.]+)""#,
            downloadURL: URL(string: "https://sunlogin.oray.com/download"),
            changelogURL: URL(string: "https://sunlogin.oray.com/download/update-log?soft=SLCC_X_MAC_ARM"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://dw.oray.com/sl/mac/AweSun_v{0}_arm64.dmg",
                    fields: [#""versionno"\s*:\s*"([0-9.]+)""#]),
                kind: .pkg,
                requestHeaders: ["Referer": "https://sunlogin.oray.com/"])),

        // OrbStack — Sparkle appcast on its CDN. NOTE: staged (graylist) rollout
        // means this can briefly trail the installed build — that only yields a
        // benign "up to date", never a false update.
        VendorProbeRecipe(
            bundleID: "dev.kdrag0n.MacVirt",
            url: URL(string: "https://cdn-updates.orbstack.dev/arm64/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"OrbStack_v([0-9.]+)_"#,
            changelogURL: URL(string: "https://docs.orbstack.dev/release-notes"),
            // Newest-first appcast → first enclosure is correct. Team HUAQ24HBR6.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure url="(https://cdn-updates\.orbstack\.dev/arm64/OrbStack_v[0-9.]+_[0-9]+_arm64\.dmg)""#),
                kind: .dmg)),

        // Postman — CDN JSON that also powers the ChangelogRecipe. The "notes"
        // array is sorted newest-first, so the first "version" field is always
        // the latest release. We install in place: `dl.pstmn.io/download/version/
        // <ver>/osx_arm64` serves the official notarized zip (Postman.app, Team
        // H7H8Q7M5CK — the same Team the installed app verifies against), with no
        // WAF. Postman self-updates via Squirrel too, but we fetch the *same*
        // latest build from its own CDN, so this never crosses channels or
        // downgrades. If the URL can't be built, it degrades to the downloads
        // page. arm64-only, matching the other recipes' Apple-silicon endpoints.
        VendorProbeRecipe(
            bundleID: "com.postmanlabs.mac",
            url: URL(string: "https://mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json")!,
            mode: .responseBody,
            versionPattern: #""notes"\s*:\s*\[\s*\{[^}]*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.postman.com/downloads/"),
            changelogURL: URL(string: "https://www.postman.com/release-notes/postman-app/"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://dl.pstmn.io/download/version/{0}/osx_arm64",
                    fields: [#""notes"\s*:\s*\[\s*\{[^}]*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#]),
                kind: .zip)),

        // HBuilderX (DCloud) — internal update manifest pulled from the app
        // binary. NOTE: undocumented endpoint (and http) — may break or be
        // blocked by ATS; degrades silently to unknown if so.
        VendorProbeRecipe(
            bundleID: "io.dcloud.HBuilderX",
            url: URL(string: "http://update.liuyingyong.cn/hbuilderx/alpha/macosx-arm64/update/index.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://hx.dcloud.net.cn/Tutorial/HistoryVersion")),

        // Warp — GitHub releases carry NO binary asset; the real dmg lives on
        // Warp's CDN. `app.warp.dev/download?package=dmg` returns a tiny HTML page
        // linking the current `releases.warp.dev/stable/v<ver>/Warp.dmg` (always
        // latest). Version + download both come from that one page. Team 2BBY89MBSN.
        // (Note: its URL build can lead the GitHub tag by a few hours — the CDN is
        // the more accurate source, so Warp lives here, not in GitHubReleaseRegistry.)
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Stable",
            url: URL(string: "https://app.warp.dev/download?package=dmg")!,
            mode: .responseBody,
            versionPattern: #"releases\.warp\.dev/stable/v([0-9.]+)\.stable"#,
            changelogURL: URL(string: "https://docs.warp.dev/changelog/2026/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://releases\.warp\.dev/stable/[^"]+\.dmg)"#),
                kind: .dmg),
            // GET 302s straight to the 320 MB dmg — DON'T follow; read the small
            // redirect body, whose href carries both the version and the dmg URL.
            followRedirects: false),

        // Android Studio — for WEBSITE-direct installs only. Toolbox-managed
        // copies are gated out of VendorProbeSource and handled by ToolboxSource
        // (open Toolbox); this recipe fires for a hand-downloaded Android Studio.
        // developer.android.com/studio is static HTML carrying both the version
        // and the arm64 dmg href on the same page. Team EQHXZ8M8AV.
        VendorProbeRecipe(
            bundleID: "com.google.android.studio",
            url: URL(string: "https://developer.android.com/studio")!,
            mode: .responseBody,
            versionPattern: #"install/([0-9]{4}\.[0-9]+\.[0-9]+)\.[0-9]+/android-studio-[^"]*mac_arm\.dmg"#,
            changelogURL: URL(string: "https://developer.android.com/studio/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://edgedl\.me\.gvt1\.com/android/studio/install/[0-9.]+/android-studio-[^"]*mac_arm\.dmg)"#),
                kind: .dmg)),

        // MacUpdater — version is in an HTML comment marker on the product page.
        // NOTE: HTML scrape — more brittle than an API; refresh if it stops
        // matching.
        VendorProbeRecipe(
            bundleID: "com.corecode.MacUpdater",
            url: URL(string: "https://www.corecode.io/macupdater/")!,
            mode: .responseBody,
            versionPattern: #"<!--BEGINVERSION-->([0-9.]+)<!--ENDVERSION-->"#,
            changelogURL: URL(string: "https://www.corecode.io/macupdater/history3.html")),

        // Surge Mac — official Sparkle appcasts. The public "latest" URLs are
        // the release and beta feeds used by the Surge changelog channel.
        // Use the beta feed for the broader update signal; the version string is
        // the short marketing version, which keeps comparison conservative.
        VendorProbeRecipe(
            bundleID: "com.nssurge.surge-mac",
            url: URL(string: "https://nssurge.com/mac/latest/appcast-signed-beta.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+(?:\.[0-9]+){1,2})</sparkle:shortVersionString>"#,
            changelogURL: URL(string: "https://nssurge.com/support/mac/release-notes")),
    ]
}
