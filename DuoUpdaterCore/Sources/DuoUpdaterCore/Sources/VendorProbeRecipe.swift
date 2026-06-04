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
/// updater), RunnerNotify / STCM Editor (ad-hoc internal builds), Brave and
/// Feishu/Lark (their `CFBundleShortVersionString` is Chromium-major-prefixed —
/// e.g. Brave `148.1.90.128`, Feishu `131.0.6778.268` — but every vendor feed
/// only exposes the bare app version `1.90.128` / `7.69.9`, which can't be made
/// to compare in the same scheme, so any probe would phantom-update or
/// phantom-downgrade; don't re-attempt without a Chromium-major source). The Android
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

        // Microsoft Teams — Microsoft's config/v1 version API (same family as
        // VS Code & Edge). The "WebView2Canary" track is the production/Public R4
        // build despite the confusing name. Teams self-updates via Microsoft
        // AutoUpdate (com.microsoft.autoupdate2). Installs from the buildLink in
        // the same JSON response.
        VendorProbeRecipe(
            bundleID: "com.microsoft.teams2",
            url: URL(string: "https://config.teams.microsoft.com/config/v1/MicrosoftTeams/1?environment=prod&audienceGroup=general&teamsRing=general&agent=TeamsBuilds")!,
            mode: .responseBody,
            versionPattern: #""WebView2Canary":\{"macOS":\{"latestVersion":"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-teams/download-app")!,
            changelogURL: URL(string: "https://support.microsoft.com/en-us/office/what-s-new-in-microsoft-teams-d7092a6d-c896-424c-b362-a472d5f105de")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""buildLink":"([^"]+MicrosoftTeams\.pkg)""#),
                kind: .pkg)),

        // Microsoft OneDrive — Microsoft's "latest" download fwlink. A single 302
        // lands on a versioned .pkg URL on oneclient.sfx.ms. The version is a
        // 4-component path segment, not a filename, so followRedirects:false reads
        // the Location header instead of lastPathComponent. OneDrive self-updates
        // via OneDriveStandaloneUpdaterDaemon; install follows the same fwlink.
        VendorProbeRecipe(
            bundleID: "com.microsoft.OneDrive",
            url: URL(string: "https://go.microsoft.com/fwlink/?linkid=823060")!,
            mode: .redirectFilename,
            versionPattern: #"/Installers/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onedrive/download")!,
            changelogURL: URL(string: "https://support.microsoft.com/en-us/office/onedrive-release-notes-845dcf18-f921-435e-bf28-4e24b95e9fc0")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/?linkid=823060")!),
                kind: .pkg),
            followRedirects: false),

        // Microsoft PowerPoint — Office suite, unified version. The fwlink 302s to
        // a versioned .pkg on the Office CDN. MAU-managed.
        VendorProbeRecipe(
            bundleID: "com.microsoft.Powerpoint",
            url: URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525136")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/powerpoint")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft-365-apps-mac")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525136")!),
                kind: .pkg),
            followRedirects: false),

        // Microsoft Word — Office suite, unified version. Same CDN/fwlink pattern
        // as PowerPoint. MAU-managed.
        VendorProbeRecipe(
            bundleID: "com.microsoft.Word",
            url: URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525134")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/word")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft-365-apps-mac")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525134")!),
                kind: .pkg),
            followRedirects: false),

        // Microsoft Excel — Office suite, unified version. Same CDN/fwlink pattern
        // as PowerPoint. MAU-managed.
        VendorProbeRecipe(
            bundleID: "com.microsoft.Excel",
            url: URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525135")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/excel")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft-365-apps-mac")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525135")!),
                kind: .pkg),
            followRedirects: false),

        // Microsoft OneNote — Office suite, unified version. No dedicated OneNote
        // fwlink; uses the Office suite fwlink (linkid=525133) that redirects to
        // the Microsoft_365_and_Office installer — same version. MAU-managed.
        VendorProbeRecipe(
            bundleID: "com.microsoft.onenote.mac",
            url: URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525133")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onenote/digital-note-taking-app")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft-365-apps-mac")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525133")!),
                kind: .pkg),
            followRedirects: false),

        // Microsoft Outlook — Office suite, unified version. Uses the Office
        // AutoUpdate XML manifest (same CDN product tree as the fwlinks) which
        // carries per-product Update Version Location entries. MAU-managed.
        VendorProbeRecipe(
            bundleID: "com.microsoft.Outlook",
            url: URL(string: "https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409OPIM2019.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>Update Version</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/outlook/outlook-for-business")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft-365-apps-mac")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"<key>Update Version Location</key>\s*<string>([^<]+\.pkg)</string>"#),
                kind: .pkg)),

        // Bartender — Sparkle appcast (ascending, oldest-first). Version lives in
        // sparkle:shortVersionString on each <item>. Detection-only; if the
        // installed app has SUFeedURL in Info.plist SparkleAppcastSource takes
        // priority. selectHighest because the feed lists items oldest-first.
        VendorProbeRecipe(
            bundleID: "com.surteesstudios.Bartender",
            url: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+\.[0-9]+\.[0-9]+)</sparkle:shortVersionString>"#,
            downloadURL: URL(string: "https://www.macbartender.com/")!,
            changelogURL: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            selectHighest: true),

        // ImageOptim — Sparkle appcast carrying only the latest release
        // (descending, single item). Version in sparkle:shortVersionString.
        // Detection-only; SparkleAppcastSource takes priority if SUFeedURL present.
        VendorProbeRecipe(
            bundleID: "net.pornel.ImageOptim",
            url: URL(string: "https://imageoptim.com/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:shortVersionString="([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://imageoptim.com/mac")!,
            changelogURL: URL(string: "https://imageoptim.com/changelog.html")!),

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

        // OrbStack — one Sparkle appcast (`appcast.new.xml`; the old `appcast.xml`
        // froze at 2.1.2) carrying every channel as <sparkle:channel> elements.
        // OrbStack has no Info.plist SUFeedURL, so it reaches us here, not via
        // SparkleAppcastSource; `AppScanner` reads `updates_optinChannel` to set
        // the install's channel (see `OrbStackChannel`) and we pick the matching
        // recipe per `channel`. Each anchors its regex to its own channel tag, so
        // a user is only ever offered their channel's build. Install stays on the
        // codesign path (Team HUAQ24HBR6) — OrbStack ships no SUPublicEDKey.
        orbStackRecipe(.stable, tag: "stable"),
        orbStackRecipe(.beta, tag: "beta"),
        orbStackRecipe(.canary, tag: "canary"),

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
        // binary. NOTE: undocumented endpoint; degrades silently to unknown if
        // it moves. The host also serves the manifest over https, so we hit
        // that — a plain-http url would be blocked by ATS at load time.
        VendorProbeRecipe(
            bundleID: "io.dcloud.HBuilderX",
            url: URL(string: "https://update.liuyingyong.cn/hbuilderx/alpha/macosx-arm64/update/index.json")!,
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

        // Slack (desktop, mac) — the website's own "latest" download link. A
        // single 302 from slack.com/ssb/download-osx-universal lands on the
        // versioned package downloads.slack-edge.com/.../mac/universal/<ver>/
        // Slack-<ver>-macOS.dmg, so the version rides in the resolved filename
        // (HEAD+follow → lastPathComponent). Use the -universal link, NOT -osx
        // (that resolves to the x64/Intel build). Detection only — Slack
        // self-updates via Squirrel; ChangelogRecipe(com.tinyspeck.slackmacgap)
        // renders the notes natively.
        VendorProbeRecipe(
            bundleID: "com.tinyspeck.slackmacgap",
            url: URL(string: "https://slack.com/ssb/download-osx-universal")!,
            mode: .redirectFilename,
            versionPattern: #"^Slack-([0-9]+\.[0-9]+\.[0-9]+)-macOS\.dmg$"#,
            downloadURL: URL(string: "https://slack.com/downloads/mac"),
            changelogURL: URL(string: "https://slack.com/release-notes/mac")),

        // Discord — official update manifest (channel=stable, platform=osx). The
        // version lives ONLY as the JSON array `host_version:[0,0,393]` and as a
        // path segment in each distro `url` (…/osx/universal/0.0.393/…). The array
        // is unusable — extractVersion takes capture group 1 only and can't join
        // three groups (it'd read "0") — so we anchor to the distro url path,
        // which carries the whole X.Y.Z in one group. Every url in the body (full
        // + deltas + per-module) targets the same destination version, so first
        // match is correct; the delta SOURCE (0.0.392) never appears as a
        // /universal/<v>/ segment. Detection only — Discord self-updates via its
        // own host updater. ptb/canary ship as separate bundle ids with their own
        // channel=ptb|canary endpoints — add dedicated recipes if needed.
        VendorProbeRecipe(
            bundleID: "com.hnc.Discord",
            url: URL(string: "https://updates.discord.com/distributions/app/manifests/latest?channel=stable&platform=osx&arch=x64")!,
            mode: .responseBody,
            versionPattern: #"stable\.dl2\.discordapp\.net/distro/app/stable/osx/universal/([0-9]+\.[0-9]+\.[0-9]+)/"#,
            downloadURL: URL(string: "https://discord.com/download"),
            changelogURL: URL(string: "https://discord.com/blog")),

        // Notion desktop — public "latest" download redirect. www.notion.so/
        // desktop/mac/download 307s straight to the versioned installer
        // (…/Notion-<ver>-universal.dmg); the version is in that `Location`
        // filename. It redirects on BOTH HEAD and GET, but the target is a
        // ~203 MB dmg, so don't follow — read the small 307 Location. Use the
        // `.so` host: it's a single hop, whereas `.com/desktop/mac/download`
        // bounces through app.notion.com first. Detection only — Notion ships a
        // universal dmg and self-updates; ChangelogRecipe(notion.id) renders notes.
        VendorProbeRecipe(
            bundleID: "notion.id",
            url: URL(string: "https://www.notion.so/desktop/mac/download")!,
            mode: .redirectFilename,
            versionPattern: #"Notion-([0-9]+\.[0-9]+\.[0-9]+)-"#,
            downloadURL: URL(string: "https://www.notion.com/desktop")!,
            changelogURL: URL(string: "https://www.notion.com/releases")!,
            followRedirects: false),

        // Obsidian — official desktop-releases manifest (the same file Obsidian's
        // own updater reads). Two "latestVersion" keys live here: the TOP-LEVEL
        // one is STABLE, then a nested "beta" object carries the (currently HIGHER)
        // insider build. We anchor to the FIRST match so we read STABLE only;
        // selectHighest stays false (true would grab the bigger beta value and
        // invent a phantom update for a stable install). Detection only — Obsidian
        // self-updates; ChangelogRecipe(md.obsidian) renders the notes natively.
        VendorProbeRecipe(
            bundleID: "md.obsidian",
            url: URL(string: "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/desktop-releases.json")!,
            mode: .responseBody,
            versionPattern: #""latestVersion"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://obsidian.md/download"),
            changelogURL: URL(string: "https://obsidian.md/changelog/")),

        // Figma desktop — official per-arch "latest" manifest (the same
        // RELEASE.json the Homebrew cask livecheck reads). `version` is first and
        // matches the app's CFBundleShortVersionString (e.g. 126.4.11). mac-arm is
        // the Apple-silicon flavor; an Intel build would use the `mac` path.
        // Detection only — a Figma-<ver>.zip exists in the same body but was NOT
        // confirmed same-Team-ID, so no in-place install; Figma also self-updates
        // via Squirrel. ChangelogRecipe(com.figma.Desktop) renders the notes.
        VendorProbeRecipe(
            bundleID: "com.figma.Desktop",
            url: URL(string: "https://desktop.figma.com/mac-arm/RELEASE.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.figma.com/downloads/"),
            changelogURL: URL(string: "https://www.figma.com/release-notes/")),

        // 1Password 8 — self-updates via its own EdDSA updater, so no standard
        // source resolves it. The vendor's app-updates.agilebits.com/check JSON
        // API only serves the NIGHTLY channel for product OPM8 (no stable param
        // exists), so it can't be used for a stable install. Instead scrape the
        // stable releases page, whose "1Password for Mac <ver>" titles are
        // server-rendered and listed newest-first — the FIRST match is the current
        // stable build (the bare <h1> "1Password for Mac" has no version and is
        // skipped by the required \s+[0-9]). NOTE: HTML scrape — more brittle than
        // an API; refresh if it stops matching. Detection only; the same page is
        // also the ChangelogRecipe(com.1password.1password) source.
        VendorProbeRecipe(
            bundleID: "com.1password.1password",
            url: URL(string: "https://releases.1password.com/mac/stable/")!,
            mode: .responseBody,
            versionPattern: #"1Password for Mac\s+([0-9]+\.[0-9]+\.[0-9]+)"#,
            downloadURL: URL(string: "https://1password.com/downloads/mac/"),
            changelogURL: URL(string: "https://releases.1password.com/mac/stable/")),

        // Sublime Text 4 — self-updates, so it reaches us here. NOTE: HTML scrape
        // (no usable API: the /updates/.../updatecheck endpoint 404s and the cask
        // has no livecheck). The /download page is server-rendered: its latest
        // marker `<p class="latest"><i>Version:</i> Build 4200</p>` precedes the
        // descending history, so the FIRST "Build NNNN" is newest. CRITICAL:
        // capture the FULL "Build NNNN" string, not the bare 4-digit build — the
        // installed CFBundleShortVersionString is literally "Build 4200" (with the
        // space), and VersionComparator ranks a number above adjacent text, so a
        // bare "4200" vs "Build 4200" reads as a perpetual phantom update. Keeping
        // the "Build " prefix makes it compare like-for-like. Detection only.
        VendorProbeRecipe(
            bundleID: "com.sublimetext.4",
            url: URL(string: "https://www.sublimetext.com/download")!,
            mode: .responseBody,
            versionPattern: #"class="latest"><i>Version:</i>\s*(Build\s+4[0-9]{3})"#,
            downloadURL: URL(string: "https://www.sublimetext.com/download"),
            changelogURL: URL(string: "https://www.sublimetext.com/download")),

        // Sublime Merge — self-updates, so it reaches us here. NOTE: HTML scrape
        // (no usable API; mirrors the Sublime Text 4 recipe above — same vendor,
        // same page shape). The /download page's latest marker
        // `<p class="latest"><i>Version:</i> Build 2125</p>` precedes the descending
        // history, so the anchored "Build NNNN" is newest. CRITICAL: capture the
        // FULL "Build NNNN" string — installed CFBundleShortVersionString is
        // literally "Build 2125", and a bare "2125" would read as a perpetual
        // phantom update (VersionComparator ranks a number above adjacent text).
        // Builds are 2xxx (not 4xxx like Sublime Text); the class="latest" anchor
        // already makes it single-match. Detection only.
        VendorProbeRecipe(
            bundleID: "com.sublimemerge",
            url: URL(string: "https://www.sublimemerge.com/download")!,
            mode: .responseBody,
            versionPattern: #"class="latest"><i>Version:</i>\s*(Build\s+[0-9]{4})"#,
            downloadURL: URL(string: "https://www.sublimemerge.com/download"),
            changelogURL: URL(string: "https://www.sublimemerge.com/download")),

        // Plex (desktop, mac) — Plex's own downloads feed (plex.tv/api/downloads/
        // 6.json is the desktop product; 7.json is the separate PlexHTPC, and the
        // `plex` cask has no livecheck, so this is the clean source). Anchor to the
        // `MacOS` block and capture only the 3-component marketing version
        // (1.112.0), dropping the feed's full `1.112.0.359-0d79a49f`: the app's
        // CFBundleShortVersionString is the bare 1.112.0, and keeping the trailing
        // .359 would compare as +359 over a current install (VersionComparator
        // treats the missing 4th component as 0) — a permanent phantom update. The
        // MacOS block's top-level `version` precedes its `releases` array, so the
        // `[^}]*?` reaches it without crossing a `}` and never grabs the (earlier)
        // Windows block. Detection only — Plex desktop self-updates via Squirrel.
        VendorProbeRecipe(
            bundleID: "tv.plex.desktop",
            url: URL(string: "https://plex.tv/api/downloads/6.json")!,
            mode: .responseBody,
            versionPattern: #""MacOS"\s*:\s*\{[^}]*?"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"#,
            downloadURL: URL(string: "https://www.plex.tv/media-server-downloads/?cat=plex+desktop"),
            changelogURL: URL(string: "https://www.plex.tv/media-server-downloads/?cat=plex+desktop")),

        // Alfred 5 — Sparkle PLIST appcast (not RSS). Alfred has no Info.plist
        // SUFeedURL (the feed is configured in Alfred's own Preferences), so it
        // reaches us here rather than via SparkleAppcastSource — same situation as
        // the Codex/OrbStack neighbors. The manifest is a single-release plist: the
        // top-level <key>version</key><string> is the latest build (5.7.3),
        // unambiguous vs the descending "## Alfred X.Y.Z" history inside
        // changelogdata. One release listed → first match is correct. Detection
        // only — Alfred self-updates via Sparkle.
        VendorProbeRecipe(
            bundleID: "com.runningwithcrayons.Alfred",
            url: URL(string: "https://www.alfredapp.com/app/update5/general.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>version</key>\s*<string>([0-9][0-9.]*)</string>"#,
            downloadURL: URL(string: "https://www.alfredapp.com/"),
            changelogURL: URL(string: "https://www.alfredapp.com/changelog/")),

        // Shottr — its own JSON version check (the same endpoint baked into the app
        // binary: shottr.cc/api/version.json). NOT a Sparkle appcast — Shottr ships
        // none (no Info.plist SUFeedURL, /appcast.xml 404s), so it reaches us here.
        // `latestVersion` is the STABLE marketing version (1.9.1), equal to the
        // app's CFBundleShortVersionString. A `betaLatestVersion` also lives in the
        // body — the `"latestVersion"` anchor can't match the `"betaLatestVersion"`
        // key (different literal prefix), so a stable install is never offered the
        // beta build. Detection only — Shottr self-updates via its own .pkg updater.
        VendorProbeRecipe(
            bundleID: "cc.ffitch.shottr",
            url: URL(string: "https://shottr.cc/api/version.json")!,
            mode: .responseBody,
            versionPattern: #""latestVersion"\s*:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)?)""#,
            downloadURL: URL(string: "https://shottr.cc/"),
            changelogURL: URL(string: "https://shottr.cc/newversion.html")),

        // The Unarchiver (MacPaw) — DevMate Sparkle appcast. Like the Codex/Alfred
        // neighbors it carries no Info.plist SUFeedURL (DevMate configures the feed
        // internally), so it reaches us here. The version is the
        // `sparkle:shortVersionString` ATTRIBUTE on each <enclosure> (NOT an
        // element); the feed is descending (newest item first), so first match is
        // the latest. Detection only — self-updates via DevMate's Sparkle.
        // changelogURL is DevMate's release-notes page (pinned to a build number,
        // so it lags a release behind — cosmetic; theunarchiver.com has no stable
        // changelog path).
        VendorProbeRecipe(
            bundleID: "com.macpaw.site.theunarchiver",
            url: URL(string: "https://updates.devmate.com/com.macpaw.site.theunarchiver.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:shortVersionString="([0-9.]+)""#,
            downloadURL: URL(string: "https://theunarchiver.com/"),
            changelogURL: URL(string: "https://updates.devmate.com/releasenotes/147/com.macpaw.site.theunarchiver.html")),

        // Orion (Kagi) — official Sparkle appcast under the macOS-major flavor dir
        // (`26_0`, the same path the Homebrew cask download uses; the bare
        // /updates/appcast.xml is a STALE stub frozen at 1.0.0 — don't use it). The
        // feed lists releases ASCENDING, so selectHighest (not first match, which is
        // the oldest 0.99) picks the current build. We extract
        // `sparkle:shortVersionString` (MARKETING version, e.g. 1.0.8) — NOT
        // `sparkle:version` (the build, e.g. 147/147.1). A vendor probe can only
        // populate `shortVersion`, so UpdateChecker compares against the installed
        // CFBundleShortVersionString (1.0.8); feeding the build "147.1" would compare
        // 147 > 1 and invent a permanent phantom update. Trade-off: blind to a
        // build-only rebuild at an unchanged marketing version — the conservative,
        // never-lie choice. Detection only — Orion self-updates via Sparkle.
        VendorProbeRecipe(
            bundleID: "com.kagi.kagimacOS",
            url: URL(string: "https://cdn.kagi.com/updates/26_0/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+(?:\.[0-9]+)+)</sparkle:shortVersionString>"#,
            downloadURL: URL(string: "https://browser.kagi.com/"),
            changelogURL: URL(string: "https://browser.kagi.com/updates/orion-release-notes.html"),
            selectHighest: true),

        // Dropbox (desktop, mac) — the website's "latest" download link. A single
        // 302 from www.dropbox.com/download?plat=mac&full=1 lands on the versioned
        // package edge.dropboxstatic.com/dbx-releng/client/Dropbox%20<ver>.dmg, so
        // the version rides in the %20-encoded Location filename. The target is a
        // ~200 MB dmg, so don't follow — read the small 302 Location
        // (followRedirects:false). NOTE the scheme is 3-component (254.4.2518 =
        // 254/4/2518, not four) — the pattern is three numeric groups. Detection
        // only — Dropbox self-updates. (Homebrew cask has no livecheck; its
        // url/version confirm this host + build.)
        VendorProbeRecipe(
            bundleID: "com.getdropbox.dropbox",
            url: URL(string: "https://www.dropbox.com/download?plat=mac&full=1")!,
            mode: .redirectFilename,
            versionPattern: #"Dropbox(?:%20| )([0-9]+\.[0-9]+\.[0-9]+)\.dmg"#,
            downloadURL: URL(string: "https://www.dropbox.com/install")!,
            changelogURL: URL(string: "https://www.dropbox.com/release_notes")!,
            followRedirects: false),

        // MacUpdater — version is in an HTML comment marker on the product page.
        // NOTE: HTML scrape — more brittle than an API; refresh if it stops
        // matching.
        VendorProbeRecipe(
            bundleID: "com.corecode.MacUpdater",
            url: URL(string: "https://www.corecode.io/macupdater/")!,
            mode: .responseBody,
            versionPattern: #"<!--BEGINVERSION-->([0-9.]+)<!--ENDVERSION-->"#,
            changelogURL: URL(string: "https://www.corecode.io/macupdater/history3.html")),

        // (Surge needs no recipe here: it declares a Sparkle SUFeedURL, so the
        // higher-priority SparkleAppcastSource handles it, and `SurgeChannel`
        // retargets that feed to the release/beta appcast per the user's choice.)
    ]

    /// One OrbStack recipe for a given channel: same appcast, regex anchored to
    /// that `<sparkle:channel>` tag (newest-first → first match is correct), and
    /// the install enclosure pulled from the same channel block.
    private static func orbStackRecipe(_ channel: ReleaseChannel, tag: String) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "dev.kdrag0n.MacVirt",
            url: URL(string: "https://cdn-updates.orbstack.dev/arm64/appcast.new.xml")!,
            mode: .responseBody,
            versionPattern: #"(?s)<sparkle:channel>\#(tag)</sparkle:channel>(?:(?!</item>).)*?OrbStack_v([0-9.]+)_"#,
            changelogURL: URL(string: "https://docs.orbstack.dev/release-notes"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(?s)<sparkle:channel>\#(tag)</sparkle:channel>(?:(?!</item>).)*?<enclosure url="(https://cdn-updates\.orbstack\.dev/arm64/OrbStack_v[0-9.]+_[0-9]+_arm64\.dmg)""#),
                kind: .dmg),
            channel: channel)
    }
}
