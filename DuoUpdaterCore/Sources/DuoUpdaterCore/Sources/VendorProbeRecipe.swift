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
        /// `url` is a (small) ZIP whose version lives in a bundled Info.plist —
        /// for vendors whose only cheap version surface is a "stub installer"
        /// archive: we GET the zip, extract the named `entry`, parse it as a
        /// property list (binary or XML), and read `key` as the version, which
        /// `versionPattern` then validates. Needed because the value sits behind
        /// TWO layers — a deflate-compressed zip entry and a binary plist — that
        /// neither text-regex (`.responseBody`) nor `.redirectFilename` can reach.
        /// (Spotify: `SpotifyInstaller.zip` (1.8MB) → `Install Spotify.app`'s
        /// `CFBundleShortVersionString`, which tracks the latest client in lockstep.)
        case zipEntryPlist(entry: String, key: String)
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

    /// When true, the version this recipe extracts is the vendor's *build* number
    /// (the app's `CFBundleVersion`), NOT its marketing `CFBundleShortVersionString`.
    /// The source then routes it into `RemoteVersion.version` so the engine compares
    /// it against the installed app's `buildVersion` — the only field that matches.
    ///
    /// Needed for vendors whose download URL / manifest carries the build but whose
    /// app reports a *shorter* marketing version: Microsoft Office ships
    /// `Microsoft_Word_16.109.26053122_Installer.pkg` (build `16.109.26053122`)
    /// while the installed bundle's `CFBundleShortVersionString` is `16.109.3`.
    /// Comparing the build against the marketing version would report `26053122 > 3`
    /// — a permanent phantom "update available" that never clears. Leave false
    /// whenever the extracted version is the same scheme the app advertises
    /// (the common case: Teams, OneDrive, Sparkle appcasts all report the full
    /// version as their marketing string).
    public let versionIsBuild: Bool

    /// Optional regex (capture group 1) for a HUMAN-READABLE version to *show*,
    /// when the compared value (`versionPattern`) is an ugly build id. Pulled from
    /// the same response body and routed into `RemoteVersion.shortVersion` for
    /// display only — the build still drives the comparison via `version`, so the
    /// row reads "2026.1.2 → 2026.1.2 RC 1" instead of "2026.1.2 → AI-261.…".
    /// Only meaningful with `versionIsBuild`; nil → show the build itself.
    /// Like every probe pattern it takes the FIRST match, so it must live in the
    /// same (newest-first) entry the build pattern matches, or the two desync.
    public let displayVersionPattern: String?

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
        versionIsBuild: Bool = false,
        displayVersionPattern: String? = nil,
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
        self.versionIsBuild = versionIsBuild
        self.displayVersionPattern = displayVersionPattern
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
/// Known-unfeasible (left out, would only mislead): Paste (no public version
/// API; direct build outruns MAS), WeLink (Zoom-SDK private updater),
/// RunnerNotify / STCM Editor (ad-hoc internal builds), Brave and
/// Feishu/Lark (their `CFBundleShortVersionString` is Chromium-major-prefixed —
/// e.g. Brave `148.1.90.128`, Feishu `131.0.6778.268` — but every vendor feed
/// only exposes the bare app version `1.90.128` / `7.69.9`, which can't be made
/// to compare in the same scheme, so any probe would phantom-update or
/// phantom-downgrade; don't re-attempt without a Chromium-major source). Android
/// Studio's Stable, Canary, and Beta tracks all share `com.google.android.studio`;
/// the install's channel is read from the bundle filename (`ReleaseChannel.detect`
/// step 0.5) and `VendorProbeSource`'s channel gate routes each to its own recipe
/// below — Stable to developer.android.com/studio, Canary/Beta to the official
/// releases-list JSON (compared on the `build` field via `versionIsBuild`).
///
/// GitHub-released apps are handled by `GitHubReleasesSource`, not here.
public enum VendorProbeRegistry {
    public static let recipes: [VendorProbeRecipe] = [
        // WhatsApp — the downloads page's link 302s to a versioned dmg on fbcdn:
        // `…/WhatsApp-2.26.31.27.dmg`. Read the Location header rather than
        // following it: the target IS the ~259 MB installer, so a HEAD-follow would
        // be answered by the CDN with the real payload's headers and any GET would
        // fetch it outright.
        //
        // VERSION SCHEME TRAP: the filename carries a leading `2.` the app does not
        // — the bundle reports `26.22.20`, the file is `WhatsApp-2.26.31.27.dmg`.
        // Capturing the whole thing would compare `2.26.31.27` against `26.22.20`
        // and conclude the installed copy is NEWER, hiding every update forever.
        // The pattern deliberately anchors on `WhatsApp-2.` and takes only the three
        // segments after it.
        //
        // One-click verified 2026-08-09 by mounting the 26.31.27 image: it holds
        // `WhatsApp.app` whose bundle id and Team (57T9237FN3) match the installed
        // copy, its `CFBundleShortVersionString` equals what the probe reports, and
        // `spctl` accepts it as "Notarized Developer ID". WhatsApp also updates
        // itself, so this row usually just confirms what already happened — but when
        // its own updater is behind, the swap is ours to make.
        VendorProbeRecipe(
            bundleID: "net.whatsapp.WhatsApp",
            url: URL(string: "https://web.whatsapp.com/desktop/mac_native/release/?configuration=Release&src=whatsapp_downloads_desktop_page")!,
            mode: .redirectFilename,
            versionPattern: #"WhatsApp-2\.([0-9]+\.[0-9]+\.[0-9]+)\.dmg"#,
            changelogURL: URL(string: "https://web.whatsapp.com/desktop/mac_native/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://web.whatsapp.com/desktop/mac_native/release/?configuration=Release&src=whatsapp_downloads_desktop_page")!),
                kind: .dmg),
            followRedirects: false),

        // UURemote (网易UU远程) — no Sparkle, no public version JSON, and the
        // product page is client-rendered so the HTML carries no version at all.
        // The one machine-readable surface is the download button's endpoint, found
        // in the page's markup: NetEase's release API 302s to the versioned package
        // (`uuyc_4.35.0.pkg`), which is the version the app reports.
        //
        // The Homebrew cask can't cover this: its provenance gate (correctly) only
        // adopts apps brew actually installed, and this one was installed directly.
        //
        // One-click verified 2026-08-09 on the 4.35.0 package: `pkgutil
        // --check-signature` reports "Developer ID Installer: Hangzhou Bobo
        // Technology Co Ltd (PU9BNSBJW7)" — the same team as the installed bundle —
        // notarized, with a trusted timestamp. A `.pkg` hands off to macOS's own
        // installer, so the user still confirms it there (same flow as ToDesk and
        // AweSun); the install spec re-resolves the redirect at download time so it
        // always fetches the current package, not this version's.
        VendorProbeRecipe(
            bundleID: "com.netease.uuremote",
            url: URL(string: "https://api.nrd.nie.163.com/api/v1/release/dl/4?channel=gwqd")!,
            mode: .redirectFilename,
            versionPattern: #"uuyc_([0-9]+(?:\.[0-9]+)+)\.pkg"#,
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://api.nrd.nie.163.com/api/v1/release/dl/4?channel=gwqd")!),
                kind: .pkg),
            followRedirects: false),

        // Alfred, PRE-RELEASE channel — the missing half of the pair below.
        //
        // A user who ticks "Pre-releases" in Alfred's own Update preferences is
        // resolved to `.beta` by `AlfredChannel`, and the channel guard then refuses
        // the stable recipe — correctly, but with nothing left to answer, so the row
        // read "Failed" indefinitely. (The Sparkle path couldn't cover for it: that
        // binding pointed at `alfredapp.com/appcast.xml` and `/prerelease.xml`, both
        // of which now 404 — the unreadable `SparkleError error 0` in the logs.)
        //
        // Same plist shape as stable, different endpoint. The two frequently serve
        // the SAME build — both were 5.7.3 (2320) here — so being on beta doesn't by
        // itself mean a newer version is on offer.
        VendorProbeRecipe(
            bundleID: AlfredChannel.bundleID,
            url: URL(string: "https://www.alfredapp.com/app/update5/prerelease.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>version</key>\s*<string>([0-9]+(?:\.[0-9]+)+)</string>"#,
            changelogURL: URL(string: "https://www.alfredapp.com/changelog/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>location</key>\s*<string>(https://[^<]+\.tar\.gz)</string>"#),
                kind: .tarGz),
            channel: .beta),

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

        // VS Code Insiders — same update API on the `insider` track, its own
        // bundle id `com.microsoft.VSCodeInsiders` (display name "Code - Insiders",
        // so `ReleaseChannel.detect` reads the standalone "Insiders" word → .preview;
        // the bundle id has no `.insiders`/`-insiders` suffix to match on). CRUCIAL:
        // the installed `CFBundleShortVersionString` carries the `-insider` suffix
        // ("1.124.0-insider"), so the version pattern MUST keep it too — the stable
        // `\d+\.\d+\.\d+` would extract a bare "1.124.0" and read every install as
        // perpetually out-of-date. `name` only bumps on the ~monthly minor (the
        // daily builds differ by commit hash, which the Info.plist doesn't expose),
        // so detection is monthly-granular; Insiders self-updates daily anyway, and
        // comparing on the suffixed name can only ever say "up to date" or a real
        // minor bump — never a phantom update. One-click mirrors stable (zip swap).
        VendorProbeRecipe(
            bundleID: "com.microsoft.VSCodeInsiders",
            url: URL(string: "https://update.code.visualstudio.com/api/update/darwin-arm64/insider/latest")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+-insider)""#,
            changelogURL: URL(string: "https://code.visualstudio.com/updates"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://update.code.visualstudio.com/latest/darwin-arm64/insider")!),
                kind: .zip),
            channel: .preview),

        // IntelliJ IDEA — JetBrains data services. The `YYYY.` prefix is what keeps
        // this off the 2-component `majorVersion` field; the segment count must NOT
        // be pinned. It was pinned to exactly three (`YYYY.x.y`) and JetBrains then
        // shipped a fourth — `"version": "2026.2.0.1"` — so the anchored pattern
        // stopped matching and the row silently fell to "unknown" with the probe
        // reporting "resolved no version". Accept one to three segments after the
        // year. Only consulted when Toolbox isn't managing it (a website install);
        // the same JSON carries the aarch64 DMG direct link, so we install in place.
        // No inline sha256 (the API gives only a checksum *link*), so we lean on the
        // mandatory Team ID signature gate — same posture as VLC's DMG. Apple
        // Silicon (macM1) only.
        VendorProbeRecipe(
            bundleID: "com.jetbrains.intellij",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]{4}(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://www.jetbrains.com/idea/whatsnew/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""macM1"\s*:\s*\{[^}]*?"link"\s*:\s*"([^"]+\.dmg)""#),
                kind: .dmg)),

        // IntelliJ IDEA EAP — same data services API on the `eap` channel. The EAP
        // marketing "version" stays "2026.2" across many builds, so comparing it
        // would never detect a build bump; we compare on the `build` (262.x) via
        // `versionIsBuild`. The installed bundle's CFBundleVersion is prefixed
        // ("IU-262.6653.22") while the API build is bare ("262.7132.23") — the
        // source strips the product-code prefix so they compare in one namespace.
        // `channel: .preview` matches the `-EAP` bundle id (see ReleaseChannel). Like
        // stable, only fires when Toolbox isn't installed.
        VendorProbeRecipe(
            bundleID: "com.jetbrains.intellij-EAP",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=eap")!,
            mode: .responseBody,
            versionPattern: #""build"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://www.jetbrains.com/idea/whatsnew/"),
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""macM1"\s*:\s*\{[^}]*?"link"\s*:\s*"([^"]+\.dmg)""#),
                kind: .dmg),
            channel: .preview),

        // JetBrains Toolbox — uses the 4-component `build`, which matches the
        // app's CFBundleShortVersionString (e.g. 3.4.3.81140). The same releases
        // JSON carries the aarch64 dmg under `downloads.macM1`, so we install in
        // place — same shape as the IntelliJ recipes above. No inline sha256 (the
        // API gives only a `checksumLink`), so we lean on the mandatory Team ID
        // gate: the dmg is notarized under 2ZEFAR8TH3 (JetBrains s.r.o.). The
        // `[^}]*?` lazily skips within the `macM1` object to its `link`; `macM1`'s
        // link is the arm64 build, so no `-arm64` anchor is needed here. Apple
        // Silicon only. (Toolbox self-updates, but this is a best-effort one-click
        // with the Team gate as backstop — it never force-kills; a running Toolbox
        // is quit and relaunched by VendorInstaller like any other in-place dmg.)
        VendorProbeRecipe(
            bundleID: "com.jetbrains.toolbox",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release")!,
            mode: .responseBody,
            versionPattern: #""build"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://blog.jetbrains.com/toolbox-app/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""macM1"\s*:\s*\{[^}]*?"link"\s*:\s*"([^"]+\.dmg)""#),
                kind: .dmg)),

        // Google Chrome — official VersionHistory API (page_size=1, desc).
        //
        // All four channels install from Google's own permanent per-channel dmg
        // (`dl.google.com/chrome/mac/universal/<channel>/…`), verified 2026-08-09:
        // each holds the matching bundle id, Team EQHXZ8M8AV, spctl "Notarized
        // Developer ID", and a version in the same 4-part form the API reports.
        //
        // Chrome self-updates through Keystone, which is NOT a reason to withhold
        // one-click — that is what `vendorInstallPolicy` is for, and its own settings
        // copy names Chrome. Keystone keeps managing whatever bundle is on disk; a
        // swap to a newer build does not confuse it. Under the default "defer while
        // running", a running Chrome is brought forward to update itself instead.
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
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg")!),
                kind: .dmg)),

        // Google Chrome — Beta / Dev / Canary channels. Each ships its OWN bundle
        // id (`com.google.Chrome.beta` / `.dev` / `.canary`) and is detected as
        // its own `ReleaseChannel`, so the channel gate routes each install to its
        // matching feed — a Beta install never gets the Stable version and vice
        // versa. Same rollout-aware `fraction:1` pattern as Stable (the
        // VersionHistory API is identical per channel; Canary publishes every
        // build at fraction 1). Each installs from its own permanent dmg — see the
        // Stable note above for why Keystone is not a reason to withhold that.
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.beta",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/beta/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://dl.google.com/chrome/mac/universal/beta/googlechromebeta.dmg")!),
                kind: .dmg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.dev",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/dev/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://dl.google.com/chrome/mac/universal/dev/googlechromedev.dmg")!),
                kind: .dmg),
            channel: .dev),
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.canary",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/canary/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://dl.google.com/chrome/mac/universal/canary/googlechromecanary.dmg")!),
                kind: .dmg),
            channel: .canary),

        // Brave Browser — Beta / Nightly. Sparkle appcast per channel and per ARCH.
        // Distinct bundle ids (`com.brave.Browser.beta` / `.nightly`) so the channel
        // gate routes each install to its own feed.
        //
        // COMPARE ON THE BUILD, not the marketing string. The feed's
        // `sparkle:shortVersionString` is Brave's own 4-part version ("1.94.104.0")
        // while the installed bundle reports a CHROMIUM-prefixed one
        // ("151.1.94.104"). Comparing those puts 1 against 151 and concludes the
        // installed copy is newer — so the row read "up to date" forever and Brave
        // Beta/Nightly could never surface an update. `sparkle:version` ("194.104")
        // is exactly the bundle's `CFBundleVersion`, so that's the pair that lines
        // up; `displayVersionPattern` keeps the human-readable string on screen.
        //
        // The `-arm64` feed is deliberate: the plain path serves x64 dmgs only
        // (`Brave-Browser-Beta-x64.dmg`). Both tracks carry the same version, so this
        // changes the artifact, not the verdict. Verified 2026-08-09 on beta 194.104
        // and nightly 195.47 — Team KL8N8XSYF4, notarized, ids matching.
        VendorProbeRecipe(
            bundleID: "com.brave.Browser.beta",
            url: URL(string: "https://updates.bravesoftware.com/sparkle/Brave-Browser/beta-arm64/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:version="([0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://brave.com/latest/")!,
            versionIsBuild: true,
            displayVersionPattern: #"sparkle:shortVersionString="([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://[^"]+Brave-Browser-Beta-arm64\.dmg)""#),
                kind: .dmg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "com.brave.Browser.nightly",
            url: URL(string: "https://updates.bravesoftware.com/sparkle/Brave-Browser/nightly-arm64/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:version="([0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://brave.com/latest/")!,
            versionIsBuild: true,
            displayVersionPattern: #"sparkle:shortVersionString="([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://[^"]+Brave-Browser-Nightly-arm64\.dmg)""#),
                kind: .dmg),
            channel: .nightly),

        // Vivaldi — Snapshot (preview) track. Sparkle appcast on the `snapshot`
        // channel. Independent bundle id (`com.vivaldi.Vivaldi.snapshot`) so the
        // channel gate routes it automatically. `sparkle:shortVersionString` carries
        // the marketing version (e.g. "8.1.4063.3"), and here it equals the bundle's
        // CFBundleShortVersionString exactly — no scheme mismatch to work around,
        // unlike the Brave feeds above.
        //
        // One-click verified 2026-08-09 on 8.2.4126.4: the enclosure is a universal
        // `.tar.xz` holding `Vivaldi Snapshot.app`, bundle id
        // com.vivaldi.Vivaldi.snapshot, Team 4XF3XNRN6Y, spctl "Notarized Developer
        // ID". `.tarGz` covers xz — see the ImageOptim note.
        VendorProbeRecipe(
            bundleID: "com.vivaldi.Vivaldi.snapshot",
            url: URL(string: "https://update.vivaldi.com/update/1.0/snapshot/mac/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)</sparkle:shortVersionString>"#,
            changelogURL: URL(string: "https://vivaldi.com/blog/desktop/")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://downloads\.vivaldi\.com/[^"]+\.tar\.xz)""#),
                kind: .tarGz),
            channel: .preview),

        // Microsoft Edge — Stable / Beta / Dev. One enterprise endpoint lists all
        // products; each per-channel pattern scopes to that Product's first
        // (newest) MacOS release. Distinct bundle ids (`…edgemac[.Beta/.Dev]`) so
        // the channel gate routes each install to its own version. Edge self-updates
        // via Microsoft AutoUpdate; like Office there's no rollout-jump risk (the
        // CDN serves the GA build), so Stable gets a one-click pkg from the official
        // "latest" fwlink (linkid=2093504 → MicrosoftEdge-<ver>.pkg, same 4-component
        // ProductVersion scheme as detection). Beta/Dev ALSO get a one-click pkg,
        // but from a different place than Stable: the same enterprise JSON lists
        // each channel's MacOS pkg under `Artifacts[].Location`, so we scope the
        // install pattern to that Product's first (newest) MacOS release — exactly
        // parallel to the versionPattern — and the `\.pkg` anchor skips the sibling
        // `.plist` artifact. The pkg is notarized under Microsoft's Developer ID
        // Installer (UBF8T346G9), same as Stable, so it clears the signature gate.
        // The channel gate still routes each pkg to its own bundle id. (Edge Canary
        // isn't carried by this enterprise API, so it stays "unknown" rather than
        // mis-served.)
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Stable".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoft.com/edge/download"),
            changelogURL: URL(string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnotes"),
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/?linkid=2093504")!),
                kind: .pkg)),
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac.Beta",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Beta".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoftedgeinsider.com/download"),
            changelogURL: URL(string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnotes-beta-channel"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(?s)"Product"\s*:\s*"Beta".*?"Platform"\s*:\s*"MacOS".*?"Location"\s*:\s*"(https://[^"]+\.pkg)""#),
                kind: .pkg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac.Dev",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Dev".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoftedgeinsider.com/download"),
            changelogURL: URL(string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnotes-dev-channel"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(?s)"Product"\s*:\s*"Dev".*?"Platform"\s*:\s*"MacOS".*?"Location"\s*:\s*"(https://[^"]+\.pkg)""#),
                kind: .pkg),
            channel: .dev),

        // Microsoft Teams — Microsoft's config/v1 version API (same family as
        // VS Code & Edge). The "WebView2Canary" track is the production/Public R4
        // build despite the confusing name (Homebrew's `microsoft-teams` cask
        // tracks this same 4-component version). Teams self-updates via Microsoft
        // AutoUpdate (com.microsoft.autoupdate2). The full version is the app's
        // marketing string, so this is a normal (non-build) recipe. The install
        // buildLink MUST be anchored to the WebView2Canary block: the JSON lists a
        // separate "WebView2" track first whose (lower) buildLink a bare
        // "buildLink" pattern would grab — installing a different track than the
        // one we detected.
        VendorProbeRecipe(
            bundleID: "com.microsoft.teams2",
            url: URL(string: "https://config.teams.microsoft.com/config/v1/MicrosoftTeams/1?environment=prod&audienceGroup=general&teamsRing=general&agent=TeamsBuilds")!,
            mode: .responseBody,
            versionPattern: #""WebView2Canary":\{"macOS":\{"latestVersion":"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-teams/download-app")!,
            changelogURL: URL(string: "https://support.microsoft.com/en-us/office/what-s-new-in-microsoft-teams-d7092a6d-c896-424c-b362-a472d5f105de")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""WebView2Canary":\{"macOS":\{"latestVersion":"[^"]*","buildLink":"([^"]+MicrosoftTeams\.pkg)""#),
                kind: .pkg)),

        // Microsoft OneDrive — Microsoft's "latest" download fwlink. A single 302
        // lands on a versioned .pkg URL on oneclient.sfx.ms. The version is a
        // 4-component path segment (e.g. `26.078.0426.0002`), not a filename, so
        // followRedirects:false reads the Location header instead of lastPathComponent.
        //
        // Capture only the FIRST THREE components: the installed bundle's
        // CFBundleShortVersionString is exactly those (`26.078.0426`), while the
        // 4th path component is a build revision that the marketing version omits —
        // and CFBundleVersion uses a *different* scheme (`26078.0426.0002`, first
        // two merged), so neither installed field matches the full 4-component path.
        // Comparing the full path version would read the trailing `.0002` as newer
        // than `26.078.0426` and phantom-update forever. (Verified against a real
        // install: short `26.078.0426`, build `26078.0426.0002`.) A genuine release
        // bumps one of the first three, so first-3 detection stays correct; the only
        // blind spot is a pure 4th-component re-spin under an unchanged marketing
        // version — the safe direction (a missed check, never a phantom), and
        // OneDrive self-updates via OneDriveStandaloneUpdaterDaemon anyway.
        // Install follows the same fwlink.
        VendorProbeRecipe(
            bundleID: "com.microsoft.OneDrive",
            url: URL(string: "https://go.microsoft.com/fwlink/?linkid=823060")!,
            mode: .redirectFilename,
            versionPattern: #"/Installers/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onedrive/download")!,
            changelogURL: URL(string: "https://support.microsoft.com/en-us/office/onedrive-release-notes-845dcf18-f921-435e-bf28-4e24b95e5fc0")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/?linkid=823060")!),
                kind: .pkg),
            followRedirects: false),

        // Microsoft PowerPoint — Office suite, unified version. The fwlink 302s to
        // a versioned .pkg on the Office CDN. MAU-managed. The pkg filename carries
        // the BUILD (`16.109.26053122`, = the app's CFBundleVersion), not the
        // shorter marketing CFBundleShortVersionString (`16.109.3`), so
        // versionIsBuild routes it to the build-vs-build comparison — otherwise the
        // build would read as "newer" than the marketing version forever.
        VendorProbeRecipe(
            bundleID: "com.microsoft.Powerpoint",
            url: URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525136")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/powerpoint")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
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
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
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
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
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
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
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
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
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
            changelogURL: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            selectHighest: true,
            // `bodyPatternLast`, not `bodyPattern`: this appcast is ASCENDING, so the
            // first enclosure is 6.0.0 and the newest is the final one — the same
            // reason `selectHighest` is set for the version. Taking the first match
            // would install a two-year-old build over a current one.
            //
            // Verified 2026-08-09 on 6.6.2: `Bartender 6.app` in the archive, bundle
            // id com.surteesstudios.Bartender, Team 24J875RH8J, spctl "Notarized
            // Developer ID". (Note the older entries are served from macbartender.com
            // and the recent ones from downloads.macbartender.com — the pattern
            // accepts either host.)
            install: VendorInstallSpec(
                urlSource: .bodyPatternLast(
                    #"<enclosure[^>]*url="(https://[^"]*macbartender\.com/[^"]+\.zip)""#),
                kind: .zip)),

        // ImageOptim — Sparkle appcast carrying only the latest release
        // (descending, single item). Version in sparkle:shortVersionString.
        // Detection-only; SparkleAppcastSource takes priority if SUFeedURL present.
        VendorProbeRecipe(
            bundleID: "net.pornel.ImageOptim",
            url: URL(string: "https://imageoptim.com/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:shortVersionString="([0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://imageoptim.com/changelog.html")!,
            // One-click verified 2026-08-09 on 1.9.3: `ImageOptim.app` in the
            // archive, bundle id net.pornel.ImageOptim, Team 59KZTZA4XR, accepted by
            // spctl. The enclosure is a `.tar.xz`, which `.tarGz` handles despite the
            // name — `VendorInstaller` renames by kind and `ArchiveExtractor` runs
            // `tar -xf` with no compression flag, so tar sniffs xz itself (checked by
            // extracting a deliberately misnamed copy).
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://imageoptim\.com/[^"]+\.tar\.xz)""#),
                kind: .tarGz)),

        // Firefox — Mozilla's `product-details` endpoint carries every channel's
        // current version in one JSON. Release, Beta and ESR all ship as
        // `org.mozilla.firefox`; the channel is told apart by `application.ini`
        // RemotingName (`firefox`/`firefox-beta`/`firefox-esr` — see
        // `ReleaseChannel`), NOT the version suffix, because the installed
        // `CFBundleShortVersionString` DROPS the `b`/`esr` (verified on real
        // bundles 2026-06-04: Beta reports `152.0`, ESR `140.11.0`). So three
        // recipes share that bundle id and are picked by the install's detected
        // channel. Developer Edition (`org.mozilla.firefoxdeveloperedition`,
        // RemotingName `firefox-dev`) and Nightly (`org.mozilla.nightly`) have
        // their own ids. The captured version KEEPS the feed's `bN`/`esr` form: it
        // sorts as a pre-release (never phantoms against the suffix-less install)
        // while a real bump still compares newer. One-click: identical mechanism to
        // Thunderbird — `download.mozilla.org/?product=…-latest&os=osx` 302→ the
        // per-channel `.dmg` (verified 2026-06-17: firefox-latest 152.0,
        // -beta-latest 152.0b10, -esr-latest 140.12.0esr, -devedition-latest
        // 152.0b10, -nightly-latest 154.0a1). All Mozilla-signed (Team `43AQ936H96`),
        // so VendorInstaller's same-Team gate is satisfied / fails closed. Note Dev
        // Edition's product code is `firefox-devedition-latest` (its dmg lives under
        // /pub/devedition/, not /pub/firefox/).
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_FIREFOX_VERSION"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/notes/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-latest&os=osx&lang=en-US")!),
                kind: .dmg)),
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_FIREFOX_RELEASED_DEVEL_VERSION"\s*:\s*"([0-9]+\.[0-9]+b[0-9]+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/channel/desktop/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/beta/notes/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-beta-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""FIREFOX_ESR"\s*:\s*"([0-9]+(?:\.[0-9]+)+esr)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/enterprise/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/organizations/notes/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-esr-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .esr),
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefoxdeveloperedition",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""FIREFOX_DEVEDITION"\s*:\s*"([0-9]+\.[0-9]+b[0-9]+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/developer/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/beta/notes/"),
            // Developer Edition tracks the Beta train (version is a `bN`) but has
            // its own bundle id and RemotingName `firefox-dev`, so the detector
            // classifies it `.dev` — the channel its recipe must target.
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-devedition-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .dev),
        VendorProbeRecipe(
            bundleID: "org.mozilla.nightly",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""FIREFOX_NIGHTLY"\s*:\s*"([0-9]+\.[0-9]+a[0-9]+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/channel/desktop/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/nightly/notes/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-nightly-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .nightly),

        // Thunderbird — same Mozilla `product-details` mechanism. Channel routing
        // is by `application.ini` RemotingName (see `ReleaseChannel`), NOT the
        // version suffix: the installed `CFBundleShortVersionString` DROPS the
        // `b`/`esr` suffix (verified on real bundles 2026-06-04). Bundle ids differ
        // per channel — Release & ESR share `org.mozilla.thunderbird`, Beta is
        // `org.mozilla.thunderbirdbeta`, Daily is `org.mozilla.thunderbird-daily`.
        // The probe still captures the feed's full `bN`/`esr` form: it sorts as a
        // pre-release (< the suffix-less installed version) so it never phantoms;
        // a real version bump (140.11.1→140.12.0esr) still compares newer.
        // One-click: Mozilla's `download.mozilla.org/?product=…-latest&os=osx`
        // 302-redirects to the per-channel `.dmg` on its CDN (verified 2026-06-17:
        // thunderbird-latest → 152.0, -beta-latest → 152.0b4, -esr-latest →
        // 140.12.0esr, -nightly-latest → 154.0a1). Every channel is signed by
        // Mozilla Corporation (Team `43AQ936H96`), so the VendorInstaller same-Team
        // gate is satisfied and fails closed if Mozilla ever rotates. Best-effort
        // in-place dmg swap on top of Thunderbird's own self-updater.
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_THUNDERBIRD_VERSION"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=thunderbird-latest&os=osx&lang=en-US")!),
                kind: .dmg)),
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbirdbeta",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_THUNDERBIRD_DEVEL_VERSION"\s*:\s*"([0-9]+\.[0-9]+b[0-9]+)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/channel/desktop/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=thunderbird-beta-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""THUNDERBIRD_ESR"\s*:\s*"([0-9]+(?:\.[0-9]+)+esr)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/enterprise/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=thunderbird-esr-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .esr),
        // Daily/Nightly has NO changelogURL on purpose: thunderbird.net publishes
        // no nightly release notes (every /<ver>/releasenotes/ 404s) and no
        // ChangelogRecipe can target it, so pointing changelogURL at the *stable*
        // releases index would embed an unrelated stable page for a nightly user.
        // Leaving it nil makes the detail pane show the honest "No release notes"
        // empty state (with a download link) instead — better than a wrong page.
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird-daily",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_THUNDERBIRD_NIGHTLY_VERSION"\s*:\s*"([0-9]+\.[0-9]+a[0-9]+)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/channel/desktop/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=thunderbird-nightly-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .nightly),

        // Warp — Preview / Dev. One JSON lists every channel's version, each tagged
        // with the channel name in its suffix (`…preview_01`), so a per-channel
        // pattern is unambiguous. Channels ship as separate bundle ids
        // (`dev.warp.Warp-Preview`, …) — the Stable build is the existing
        // `dev.warp.Warp-Stable` recipe above. We extract the bare date-version
        // (dropping the `v` prefix and `.<channel>_NN` suffix) to match the form
        // Stable already compares against.
        //
        // PREVIEW installs one-click; DEV deliberately does not. `app.warp.dev/
        // download?package=dmg&channel=preview` really does serve WarpPreview.app
        // (verified 2026-08-09: dev.warp.Warp-Preview, Team 2BBY89MBSN, notarized,
        // version matching the JSON). The same URL with `channel=dev` ignores the
        // parameter and hands back **Warp.app / dev.warp.Warp-Stable** — wiring that
        // would install Stable over a Dev install, the cross-channel swap the whole
        // channel gate exists to prevent. Note the Content-Type on both is
        // `text/html` despite the body being a 300 MB disk image; don'"'"'t trust it.
        //
        // The JSON still lists `beta` and `canary`, but Warp abandoned both tracks
        // (beta froze at 2024-12, canary at 2022-09 — see 2026-06-04 audit), so we
        // carry NO recipe for them: probing would only ever surface a years-stale
        // "latest", worse than the clean "unknown" an installed Warp-Beta/Canary
        // now gets. Bundle-id-suffix detection still tags such an install for the
        // UI; it just has no version source.
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Preview",
            url: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.preview_[0-9]+""#,
            changelogURL: URL(string: "https://docs.warp.dev/changelog"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://app.warp.dev/download?package=dmg&channel=preview")!),
                kind: .dmg),
            channel: .preview),
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Dev",
            url: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.dev_[0-9]+""#,
            downloadURL: URL(string: "https://www.warp.dev/download"),
            changelogURL: URL(string: "https://docs.warp.dev/changelog"),
            channel: .dev),

        // Signal — Stable + Beta. electron-builder feeds (one per channel). Stable
        // ships `org.whispersystems.signal-desktop`; Beta is a separate
        // "Signal Beta.app" (detected as `.beta` from its name). Signal self-updates
        // via electron-updater; one-click is best-effort on top of that. The same
        // yml we probe lists a **universal** `.dmg` (alongside per-arch zips) and we
        // resolve its filename against `updates.signal.org/desktop/`.
        //
        // Two per-channel gotchas, both found 2026-08-09:
        //
        // 1. The filenames are NOT the same shape across channels: stable is
        //    `signal-desktop-mac-universal-8.22.0.dmg`, beta carries an extra
        //    segment — `signal-desktop-beta-mac-universal-8.23.0-beta.1.dmg`. Each
        //    pattern is pinned to its own channel's spelling rather than made
        //    optional, so neither feed's pattern can resolve the other channel's
        //    build. A rename here degrades to detection-only *silently* (a probe
        //    that resolves no install URL is an error nowhere), so the install-plan
        //    test is what has to catch it — that's why both ids are listed there.
        //
        // 2. NO checksumPattern, deliberately. The yml's `sha512`/`size` describe
        //    the dmg as electron-builder emitted it, *before* Signal's CI signs and
        //    staples it; the CDN serves the stapled file (+2563 bytes on both
        //    channels), so the feed hash can never match the bytes we download and a
        //    checksum gate would abort every install. (Typeless reads a structurally
        //    identical feed with delta 0 — this is Signal's pipeline, not
        //    electron-builder's, so don't "fix" it by copying Typeless.) Integrity
        //    still rests on VendorInstaller's mandatory gates, verified against both
        //    real dmgs: notarized Developer ID, Team U68MSDN6DR on both channels,
        //    and a signed bundle id that pins each channel to its own install.
        VendorProbeRecipe(
            bundleID: "org.whispersystems.signal-desktop",
            url: URL(string: "https://updates.signal.org/desktop/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://signal.org/download/"),
            changelogURL: URL(string: "https://github.com/signalapp/Signal-Desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(signal-desktop-mac-universal-[^\s]+\.dmg)"#,
                    base: URL(string: "https://updates.signal.org/desktop/")!),
                kind: .dmg)),
        VendorProbeRecipe(
            bundleID: "org.whispersystems.signal-desktop-beta",
            url: URL(string: "https://updates.signal.org/desktop/beta-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://signal.org/download/"),
            changelogURL: URL(string: "https://github.com/signalapp/Signal-Desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(signal-desktop-beta-mac-universal-[^\s]+\.dmg)"#,
                    base: URL(string: "https://updates.signal.org/desktop/")!),
                kind: .dmg),
            channel: .beta),

        // Typeless (now.typeless.desktop) — AI voice dictation, Electron app that
        // self-updates via electron-updater (Squirrel.Mac). No Sparkle feed in
        // Info.plist; the Homebrew cask is `auto_updates true` so brew never answers
        // — the only public "latest version" surface is the electron-builder feed.
        // Single stable channel (no beta/canary anywhere). The vendor splits by arch:
        // `arm64-mac.yml` for Apple Silicon (what we probe), `latest-mac.yml` for x64.
        // The feed's `version` is the marketing version (1.8.0) and matches the
        // installed app's CFBundleShortVersionString exactly (build is 1.8.0.109 — we
        // do NOT compare against that), so no versionIsBuild. One-click: the same yml
        // lists `Typeless-<ver>-arm64.dmg`; we resolve its filename against
        // typeless-static.com/desktop-release/ and verify the dmg's base64 sha512 from
        // the line right after its `url:` — on top of VendorInstaller's mandatory
        // same-Team gate (installed Team 947QKAND4W). No public changelog page exists.
        VendorProbeRecipe(
            bundleID: "now.typeless.desktop",
            url: URL(string: "https://typeless-static.com/desktop-release/arm64-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://typeless.com/"),
            changelogURL: URL(string: "https://www.typeless.com/help/release-notes/macos"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Typeless-[^\s]+-arm64\.dmg)"#,
                    base: URL(string: "https://typeless-static.com/desktop-release/")!),
                kind: .dmg,
                checksumPattern: #"Typeless-[^\n]+-arm64\.dmg\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#)),

        // Element — Stable + Nightly, split bundle ids (`im.riot.app` vs
        // `im.riot.nightly` — verified 2026-06-04 against a real Nightly bundle;
        // the earlier `io.element.nightly` guess never matched and the probe
        // silently missed). `currentRelease` is the latest version (semver for
        // Stable, a `YYYYMMDDNN` build stamp for Nightly). One-click: the same
        // releases.json nests the installer under `updateTo.url` — the
        // `Element[-| Nightly-]<ver>-universal-mac.zip` on packages.element.io. We
        // capture that absolute zip url directly (each channel from its own feed).
        VendorProbeRecipe(
            bundleID: "im.riot.app",
            url: URL(string: "https://packages.element.io/desktop/update/macos/releases.json")!,
            mode: .responseBody,
            versionPattern: #""currentRelease"\s*:\s*"([^"]+)""#,
            downloadURL: URL(string: "https://element.io/download"),
            changelogURL: URL(string: "https://github.com/element-hq/element-desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(https://packages\.element\.io/[^"]+\.zip)""#),
                kind: .zip)),
        VendorProbeRecipe(
            bundleID: "im.riot.nightly",
            url: URL(string: "https://packages.element.io/nightly/update/macos/releases.json")!,
            mode: .responseBody,
            versionPattern: #""currentRelease"\s*:\s*"([^"]+)""#,
            downloadURL: URL(string: "https://element.io/download"),
            changelogURL: URL(string: "https://github.com/element-hq/element-desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(https://packages\.element\.io/[^"]+\.zip)""#),
                kind: .zip),
            channel: .nightly),

        // WeType (微信输入法) — Tencent's input method. Installs under
        // `/Library/Input Methods` (not /Applications), now scanned by AppScanner.
        // No standard source resolves it: its bundled Sparkle has NO SUFeedURL in
        // Info.plist (set at runtime), and the hardcoded public appcast froze at
        // 1.4.1 (2025-07) while 2.x updates ride an in-app WeChat push channel — so
        // the only public "what's the latest macOS version" surface is the official
        // changelog page. It's a Next.js page but the data is server-rendered inline
        // (an `__next_f` RSC blob, no JS needed): a flat list of release objects for
        // ALL platforms — `"platform":1`=iOS, `2`=Android, `3`=macOS, `4`=Windows.
        // CRUCIAL anchor: `version` precedes `platform` in each object, so the
        // pattern ties the captured version to its OWN object's `"platform":3` —
        // `[^"]*` can't cross a structural quote, so it can't span into an adjacent
        // (e.g. iOS) object. Without that gate, a bare/highest version pattern would
        // grab a higher non-macOS version (iOS is at 3.4.0) → a phantom update.
        // `content_html` carries no raw `"` (quotes are `&quot;`-encoded), so the
        // `[^"]*` field bounds hold. selectHighest because the page lists releases
        // ascending (oldest-first) and the pattern matches NOTHING BUT macOS
        // versions. DETECTION-ONLY, re-checked 2026-08-09: the page DOES now expose
        // download links (`WeTypeInstaller_2.2.2_647_[d-g].zip`), but each contains
        // `WeTypeInstaller.app` (`com.tencent.wetype.InstallerApp`, 3 MB, notarized
        // under Team 88L2Q4487U) — a stub that fetches and installs the real thing.
        // The input method itself lives at `/Library/Input Methods/WeType.app`, not
        // in `/Applications`, so there is nothing here for an in-place swap to
        // replace even if the payload were the app. WeType self-updates in-app. changelogURL is the same page (the `/macos`
        // route filters to macOS client-side) — also parsed natively by a
        // ChangelogRecipe; this is the webview fallback if that parse misses.
        VendorProbeRecipe(
            bundleID: "com.tencent.inputmethod.wetype",
            url: URL(string: "https://z.weixin.qq.com/web/change-log/macos")!,
            mode: .responseBody,
            versionPattern: #""version":"([0-9][^"]*)","content":"[^"]*","content_html":"[^"]*","platform":3"#,
            downloadURL: URL(string: "https://z.weixin.qq.com/"),
            changelogURL: URL(string: "https://z.weixin.qq.com/web/change-log/macos"),
            selectHighest: true),

        // WeChat (微信, 官网版) — Tencent's flagship messenger, installed from the
        // official site (Developer ID, no MAS receipt, no SUFeedURL in Info.plist).
        // No standard source resolves it: the Homebrew cask is `auto_updates: true`
        // (fall-through), MAS is a separate copy, and WeChat's bundled Sparkle sets
        // its feed URL at runtime. But the appcast IS public — the same XML the cask's
        // livecheck reads. We probe it directly.
        //
        // VERSION SCHEME: compare the MARKETING version, the way users (and the
        // official site) track WeChat — "4.1.10". The feed's `sparkle:shortVersionString`
        // is a 4-segment `4.1.10.53`, but the installed bundle STRIPS the 4th segment
        // and reports `CFBundleShortVersionString = 4.1.10`; the official changelog and
        // download both say "4.1.10". So the pattern captures only the first THREE
        // segments → "4.1.10", which equals the installed marketing version (up to
        // date) and bumps cleanly to "4.1.11" when that ships. We deliberately do NOT
        // compare the `sparkle:version` build (268853 vs 268851): WeChat re-spins
        // builds inside one marketing version, and surfacing "→ 268853" is both a
        // meaningless number and a non-update in the user's eyes. The pattern matches
        // both the element and the enclosure-attribute form of `shortVersionString`;
        // selectHighest takes the newest across all items (it matches nothing but app
        // versions).
        //
        // One-click dmg: the enclosure is on Tencent's own CDN, same channel, signed
        // by the same Team `5A4RE8SF68` (Tencent Mobile International) as the installed
        // app — the VendorInstaller signature gate enforces it. `.bodyPattern` takes
        // the FIRST `<enclosure>` (newest item, listed first); its `?t=<token>` query
        // is read fresh from each probe's feed. Structured notes come from a
        // ChangelogRecipe over the official per-version updates page; changelogURL is
        // the webview fallback.
        VendorProbeRecipe(
            bundleID: "com.tencent.xinWeChat",
            url: URL(string: "https://dldir1.qq.com/weixin/mac/mac-release.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:shortVersionString[>="]+\s*(\d+\.\d+\.\d+)"#,
            downloadURL: URL(string: "https://mac.weixin.qq.com/"),
            changelogURL: URL(string: "https://weixin.qq.com/updates?platform=mac"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"<enclosure url="(https://[^"]+\.dmg[^"]*)""#),
                kind: .dmg)),

        // ToDesk (远程控制) — Hainan Youqu's remote-desktop app. No standard source
        // resolves it; its in-app appcast sits behind a JS bot-challenge (the reason
        // it was long left "unknown"). The public download page is the way in: a
        // Nuxt/Vue SPA whose macOS pkg URL is SERVER-RENDERED into the inline data
        // blob (no JS needed). ANCHOR ON THE `macos/` pkg FILENAME `ToDesk_<ver>.pkg`.
        // History: we used to key off a quoted `mac_version:"4.9.7.2"` literal, but
        // 2026-07-13 the vendor variable-ized every macOS version field
        // (`mac_version:l`, `mac_version_gray:l` — bare vars, no quoted digits), so
        // that anchor stopped matching → "probe resolved no version". The GA marketing
        // version now survives only in the positional-arg block
        // (`("",false,"-1","2026.7.10","…/macos/ToDesk_4.9.7.4.pkg",…`); the pkg
        // filename is the one durable literal. Two other pkg links share the page —
        // the DaaS (enterprise) GA `…/daas/mac/ToDesk_DaaS_v1.1.0.1.pkg` and its gray
        // `ToDesk_DaaS-v1.1.0.1_392.pkg` — but both read `ToDesk_D…`, so anchoring on
        // `ToDesk_<digit>` excludes them; the only `ToDesk_<digits>.pkg` on the page
        // is the consumer GA build. NB `2026.7.10` is a release DATE that precedes the
        // pkg URL — never anchor on it; the real marketing version (==
        // CFBundleShortVersionString) lives in the filename. Non-build recipe, first
        // match, no selectHighest.
        // Residual risk: if the vendor ever moves the consumer GRAY channel back to a
        // `ToDesk_<digits>.pkg` name that precedes GA in the body, first-match would
        // grab the (older) gray build — a stale-but-real version, i.e. under-reporting
        // rather than inventing an update (safe direction). Revisit then.
        // One-click pkg install rebuilds the GA URL from the captured filename version
        // (template), on the vendor's own dl.todesk.com, signed by the same Team
        // KM56KD59W4 (Hainan Youqu Technology) as the installed app — the
        // VendorInstaller signature gate enforces it.
        VendorProbeRecipe(
            bundleID: "com.youqu.todesk.mac",
            url: URL(string: "https://www.todesk.com/download.html")!,
            mode: .responseBody,
            versionPattern: #"ToDesk_([0-9]+(?:\.[0-9]+)+)\.pkg"#,
            downloadURL: URL(string: "https://www.todesk.com/download.html"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://dl.todesk.com/macos/ToDesk_{0}.pkg",
                    fields: [#"ToDesk_([0-9]+(?:\.[0-9]+)+)\.pkg"#]),
                kind: .pkg)),

        // Spotify — no cheap public version API (the cohort `upgrade.scdn.co`
        // endpoint is session-token-gated, not a configurable key). BUT the 1.8MB
        // "stub" web installer `download.scdn.co/SpotifyInstaller.zip` bundles an
        // `Install Spotify.app` whose CFBundleShortVersionString tracks the latest
        // CLIENT version in lockstep — verified 2026-06-16: stub `1.2.92.148` while
        // the installed app AND Homebrew's cask both lagged at `.147`, so the stub
        // is the FRESHEST surface (even ahead of brew's heavyweight `extract_plist`
        // of the 164MB dmg). The version sits behind two layers — a
        // deflate-compressed zip entry + a binary plist — so it needs the
        // `.zipEntryPlist` mode (text-regex / redirect modes can't reach it); the
        // pattern just validates the extracted string is a dotted version. Same
        // marketing scheme the app reports (4-component `1.2.x.y`), so not a build
        // recipe. One-click install pulls the full always-latest universal dmg
        // (`download.scdn.co/SpotifyARM64.dmg`, 164MB, fetched only at apply time) —
        // an in-place app swap gated by Spotify's Team 2FNC3A47ZF. changelogURL is
        // nil on purpose: spotify.com/release-notes tracks a DIFFERENT (mobile/web)
        // version scheme (`1.2.534.x`), so embedding it for a `1.2.92.x` desktop
        // build would show an unrelated page — better the honest "no notes" state.
        VendorProbeRecipe(
            bundleID: "com.spotify.client",
            url: URL(string: "https://download.scdn.co/SpotifyInstaller.zip")!,
            mode: .zipEntryPlist(
                entry: "Install Spotify.app/Contents/Info.plist",
                key: "CFBundleShortVersionString"),
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            downloadURL: URL(string: "https://www.spotify.com/download/mac/"),
            install: VendorInstallSpec(
                urlSource: .fixed(URL(string: "https://download.scdn.co/SpotifyARM64.dmg")!),
                kind: .dmg)),

        // Cursor — official update API; the first `version` field is the latest
        // build. Single channel (its "stable"/"latest" tracks resolve to the same
        // build). One-click: the same JSON carries `downloadUrl` → the arm64
        // `Cursor-darwin-arm64.dmg` on downloads.cursor.com. (Cursor self-updates via
        // ToDesktop; this is the fallback, guarded by the same-Team gate.)
        VendorProbeRecipe(
            bundleID: "com.todesktop.230313mzl4w4u92",
            url: URL(string: "https://api2.cursor.sh/updates/api/download/latest/darwin-arm64/cursor")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.cursor.com/downloads"),
            changelogURL: URL(string: "https://www.cursor.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""downloadUrl"\s*:\s*"(https://downloads\.cursor\.com/[^"]+\.dmg)""#),
                kind: .dmg)),

        // Raycast — official "latest release" endpoint; `version` is first. Single
        // channel. One-click: the same JSON's `downloadURL` is the dmg (a
        // worker.raycast-releases.com proxy URL wrapping a presigned R2 object;
        // resolved fresh from each probe so its signed expiry is never stale).
        VendorProbeRecipe(
            bundleID: "com.raycast.macos",
            url: URL(string: "https://releases.raycast.com/releases/latest?build=universal")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.raycast.com/"),
            changelogURL: URL(string: "https://www.raycast.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""downloadURL"\s*:\s*"(https://[^"]+)""#),
                kind: .dmg)),

        // Docker Desktop — Sparkle appcast. Titles read "<ver> (<build>)" (and
        // "Version <ver> (<build>)"); take the highest since the feed isn't
        // strictly ordered. The channel title "Docker for Mac" carries no
        // version-paren and is skipped. Build number ignored in comparison.
        VendorProbeRecipe(
            bundleID: "com.docker.docker",
            url: URL(string: "https://desktop.docker.com/mac/main/arm64/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<title>(?:Version\s*)?([0-9]+\.[0-9]+\.[0-9]+)\s*\("#,
            changelogURL: URL(string: "https://docs.docker.com/desktop/release-notes/"),
            selectHighest: true,
            // The install pattern anchors on `Docker.dmg` for a reason: this feed
            // nests `<sparkle:deltas>` whose entries are `<enclosure>` too, pointing
            // at `Docker-<prev>.delta`. A looser match would happily install a patch
            // file as if it were the app. (Same trap that made the Sparkle parser
            // drop whole feeds — see `SparkleAppcastParser`.)
            //
            // Verified 2026-08-09 on 4.85.0 (build 235549): `Docker.app` in the
            // image, bundle id com.docker.docker, Team 9BNSXJN65R, spctl "Notarized
            // Developer ID". 573 MB, arm64-specific feed path.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://desktop\.docker\.com/[^"]+/Docker\.dmg)""#),
                kind: .dmg)),

        // LibreWolf — release tags, newest first; tag is "<firefox-version>-<packaging>"
        // (e.g. "151.0.3-1") and we capture only the upstream Firefox version so it
        // compares equal to the installed app's `CFBundleShortVersionString` (keeping
        // "-1" would read as a perpetual update). No auto-updater — genuinely useful.
        // Real installed bundle id is `net.librewolf.librewolf` (NOT
        // `org.mozilla.librewolf` — LibreWolf re-brands the Mozilla source). Version
        // source is **Codeberg**, not GitLab: LibreWolf migrated, and the old GitLab
        // repos are abandoned (project 44042130/bsys6 caps at 147.0.4 while current
        // is 151.x → a stale probe). The brew cask's own livecheck reads this same
        // Codeberg `releases/latest`. Verified 2026-06-04 against an installed cask:
        // app reports `151.0.3-1`; `tag_name` is `151.0.3-1` → captures `151.0.3`.
        //
        // DETECTION ONLY, and not for lack of a URL — the release does publish
        // `librewolf-<ver>-macos-arm64-package.dmg`. Checked it on 2026-08-09: the
        // `LibreWolf.app` inside is ad-hoc signed (`TeamIdentifier=not set`) and
        // Gatekeeper rejects it outright ("code has no resources but signature
        // indicates they must be present"). `VendorInstaller`'s same-Team gate would
        // refuse it anyway, and rightly: there is no signing identity to compare the
        // installed copy against. Don't wire one-click here unless LibreWolf starts
        // shipping a Developer ID build.
        VendorProbeRecipe(
            bundleID: "net.librewolf.librewolf",
            url: URL(string: "https://codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest")!,
            mode: .responseBody,
            versionPattern: #""tag_name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"#,
            downloadURL: URL(string: "https://librewolf.net/installation/macos/"),
            changelogURL: URL(string: "https://codeberg.org/librewolf/bsys6/releases")),

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
            changelogURL: URL(string: "https://lmstudio.ai/changelog/lmstudio"),
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
        // Two public tracks share `io.tailscale.ipn.macsys`; the channel gate
        // routes each install to its own endpoint per the app's opt-in toggle
        // (see `TailscaleChannel`). `pkgs.tailscale.com/rc` 404s — no third track.
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
                kind: .pkg),
            channel: .stable),
        // Tailscale unstable — same JSON shape on the `/unstable` track (odd
        // minor, e.g. 1.99.x). Only reached when the install opted in via
        // `UnstableUpdatesEnabled`; the same Tailscale-signed pkg path.
        VendorProbeRecipe(
            bundleID: "io.tailscale.ipn.macsys",
            url: URL(string: "https://pkgs.tailscale.com/unstable/?mode=json")!,
            mode: .responseBody,
            versionPattern: #""MacZipsVersion"\s*:\s*"([0-9.]+)""#,
            changelogURL: URL(string: "https://tailscale.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #""universal-package"\s*:\s*"(Tailscale-[^"]+\.pkg)""#,
                    base: URL(string: "https://pkgs.tailscale.com/unstable/")!),
                kind: .pkg),
            channel: .unstable),

        // AweSun (Oray) — official software API; same endpoint the Homebrew cask
        // livecheck uses. Intel build drops the `_ARM` suffix. The dmg holds a
        // signed `AweSun.pkg` (Developer ID Installer ZBNMDRTU32) → system
        // installer (pkg). We take the FILENAME out of the JSON's own
        // `downloadurl` and re-host it on `dw.oray.com` rather than build the
        // name ourselves: the vendor renamed the file once already (`AweSun_v{v}`
        // → `AweSun_{v}`, which 404'd every install at 16.6.0.32198), and the
        // field's own host alternates per request between `dw.oray.com` and
        // `d-cdn.oray.com` while the filename stays identical. We can't use the
        // URL verbatim either — the field escapes its slashes (`https:\/\/…`,
        // breaking `URL(string:)`). `dw.oray.com` is behind an Aliyun WAF that
        // returns an anti-bot JS challenge unless a `Referer` is present — so we
        // send one. If the filename can't be read, the probe degrades to opening
        // the official download page (downloadURL).
        VendorProbeRecipe(
            bundleID: "com.oray.sunlogin.macclient",
            url: URL(string: "https://client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM?versiontype=stable")!,
            mode: .responseBody,
            versionPattern: #""versionno"\s*:\s*"([0-9.]+)""#,
            downloadURL: URL(string: "https://sunlogin.oray.com/download"),
            changelogURL: URL(string: "https://sunlogin.oray.com/download/update-log?soft=SLCC_X_MAC_ARM"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://dw.oray.com/sl/mac/{0}",
                    fields: [#""downloadurl"\s*:\s*"[^"]*?(AweSun_[0-9][^"\\/]*_arm64\.dmg)""#]),
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

        // HBuilderX (DCloud) — the vendor's own download-site config. This is the
        // SAME `release.json` the changelog recipe already reads (see
        // ChangelogRecipe), and it carries BOTH the version and the installer
        // `files[]`, so one source drives detection and one-click alike — the same
        // shape as the alpha recipe below.
        //
        // Previously this pointed at a third-party mirror
        // (update.liuyingyong.cn/…/alpha/…) that only served the update manifest,
        // no installer, so it was detection-only and could lag the vendor. The
        // official release.json is fresher and lists the arm64 dmg directly.
        //
        // One-click: `files[]` lists the platforms in win/x64/arm64 order, so the
        // plain `mac_simple` x64 `.dmg` appears BEFORE `mac_simple_arm64`; the
        // `\.arm64\.dmg` anchor pins the Apple-silicon build regardless of order
        // (same guard as the alpha recipe). The dmg is notarized under Team
        // YQM5H857L5 (Digital Heaven / DCloud), same as the alpha, so it clears
        // VendorInstaller's signature gate. Apple-silicon only.
        //
        // The trailing `"` in versionPattern is load-bearing: it requires the
        // captured X.Y.Z to be immediately closed by a quote, so the config's own
        // 2-component `displayVersion` ("5.14") and any hypothetical suffixed
        // string can't be mis-captured. Don't drop it.
        VendorProbeRecipe(
            bundleID: "io.dcloud.HBuilderX",
            url: URL(string: "https://download1.dcloud.net.cn/hbuilderx/release.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://hx.dcloud.net.cn/Tutorial/HistoryVersion"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://download1\.dcloud\.net\.cn/download/HBuilderX\.[0-9.]+\.arm64\.dmg)"#),
                kind: .dmg)),

        // HBuilderX Alpha (DCloud) — the alpha track is a SEPARATE app: bundle id
        // io.dcloud.HBuilderXAlpha, installed as HBuilderX-Alpha.app, notarized
        // under the SAME Team ID (YQM5H857L5) as the stable build. Its detected
        // channel is .alpha (the "HBuilderX-Alpha" bundle name carries a standalone
        // "alpha" token), so this recipe MUST declare channel: .alpha — otherwise
        // VendorProbeSource's channel gate refuses it and the app stays "unknown".
        // Version comes from the download page's alpha config JSON, whose `version`
        // is the full pre-release string ("5.11.2026052520-alpha") and matches the
        // installed CFBundleShortVersionString exactly (VersionComparator tokenizes
        // the "-alpha" as a trailing text run, so equal strings compare equal and a
        // newer numeric build still wins). The trailing `"` after the capture keeps
        // it off the shorter `displayVersion` ("5.11") field.
        //
        // One-click: the SAME alpha.json that yields the version also lists the
        // installer under `files[]`. We grab the arm64 dmg explicitly — its
        // `mac_simple_arm64` entry appears AFTER the x64 `mac_simple` `.dmg`, so a
        // naive `\.dmg` `.bodyPattern` (first match) would pull the Intel build;
        // the `\.arm64\.dmg` anchor pins the right one regardless of order. The dmg
        // is notarized under the same Team ID YQM5H857L5 as the installed alpha, so
        // it clears VendorInstaller's signature gate. (Apple-silicon only; an Intel
        // Mac would need the plain `…-alpha.dmg`, but this repo is arm64-first.)
        VendorProbeRecipe(
            bundleID: "io.dcloud.HBuilderXAlpha",
            url: URL(string: "https://download1.dcloud.net.cn/hbuilderx/alpha.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+-alpha)""#,
            changelogURL: URL(string: "https://hx.dcloud.net.cn/Tutorial/HistoryVersion"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://download1\.dcloud\.net\.cn/download/HBuilderX\.[0-9.]+-alpha\.arm64\.dmg)"#),
                kind: .dmg),
            channel: .alpha),

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

        // Android Studio — Canary & Beta preview installs. Both share Stable's
        // `com.google.android.studio`; the install's channel is read from the
        // bundle filename (see `ReleaseChannel.detect` step 0.5), and the channel
        // gate routes each here. Source is Google's official releases-list JSON
        // (`jb.gg/android-studio-releases-list.json`, the same data the download
        // page uses; 307→TeamCity, redirect followed). CRUCIAL: the installed
        // `CFBundleShortVersionString` is truncated to "2026.1" and identical
        // across tracks, so a marketing-version compare is useless — we compare on
        // the `build` field ("AI-261.24374.151.2612.15561891"), which matches the
        // installed `CFBundleVersion` byte-for-byte, via `versionIsBuild`.
        //
        // STABILITY FLOOR (not "newest preview wins"): each preview channel accepts
        // builds at its own quality OR more stable, never less stable. Android
        // Studio's quality ladder is Canary (least stable) → Beta → RC → stable.
        //   • Canary install → newest of {Canary, Beta, RC}: a Canary 7 install
        //     correctly moves onto `2026.1.2 RC 1` when no newer Canary exists, and
        //     onto `2026.1.3 Canary 1` once the next feature version opens.
        //   • Beta install → newest of {Beta, RC} ONLY — it must NEVER be offered a
        //     Canary build (that's a stability DOWNGRADE). When a Beta sits on the
        //     latest RC and the only newer thing is the next version's Canary, the
        //     Beta is correctly up to date.
        // (An earlier "highest across all previews" version wrongly pushed
        //  `2026.1.3 Canary 1` at a Beta install that was already current; and the
        //  original channel-pure "Canary only" wrongly hid the RC the user wanted.
        //  See `InstalledApp.prefersVendorProbeOverToolbox`.) The feed is
        // newest-first, so the FIRST channel-set match is that set's newest build.
        // dmg patterns mirror each channel set — though these installs are
        // Toolbox-managed → detection-only, so the install spec is suppressed at the
        // source and the user updates through Toolbox; the dmg set just stays in
        // lockstep with the version set. Team EQHXZ8M8AV.
        VendorProbeRecipe(
            bundleID: "com.google.android.studio",
            url: URL(string: "https://jb.gg/android-studio-releases-list.json")!,
            mode: .responseBody,
            versionPattern:
                #""build"\s*:\s*"(AI-[^"]+)","platformVersion":"[^"]*","name":"[^"]*","channel":"(?:Canary|Beta|RC)""#,
            changelogURL: URL(string: "https://developer.android.com/studio/preview/features"),
            versionIsBuild: true,
            // Show the feed's clean marketing name ("2026.1.2 RC 1") not the raw
            // build id ("AI-261.…"); the build still drives the comparison.
            displayVersionPattern:
                #""name":"[^"]*\|\s*([^"]+)","channel":"(?:Canary|Beta|RC)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://edgedl\.me\.gvt1\.com/android/studio/install/[0-9.]+/android-studio-[^"]*(?:canary|beta|rc)[0-9]*-mac_arm\.dmg)"#),
                kind: .dmg),
            channel: .canary),
        VendorProbeRecipe(
            bundleID: "com.google.android.studio",
            url: URL(string: "https://jb.gg/android-studio-releases-list.json")!,
            mode: .responseBody,
            // Beta accepts only Beta/RC — NEVER Canary (a stability downgrade).
            versionPattern:
                #""build"\s*:\s*"(AI-[^"]+)","platformVersion":"[^"]*","name":"[^"]*","channel":"(?:Beta|RC)""#,
            changelogURL: URL(string: "https://developer.android.com/studio/preview/features"),
            versionIsBuild: true,
            // Show the feed's clean marketing name ("2026.1.2 RC 1") not the raw
            // build id ("AI-261.…"); the build still drives the comparison.
            displayVersionPattern:
                #""name":"[^"]*\|\s*([^"]+)","channel":"(?:Beta|RC)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://edgedl\.me\.gvt1\.com/android/studio/install/[0-9.]+/android-studio-[^"]*(?:beta|rc)[0-9]*-mac_arm\.dmg)"#),
                kind: .dmg),
            channel: .beta),

        // Slack (desktop, mac) — the website's own "latest" download link. A
        // single 302 from slack.com/ssb/download-osx-universal lands on the
        // versioned package downloads.slack-edge.com/.../mac/universal/<ver>/
        // Slack-<ver>-macOS.dmg, so the version rides in the resolved filename
        // (HEAD+follow → lastPathComponent). Use the -universal link, NOT -osx
        // (that resolves to the x64/Intel build). ChangelogRecipe(com.tinyspeck.slackmacgap)
        // renders the notes natively. One-click: the same -universal link IS the
        // installer — the spec HEAD-follows the 302 to the versioned universal dmg
        // and swaps in place (on top of Slack's own Squirrel updater).
        VendorProbeRecipe(
            bundleID: "com.tinyspeck.slackmacgap",
            url: URL(string: "https://slack.com/ssb/download-osx-universal")!,
            mode: .redirectFilename,
            versionPattern: #"^Slack-([0-9]+\.[0-9]+\.[0-9]+)-macOS\.dmg$"#,
            downloadURL: URL(string: "https://slack.com/downloads/mac"),
            changelogURL: URL(string: "https://slack.com/release-notes/mac"),
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://slack.com/ssb/download-osx-universal")!),
                kind: .dmg)),

        // Discord — official update manifest (channel=stable, platform=osx). The
        // version lives ONLY as the JSON array `host_version:[0,0,393]` and as a
        // path segment in each distro `url` (…/osx/universal/0.0.393/…). The array
        // is unusable — extractVersion takes capture group 1 only and can't join
        // three groups (it'd read "0") — so we anchor to the distro url path,
        // which carries the whole X.Y.Z in one group. Every url in the body (full
        // + deltas + per-module) targets the same destination version, so first
        // match is correct; the delta SOURCE (0.0.392) never appears as a
        // /universal/<v>/ segment. Discord self-updates via its own host updater.
        // ptb/canary ship as separate bundle ids with their own channel=ptb|canary
        // endpoints — their dedicated recipes follow below. One-click NOTE: the
        // manifest carries only `.distro` module files, not an app dmg, so the
        // install uses Discord's SEPARATE public download endpoint —
        // `discord.com/api/download?platform=osx&format=dmg` — which 302s to the same
        // version's `…/apps/osx/<ver>/Discord.dmg` (verified 0.0.395 == host_version).
        // ptb/canary stay detection-only for now (their dmg endpoints unverified).
        VendorProbeRecipe(
            bundleID: "com.hnc.Discord",
            url: URL(string: "https://updates.discord.com/distributions/app/manifests/latest?channel=stable&platform=osx&arch=x64")!,
            mode: .responseBody,
            versionPattern: #"stable\.dl2\.discordapp\.net/distro/app/stable/osx/universal/([0-9]+\.[0-9]+\.[0-9]+)/"#,
            downloadURL: URL(string: "https://discord.com/download"),
            changelogURL: URL(string: "https://discord.com/blog"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://discord.com/api/download?platform=osx&format=dmg")!),
                kind: .dmg)),

        // Discord PTB / Canary — same manifest endpoint as Stable, just a different
        // `channel=` query, and each ships under its own bundle id with its own
        // `<chan>.dl2.discordapp.net/distro/app/<chan>/…` url path (so the version
        // pattern only swaps the channel literal). Detection only — Discord
        // self-updates via its own host updater. Canary's "Discord Canary" name
        // detects as .canary via the standalone word; PTB needs the dedicated
        // `.ptb` channel (no word/suffix otherwise carries "Public Test Build").
        VendorProbeRecipe(
            bundleID: "com.hnc.DiscordPTB",
            url: URL(string: "https://updates.discord.com/distributions/app/manifests/latest?channel=ptb&platform=osx&arch=x64")!,
            mode: .responseBody,
            versionPattern: #"ptb\.dl2\.discordapp\.net/distro/app/ptb/osx/universal/([0-9]+\.[0-9]+\.[0-9]+)/"#,
            changelogURL: URL(string: "https://discord.com/blog"),
            // One-click verified 2026-08-09: `https://discord.com/api/download/ptb`
            // 302s to `…/apps/osx/0.0.252/DiscordPTB.dmg`, holding `Discord PTB.app`
            // — bundle id com.hnc.DiscordPTB, Team 53Q6R32WPB, accepted by spctl.
            // The stable "latest" redirect is what to install from: the manifest URL
            // above points at a `.dis` distro blob, not an app.
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://discord.com/api/download/ptb?platform=osx")!),
                kind: .dmg),
            channel: .ptb),
        VendorProbeRecipe(
            bundleID: "com.hnc.DiscordCanary",
            url: URL(string: "https://updates.discord.com/distributions/app/manifests/latest?channel=canary&platform=osx&arch=x64")!,
            mode: .responseBody,
            versionPattern: #"canary\.dl2\.discordapp\.net/distro/app/canary/osx/universal/([0-9]+\.[0-9]+\.[0-9]+)/"#,
            changelogURL: URL(string: "https://discord.com/blog"),
            // Same stable "latest" redirect as PTB, on the canary track (the
            // manifest URL points at a `.dis` distro blob, not an app). Verified
            // separately rather than assumed from PTB: 0.0.1255 →
            // `Discord Canary.app`, bundle id com.hnc.DiscordCanary, Team
            // 53Q6R32WPB, accepted by spctl.
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://discord.com/api/download/canary?platform=osx")!),
                kind: .dmg),
            channel: .canary),

        // Notion desktop — public "latest" download redirect. www.notion.so/
        // desktop/mac/download 307s straight to the versioned installer
        // (…/Notion-<ver>-universal.dmg); the version is in that `Location`
        // filename. It redirects on BOTH HEAD and GET, but the target is a
        // ~203 MB dmg, so don't follow — read the small 307 Location. Use the
        // `.so` host: it's a single hop, whereas `.com/desktop/mac/download`
        // bounces through app.notion.com first. ChangelogRecipe(notion.id) renders
        // notes. One-click: the very same `/desktop/mac/download` 307 IS the
        // installer link — the install spec HEAD-follows it to the versioned
        // universal dmg and swaps in place (on top of Notion's own self-updater).
        VendorProbeRecipe(
            bundleID: "notion.id",
            url: URL(string: "https://www.notion.so/desktop/mac/download")!,
            mode: .redirectFilename,
            versionPattern: #"Notion-([0-9]+\.[0-9]+\.[0-9]+)-"#,
            downloadURL: URL(string: "https://www.notion.com/desktop")!,
            changelogURL: URL(string: "https://www.notion.com/releases")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://www.notion.so/desktop/mac/download")!),
                kind: .dmg),
            followRedirects: false),

        // Obsidian — official desktop-releases manifest (the same file Obsidian's
        // own updater reads). Two "latestVersion" keys live here: the TOP-LEVEL
        // one is STABLE, then a nested "beta" object carries the (currently HIGHER)
        // insider build. We anchor to the FIRST match so we read STABLE only;
        // selectHighest stays false (true would grab the bigger beta value and
        // invent a phantom update for a stable install). ChangelogRecipe(md.obsidian)
        // renders the notes natively. One-click CAVEAT: this manifest's own
        // `downloadUrl` is an `.asar.gz` — Obsidian's in-place patch format, which we
        // can't apply. The full signed dmg lives only on the GitHub release, named
        // `Obsidian-<ver>.dmg`, so we template that URL from the stable `latestVersion`
        // (first match — the nested `beta` object's higher version comes later and is
        // intentionally NOT picked). A full-bundle dmg swap supersedes Obsidian's own
        // lighter asar self-update; the same-Team gate still guards it.
        VendorProbeRecipe(
            bundleID: "md.obsidian",
            url: URL(string: "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/desktop-releases.json")!,
            mode: .responseBody,
            versionPattern: #""latestVersion"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://obsidian.md/download"),
            changelogURL: URL(string: "https://obsidian.md/changelog/"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://github.com/obsidianmd/obsidian-releases/releases/download/v{0}/Obsidian-{0}.dmg",
                    fields: [#""latestVersion"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#]),
                kind: .dmg)),

        // Figma desktop (stable) — official per-arch "latest" manifest (the same
        // RELEASE.json the Homebrew cask livecheck reads). `version` is first and
        // matches the app's CFBundleShortVersionString (e.g. 126.4.13). mac-arm is
        // the Apple-silicon flavor; an Intel build would use the `mac` path. The
        // body also carries the absolute zip URL ("url":"…/Figma-<ver>.zip") — the
        // install spec captures that for one-click. Confirmed 2026-06-06: the
        // downloaded Figma-126.4.13.zip is a notarized Developer ID build, Team
        // T8RA8NE3B7 (Figma, Inc.), bundle id com.figma.Desktop == the installed
        // app, so the VendorInstaller Team gate passes. ChangelogRecipe renders the
        // notes. (Figma also self-updates via Squirrel; this is a manual fallback.)
        VendorProbeRecipe(
            bundleID: "com.figma.Desktop",
            url: URL(string: "https://desktop.figma.com/mac-arm/RELEASE.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.figma.com/downloads/"),
            changelogURL: URL(string: "https://www.figma.com/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(https://desktop\.figma\.com/[^"]+\.zip)""#),
                kind: .zip)),

        // Figma Beta — a SEPARATE app (NOT an in-app toggle): its own bundle id
        // com.figma.DesktopBeta, its own "Figma Beta.app", and a parallel endpoint
        // tree under /beta/. Pattern A (independent installs), so no cross-channel
        // risk — this recipe only ever resolves against a real Figma Beta install,
        // which detects as `.beta` (verified via channel-verify on the 126.6.2
        // bundle). Endpoint mirrors stable exactly: RELEASE.json → version + the
        // FigmaBeta-<ver>.zip url. Same signer as stable (Team T8RA8NE3B7,
        // confirmed 2026-06-06 on the real FigmaBeta-126.6.2.zip), so one-click is
        // safe behind the same Team gate. Notes share the product release-notes page
        // (Figma publishes no separate beta changelog).
        VendorProbeRecipe(
            bundleID: "com.figma.DesktopBeta",
            url: URL(string: "https://desktop.figma.com/mac-arm/beta/RELEASE.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.figma.com/downloads/"),
            changelogURL: URL(string: "https://www.figma.com/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(https://desktop\.figma\.com/[^"]+\.zip)""#),
                kind: .zip),
            channel: .beta),

        // 1Password 8 — self-updates via its own EdDSA updater, so no standard
        // source resolves it. The vendor's app-updates.agilebits.com/check JSON
        // API only serves the NIGHTLY channel for product OPM8 (no stable param
        // exists), so it can't be used for a stable install. Instead scrape the
        // stable releases page, whose "1Password for Mac <ver>" titles are
        // server-rendered and listed newest-first — the FIRST match is the current
        // stable build (the bare <h1> "1Password for Mac" has no version and is
        // skipped by the required \s+[0-9]). NOTE: HTML scrape — more brittle than
        // an API; refresh if it stops matching. The same page is also the
        // ChangelogRecipe(com.1password.1password) source.
        //
        // DETECTION ONLY, deliberately. `downloads.1password.com/mac/1Password.zip`
        // looks like a perfect one-click target — stable URL, Developer ID
        // (2BUA8C4S2C), notarized — but what it actually contains is
        // `1Password Installer.app` (`com.1password.1password-installer`), a stub
        // that fetches the real app. Swapping that over `/Applications/1Password.app`
        // would replace the password manager with its installer. Checked 2026-08-09;
        // don't wire this without a payload that IS the app.
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
            changelogURL: URL(string: "https://www.sublimetext.com/download"),
            // One-click verified 2026-08-09 on build 4200: `Sublime Text.app` in the
            // archive, bundle id and Team (Z6D26JE4Y4) matching the installed copy,
            // its CFBundleShortVersionString literally "Build 4200" like the probe's
            // value, spctl "Notarized Developer ID".
            //
            // The page ships the download link as a TEMPLATE — the literal string
            // `sublime_text_build_${version}_mac.zip`, with JS filling it in — so
            // there is no href to lift. Rebuild it from the same "latest" marker the
            // version comes from, taking the BARE build number (the version pattern
            // keeps the "Build " prefix on purpose; a URL can't).
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.sublimetext.com/sublime_text_build_{0}_mac.zip",
                    fields: [#"class="latest"><i>Version:</i>\s*Build\s+(4[0-9]{3})"#]),
                kind: .zip)),

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
            changelogURL: URL(string: "https://www.sublimemerge.com/download"),
            // Same shape as Sublime Text: the page ships the download link as the
            // literal template `sublime_merge_build_${version}_mac.zip` for JS to
            // fill, so it's rebuilt from the same "latest" marker, taking the BARE
            // build number (the version keeps its "Build " prefix to match what the
            // bundle reports; a URL can't carry it). Verified 2026-08-09 on build
            // 2125: `Sublime Merge.app`, Team Z6D26JE4Y4, accepted by spctl.
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.sublimetext.com/sublime_merge_build_{0}_mac.zip",
                    fields: [#"class="latest"><i>Version:</i>\s*Build\s+([0-9]{4})"#]),
                kind: .zip)),

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
        // Windows block. One-click: the MacOS block's release `url` is the
        // `Plex-<full>-universal.zip` on downloads.plex.tv/plex-desktop/ — anchored
        // to that path so it can't grab the Windows installer. (Plex self-updates via
        // Squirrel; this is the fallback behind the same-Team gate.)
        VendorProbeRecipe(
            bundleID: "tv.plex.desktop",
            url: URL(string: "https://plex.tv/api/downloads/6.json")!,
            mode: .responseBody,
            versionPattern: #""MacOS"\s*:\s*\{[^}]*?"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"#,
            downloadURL: URL(string: "https://www.plex.tv/media-server-downloads/?cat=plex+desktop"),
            changelogURL: URL(string: "https://www.plex.tv/media-server-downloads/?cat=plex+desktop"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://downloads\.plex\.tv/plex-desktop/[^"]+/macos/[^"]+universal\.zip)"#),
                kind: .zip)),

        // Alfred 5 — Sparkle PLIST appcast (not RSS). Alfred has no Info.plist
        // SUFeedURL (the feed is configured in Alfred's own Preferences), so it
        // reaches us here rather than via SparkleAppcastSource — same situation as
        // the Codex/OrbStack neighbors. The manifest is a single-release plist: the
        // top-level <key>version</key><string> is the latest build (5.7.3),
        // unambiguous vs the descending "## Alfred X.Y.Z" history inside
        // changelogdata. One release listed → first match is correct.
        //
        // One-click added 2026-08-08 after verifying what `location` points at: the
        // tarball holds `Alfred 5.app` at its root, whose bundle id
        // (`com.runningwithcrayons.Alfred`) and Team (`XZZXE9SED4`) match the
        // installed copy, and `spctl` reports "Notarized Developer ID". That URL
        // carries the version, so it's read from the same body rather than fixed.
        // Alfred still self-updates on its own; this only means the row can too.
        VendorProbeRecipe(
            bundleID: AlfredChannel.bundleID,
            url: URL(string: "https://www.alfredapp.com/app/update5/general.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>version</key>\s*<string>([0-9][0-9.]*)</string>"#,
            changelogURL: URL(string: "https://www.alfredapp.com/changelog/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>location</key>\s*<string>(https://[^<]+\.tar\.gz)</string>"#),
                kind: .tarGz)),

        // Shottr — its own JSON version check (the same endpoint baked into the app
        // binary: shottr.cc/api/version.json). NOT a Sparkle appcast — Shottr ships
        // none (no Info.plist SUFeedURL, /appcast.xml 404s), so it reaches us here.
        // `latestVersion` is the STABLE marketing version (1.9.1), equal to the
        // app's CFBundleShortVersionString. A `betaLatestVersion` also lives in the
        // body — the `"latestVersion"` anchor can't match the `"betaLatestVersion"`
        // key (different literal prefix), so a stable install is never offered the
        // One-click: the same JSON's `"package"` is the stable `Shottr-<ver>.pkg`.
        // Anchor to `"package"` (leading quote) so it never matches `"betaPackage"`
        // — a stable install is never handed the EAP pkg. (Shottr self-updates via
        // its own .pkg updater; this is the fallback behind the same-Team gate.)
        VendorProbeRecipe(
            bundleID: "cc.ffitch.shottr",
            url: URL(string: "https://shottr.cc/api/version.json")!,
            mode: .responseBody,
            versionPattern: #""latestVersion"\s*:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)?)""#,
            downloadURL: URL(string: "https://shottr.cc/"),
            changelogURL: URL(string: "https://shottr.cc/newversion.html"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""package"\s*:\s*"(https://shottr\.cc/[^"]+\.pkg)""#),
                kind: .pkg)),

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
            changelogURL: URL(string: "https://updates.devmate.com/releasenotes/147/com.macpaw.site.theunarchiver.html"),
            // One-click verified 2026-08-09 on the 4.3.9 archive from this same
            // feed: `The Unarchiver.app` inside, bundle id and Team (S8EX82NJP6)
            // matching the installed copy, spctl "Notarized Developer ID". The
            // enclosure URL is versioned AND carries a build timestamp, so it can
            // only come from the feed we just read — first item is newest here.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://dl\.devmate\.com/[^"]+\.zip)""#),
                kind: .zip)),

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
        // never-lie choice. One-click: the feed is ASCENDING, so the install takes
        // the LAST `<enclosure url=…zip>` (newest) — `.bodyPatternLast`, mirroring
        // `selectHighest` on the version side; first-match would grab the oldest 0.99.
        // (Orion self-updates via Sparkle; fallback behind the same-Team gate.)
        VendorProbeRecipe(
            bundleID: "com.kagi.kagimacOS",
            url: URL(string: "https://cdn.kagi.com/updates/26_0/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+(?:\.[0-9]+)+)</sparkle:shortVersionString>"#,
            downloadURL: URL(string: "https://browser.kagi.com/"),
            changelogURL: URL(string: "https://browser.kagi.com/updates/orion-release-notes.html"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .bodyPatternLast(#"url="(https://[^"]+\.zip)""#),
                kind: .zip)),

        // Dropbox (desktop, mac) — the website's "latest" download link. A single
        // 302 from www.dropbox.com/download?plat=mac&full=1 lands on the versioned
        // package edge.dropboxstatic.com/dbx-releng/client/Dropbox%20<ver>.dmg, so
        // the version rides in the %20-encoded Location filename. The target is a
        // ~200 MB dmg, so don't follow — read the small 302 Location
        // (followRedirects:false). NOTE the scheme is 3-component (254.4.2518 =
        // 254/4/2518, not four) — the pattern is three numeric groups. Detection
        // Dropbox self-updates, so this row usually just confirms that. (Homebrew
        // cask has no livecheck; its url/version confirm this host + build.)
        //
        // One-click verified 2026-08-09 on 264.4.3385: the image is labelled
        // "Dropbox Offline Installer" but holds the real `Dropbox.app` —
        // com.getdropbox.dropbox, Team G7HH3F8CAK, spctl "Notarized Developer ID",
        // version matching the redirect filename. (Worth stating, since the sibling
        // 1Password download turned out to be a stub installer, not the app.)
        VendorProbeRecipe(
            bundleID: "com.getdropbox.dropbox",
            url: URL(string: "https://www.dropbox.com/download?plat=mac&full=1")!,
            mode: .redirectFilename,
            versionPattern: #"Dropbox(?:%20| )([0-9]+\.[0-9]+\.[0-9]+)\.dmg"#,
            changelogURL: URL(string: "https://www.dropbox.com/release_notes")!,
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://www.dropbox.com/download?plat=mac&full=1")!),
                kind: .dmg),
            followRedirects: false),

        // MacUpdater — version is in an HTML comment marker on the product page.
        // NOTE: HTML scrape — more brittle than an API; refresh if it stops
        // matching.
        //
        // One-click verified 2026-08-09 on 3.5.0: `macupdater_latest.dmg` is an
        // unversioned "latest" URL holding `MacUpdater.app` — bundle id
        // com.corecode.MacUpdater, Team 9D78DG5ACV, spctl "Notarized Developer ID".
        // Fixed rather than scraped: the page's only download href is that same
        // stable path.
        VendorProbeRecipe(
            bundleID: "com.corecode.MacUpdater",
            url: URL(string: "https://www.corecode.io/macupdater/")!,
            mode: .responseBody,
            versionPattern: #"<!--BEGINVERSION-->([0-9.]+)<!--ENDVERSION-->"#,
            changelogURL: URL(string: "https://www.corecode.io/macupdater/history3.html"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://www.corecode.io/downloads/macupdater_latest.dmg")!),
                kind: .dmg)),

        // Alcove — PUBLIC mirror, kept only as the no-credential fallback. The
        // authoritative source is `AlcoveUpdateSource` (the licensed api.tryalcove.com
        // channel the app's own "Reworked update manager" uses), wired ahead of this
        // probe so it answers first whenever the user's license credentials are seeded.
        // This endpoint (update.tryalcove.com) is NOT authoritative — like the
        // henrikruscon/alcove-releases GitHub mirror it lags the licensed channel
        // (verified 2026-06-17: it served 1.7.3 while the licensed channel — and the
        // app itself — already offered 1.7.4). So it's best-effort detection for users
        // who haven't seeded credentials, nothing more. The endpoint returns
        // GitHub-release-shaped JSON: `tag_name` is the version
        // (semver == the app's CFBundleShortVersionString — no build trap) and
        // `assets[].browser_download_url` carries the versioned Alcove.dmg, anchored
        // on `Alcove\.dmg` so it's picked over the sibling Alcove.zip regardless of
        // order. One-click installs that dmg, gated by VendorInstaller's same-Team-ID
        // signature check (287NUTSP69, Henrik Ruscon — notarized Developer ID,
        // verified 2026-06-06). The download is the "trial" (unlicensed) build: it's
        // the same binary the licensed install runs, the license lives outside the
        // app bundle, so swapping it in place keeps the activation. Changelog comes
        // from the matching ChangelogRecipe parsing this same endpoint's `body`.
        VendorProbeRecipe(
            bundleID: "com.henrikruscon.Alcove",
            url: URL(string: "https://update.tryalcove.com")!,
            mode: .responseBody,
            versionPattern: #""tag_name"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.tryalcove.com/download")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""browser_download_url"\s*:\s*"([^"]+Alcove\.dmg)""#),
                kind: .dmg)),

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
