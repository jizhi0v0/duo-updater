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
        ///
        /// Prefer `bodyPatternHighestVersioned` when the feed states each entry's
        /// version next to its URL: "last in the document" is another bet on
        /// ordering, just the opposite one.
        case bodyPatternLast(String)
        /// Two capture groups — group 1 the URL, group 2 the version that same
        /// entry declares — and the entry with the highest version wins, in any
        /// document order.
        ///
        /// Use this for any feed that lists several releases and says which version
        /// each download is. It is the only positional-independent option: with
        /// `selectHighest` deciding the reported version by comparison while the URL
        /// was chosen by position, the two can name different releases — the app
        /// then downloads, backs up and installs a version it already has, reports
        /// success, and goes on offering the update (measured on Docker's appcast,
        /// which lists 4.86.0 ahead of 4.87.0).
        case bodyPatternHighestVersioned(String)
        /// Capture group 1 is a *relative* path/filename; resolve it against
        /// `base` to form the absolute URL (e.g. Tailscale's JSON gives only the
        /// pkg filename).
        case bodyPatternRelative(String, base: URL)
        /// Build the URL from a template with `{0}`, `{1}`, … placeholders, each
        /// filled by capture group 1 of the corresponding regex in `fields`,
        /// applied to the body. For feeds that publish the pieces but no link —
        /// e.g. LM Studio gives `version` + `build` and the dmg path needs both.
        case bodyTemplate(String, fields: [String])
        /// Build the URL from a template whose `{version}` placeholders are filled
        /// with the version the probe RESOLVED — not with a fresh first-match over
        /// the body.
        ///
        /// That distinction is the whole point. `bodyTemplate` re-runs its regexes
        /// and takes the first match, which agrees with the resolved version only
        /// when the body lists the newest release first. A vendor directory index
        /// is sorted ALPHABETICALLY (`"100.0" < "99.0"`, and `"v10.0" < "v9.17"`),
        /// so `selectHighest` deliberately picks a different entry than the first
        /// one — and a `bodyTemplate` there would quietly build a URL for an OLDER
        /// release than the one being reported. This case cannot drift that way:
        /// the string that was compared is the string that gets downloaded.
        case versionTemplate(String)
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

    /// Distinguishes several recipes that share a bundle id AND a channel — the
    /// case where one channel has more than one endpoint worth asking and the
    /// source takes the highest answer (see `VendorProbeSource.probeDiagnostic`).
    /// Nil for the overwhelmingly common one-endpoint recipe, which keeps its
    /// `recipeID` — and so its verify baseline and issue history — unchanged.
    public let variant: String?

    /// The endpoint to probe (a stable "latest" redirect, or a version API).
    ///
    /// When `identity` is set this carries its placeholder token and is NOT a
    /// fetchable URL on its own; the substitution happens inside the fetch. It is
    /// still the value reported everywhere (logs, verify findings), which is what
    /// keeps the machine's identifier out of them.
    public let url: URL

    /// Set when the endpoint only answers for a specific machine, and the app
    /// keeps the identifier it keys on, on disk. Each entry substitutes its own
    /// placeholder, and all are applied before the request. See `ProbeIdentity`
    /// for why a synthesized value is not an acceptable substitute, and for the
    /// handling rules.
    ///
    /// Identities only. A value that selects which BUILDS come back rather than
    /// which bucket this machine is in belongs in `track` — the two look alike
    /// in the URL and behave nothing alike when they are wrong.
    public let identities: [ProbeIdentity]

    /// Set when the endpoint serves several tracks off one URL and a
    /// request-borne value picks between them. Substituted exactly like an
    /// identity; kept apart from one because it is not a machine identifier and
    /// because it carries what a verification sweep needs to tell whether it is
    /// doing anything. See `RolloutTrack`.
    public let track: RolloutTrack?

    /// Every local value this recipe substitutes into its URL: its identities,
    /// plus its track's selector if it has one.
    ///
    /// Exists so the rules that apply to "a value read off this machine and put
    /// on the wire" — distinct placeholders, a fallback that survives its own
    /// validation, nothing baked into `recipe.url`, no unreviewed read out of a
    /// credential file — are checked against ONE derived list. Splitting the
    /// plan out of `identities` broke two such guards the day it happened, which
    /// is the argument for deriving rather than enumerating.
    public var localReads: [ProbeIdentity] {
        identities + (track.map { [$0.selector] } ?? [])
    }

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

    /// Optional regex (capture group 1) for the release's publish timestamp, read
    /// from the same response body and parsed by `ReleaseDate` (ISO8601, RFC822 or
    /// a bare epoch). Routed into `RemoteVersion.publishedAt`, which is what the
    /// Release Log timeline uses to place a release *exactly* instead of falling
    /// back to an estimated "≈" window.
    ///
    /// Only set this when the endpoint states the date of the release the
    /// `versionPattern` matched — it takes the FIRST match, so on a multi-entry
    /// feed it must live in the same (newest-first) entry, or a version would be
    /// stamped with another release's date. Nil (the default, and correct for most
    /// recipes) simply means "no authoritative time", which the timeline records as
    /// absent. Meaningless for `.redirectFilename`/`.zipEntryPlist`, where the
    /// probed text is a URL or a single plist value rather than a document.
    public let publishedAtPattern: String?

    /// When present, the app can be updated in place through its own channel: the
    /// source resolves the installer URL (and optional checksum) and hands it to
    /// `VendorInstaller`. Absent → detection only (the user is sent to download
    /// by hand). Only set this for official-website installs, where a vendor
    /// download is the *same* channel the app came from (no cross-channel mixing).
    public let install: VendorInstallSpec?

    /// A request body to POST instead of issuing a plain GET. Only meaningful
    /// with `.responseBody`.
    ///
    /// Exists for update services that answer nothing at all to a GET — Google's
    /// Omaha (`update.googleapis.com/service/update2/json`) wants a JSON document
    /// naming the app, the platform and the version you already have, and replies
    /// with either "noupdate" or the full manifest for the newest build. Asking
    /// with a deliberately ancient version (`0.0.0.0`) is what turns a
    /// "should I update?" service into a "what is the latest?" one, so the body
    /// each recipe carries is a fixed document, not one built from the install.
    ///
    /// The reply is prefixed with Google's anti-JSON-hijacking `)]}'` line; no
    /// stripping is needed because `versionPattern` is a regex over the raw text,
    /// which simply skips it.
    public let requestBody: RequestBody?

    /// A fixed request body and its content type.
    public struct RequestBody: Sendable, Hashable {
        public let contentType: String
        public let json: String

        public init(contentType: String = "application/json", json: String) {
            self.contentType = contentType
            self.json = json
        }
    }

    /// When false, the probe does NOT follow HTTP redirects: it reads the
    /// redirect response itself (status 3xx, its small body / `Location`). Needed
    /// for endpoints that 302 to a huge binary — following would download the
    /// whole installer just to read a version (e.g. Warp's download gateway,
    /// which only redirects on GET).
    public let followRedirects: Bool

    /// Request headers layered on top of the probe's defaults (they win on a key
    /// collision, `User-Agent` included).
    ///
    /// The default UA is deliberately browser-like because several vendor sites
    /// reject unfamiliar agents — but a few WAFs invert that test and refuse a
    /// browser UA arriving without the rest of a browser's fingerprint.
    /// SourceForge is the measured case: `sourceforge.net/projects/<p>/best_release.json`
    /// answers 200 to `curl`'s own UA and to `DuoUpdater/0.1`, and **403** to the
    /// exact Safari UA this probe otherwise sends (2026-08-16, same second, same
    /// host — the only variable was the UA string).
    public let requestHeaders: [String: String]

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
        publishedAtPattern: String? = nil,
        install: VendorInstallSpec? = nil,
        requestBody: RequestBody? = nil,
        requestHeaders: [String: String] = [:],
        followRedirects: Bool = true,
        channel: ReleaseChannel = .stable,
        identities: [ProbeIdentity] = [],
        track: RolloutTrack? = nil,
        variant: String? = nil
    ) {
        self.bundleID = bundleID
        self.channel = channel
        self.url = url
        self.identities = identities
        self.track = track
        self.variant = variant
        self.mode = mode
        self.versionPattern = versionPattern
        self.downloadURL = downloadURL
        self.changelogURL = changelogURL
        self.selectHighest = selectHighest
        self.versionIsBuild = versionIsBuild
        self.displayVersionPattern = displayVersionPattern
        self.publishedAtPattern = publishedAtPattern
        self.install = install
        self.requestBody = requestBody
        self.requestHeaders = requestHeaders
        self.followRedirects = followRedirects
    }

    /// Extract a version from `text` using `pattern`. Pure and side-effect-free
    /// — this is the fragile, format-specific bit, so it's factored out for
    /// unit testing without touching the network. Returns nil when the pattern
    /// is invalid or doesn't match (the caller then degrades to "unknown").
    /// The same pattern with its fixed run of version segments made variable.
    ///
    /// A pattern that hard-codes how many dot-separated numbers a version has is
    /// the single most common way a recipe dies silently: Zotero shipped `10.0`
    /// where every release before it had three segments, the pattern stopped
    /// matching, and the app simply vanished from the update list with no error
    /// anywhere. 33 of the registry's patterns still pin an exact count — audited
    /// 2026-08-19 against every live endpoint, and for all but one the count is
    /// not load-bearing today, so widening them wholesale would be churn without
    /// evidence. Detecting the day it stops being true is worth more.
    ///
    /// Returns nil when the pattern pins no segment run, so a caller can tell
    /// "this diagnosis does not apply" from "it applies and found nothing".
    static func segmentCountRelaxed(_ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"\[0-9\]\+(?:\\\.\[0-9\]\+)+"#) else { return nil }
        let ns = pattern as NSString
        guard let m = re.firstMatch(
            in: pattern, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return ns.replacingCharacters(
            in: m.range, with: #"[0-9]+(?:\.[0-9]+){1,4}"#)
    }

    /// What a pattern WOULD have matched if it did not pin the segment count.
    /// Used only to explain a miss; never to produce a version we act on.
    static func versionIfSegmentCountRelaxed(
        from body: String, pattern: String
    ) -> String? {
        guard let relaxed = segmentCountRelaxed(pattern), relaxed != pattern
        else { return nil }
        return extractVersion(from: body, pattern: relaxed)
    }

    public static func extractVersion(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return version(of: match, in: text)
    }

    /// The version a match stands for: capture group 1, the whole match when the
    /// pattern captures nothing, or — when it captures more than once — every
    /// group joined with `.`.
    ///
    /// The joining case exists for versions a vendor won't let us capture in one
    /// span. Warp's feed says `v0.2026.08.05.09.03.stable_01` while the app it
    /// installs reports `0.2026.08.05.09.03.01`: the build counter sits behind the
    /// channel name, so a single group has to stop before it. Dropping the counter
    /// isn't cosmetic — two builds cut from the same timestamp then read as one
    /// version, and the second one is invisible.
    private static func version(of match: NSTextCheckingResult, in text: String) -> String? {
        guard match.numberOfRanges > 1 else {
            guard let whole = Range(match.range(at: 0), in: text) else { return nil }
            return String(text[whole])
        }
        let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
            let group = match.range(at: index)
            guard group.location != NSNotFound, let r = Range(group, in: text) else { return nil }
            return String(text[r])
        }
        return groups.isEmpty ? nil : groups.joined(separator: ".")
    }

    /// Like `extractVersion`, but returns capture group 1 of the LAST match —
    /// for ascending-order feeds where the newest entry comes last. Pure, for the
    /// same reason `extractVersion` is.
    public static func lastMatch(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard let match = matches.last else { return nil }
        return version(of: match, in: text)
    }

    /// Like `extractVersion`, but when the pattern matches several times (an
    /// appcast/feed listing many releases, often in ascending order) it returns
    /// the *highest* version, not the first. Single-match bodies behave exactly
    /// like `extractVersion`. This is the right default for vendor probes —
    /// "first in the document" is not reliably "newest", but max-by-version is.
    /// Pick a download by the version it declares about *itself*: group 1 is the
    /// URL, group 2 the version that same entry carries, and the highest version
    /// wins — whatever order the feed lists its entries in.
    ///
    /// Positional selection (`extractVersion`'s first match, `lastMatch`'s last) is
    /// a bet on the vendor's ordering, and losing it is silent. Docker's appcast
    /// lists 4.86.0 *before* 4.87.0: first-match downloaded the 4.86.0 image
    /// (573976729 bytes, exactly that entry's `length`), installed it over the
    /// 4.86.0 already on disk, and the row went on offering 4.87.0 — after 574 MB
    /// of download and a 2.26 GB backup. Reading each candidate's own version takes
    /// ordering out of the decision entirely.
    public static func highestVersionedURL(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var best: (url: String, version: String)?
        for match in regex.matches(in: text, options: [], range: range) {
            // Both groups are required: a pattern that captures only the URL would
            // otherwise silently degrade to "first match wins", which is the bug.
            guard match.numberOfRanges > 2,
                  let urlRange = Range(match.range(at: 1), in: text),
                  let versionRange = Range(match.range(at: 2), in: text)
            else { continue }
            let candidate = (url: String(text[urlRange]), version: String(text[versionRange]))
            if best == nil || VersionComparator.isNewer(candidate.version, than: best!.version) {
                best = candidate
            }
        }
        return best?.url
    }

    public static func highestVersion(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var best: String?
        for match in regex.matches(in: text, options: [], range: range) {
            guard let candidate = version(of: match, in: text) else { continue }
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
            versionPattern: #"WhatsApp-[0-9]+\.([0-9]+(?:\.[0-9]+){1,2})\.dmg"#,
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
        // No `changelogURL`: there is no such page. `uuyc.163.com/changelog` and
        // `/update` both answer 200, but they return byte-identical content to a
        // path that does not exist — an SPA catch-all serving the homepage, not a
        // changelog. The download page is a distinct page but contains no
        // 更新日志/更新说明/新增/修复 markers at all. (Checked 2026-08-22.)
        VendorProbeRecipe(
            bundleID: "com.netease.uuremote",
            url: URL(string: "https://api.nrd.nie.163.com/api/v1/release/dl/4?channel=gwqd")!,
            mode: .redirectFilename,
            versionPattern: #"uuyc_([0-9]+(?:\.[0-9]+)+)\.pkg"#,
            // The probe endpoint above 302s straight to the pkg, so it must never
            // be what a "download page" link opens — that just downloads a file.
            // uuyc.163.com is the product's own site (网易UU远程官网).
            downloadURL: URL(string: "https://uuyc.163.com/"),
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
            versionPattern: #""name"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
            versionPattern: #""build"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
        // swap to a newer build does not confuse it. Under the default we install
        // over a running Chrome and restart it; picking "defer while running"
        // instead brings it forward to update itself.
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

        // Microsoft OneNote — Office suite, unified version. MAU-managed, and read
        // from the MAU manifest rather than the suite fwlink, the same way Outlook
        // is below.
        //
        // It used to use the suite fwlink (linkid=525133), on the reasoning that
        // there is no dedicated OneNote fwlink and the suite reports the same
        // version. That is true for DETECTION and wrong for INSTALL: that link
        // serves `Microsoft_365_and_Office_<build>_Installer.pkg`, which declares
        // eight destinations — Word, Excel, PowerPoint, Outlook, OneNote, OneDrive,
        // AutoUpdate and a Defender shim. Someone who has only OneNote installed
        // and clicks Update would have had the entire Office suite put on their
        // machine. Verified 2026-08-19 by parsing the real 2.7 GB suite package.
        //
        // `FullUpdaterLocation` in the MAU manifest is a standalone 592 MB
        // OneNote package that declares exactly one destination,
        // `/Applications/Microsoft OneNote.app` (verified the same way), signed
        // `Developer ID Installer: Microsoft Corporation (UBF8T346G9)`.
        //
        // It must be `FullUpdaterLocation` and not `Location`/`Payload`: those are
        // deltas keyed to a specific starting build, and applying one without its
        // baseline installs a broken app.
        VendorProbeRecipe(
            bundleID: "com.microsoft.onenote.mac",
            url: URL(string: "https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409ONMC2019.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>Update Version</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onenote/digital-note-taking-app")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>FullUpdaterLocation</key>\s*<string>(https://[^<\s]+/Microsoft_OneNote_[0-9.]+_Updater\.pkg)</string>"#),
                kind: .pkg)),

        // Microsoft Outlook — Office suite, unified version. Uses the Office
        // AutoUpdate XML manifest (same CDN product tree as the fwlinks), an
        // ARRAY of update dicts. MAU-managed.
        //
        // The manifest is a plist, so each dict's keys are ALPHABETICAL and the
        // newest release comes first, which is why every first-match pattern here
        // reads out of the same (first) dict.
        //
        // One-click repaired 2026-08-09. The old install spec read
        // `<key>Update Version Location</key>`, a key Microsoft has since removed
        // — the version still resolved, so the row quietly degraded to
        // detection-only with no error anywhere. Today's payload keys, and what
        // each actually points at (verified against the live manifest):
        //
        //   Location / Payload      → `Outlook_<baseline>_to_<new>_Delta.pkg` on
        //                             the 24 delta entries — a PARTIAL payload
        //                             (504MB, 185 bundles, installKBytes 1117435)
        //   BinaryUpdaterLocation   → `…_BinaryDelta.pkg`, a 18–216MB binary patch
        //   FullUpdaterLocation     → `Microsoft_Outlook_<build>_Updater.pkg`, the
        //                             full standalone package (1.29GB, 210 bundles,
        //                             installKBytes 2664652, choice customLocation
        //                             /Applications)
        //
        // Only the full updater is installable. Neither delta carries a baseline
        // guard — their `InstallationCheck()` only tests the min OS version — so
        // running one against the wrong installed build would silently lay down a
        // partial Outlook.
        //
        // The URL is READ from `FullUpdaterLocation`, not assembled from the
        // version — same call as AweSun's 0.3.13 fix (building the filename from
        // the version broke the moment Oray renamed the file). It also means the
        // CDN move Microsoft is midway through follows automatically: payload URLs
        // now point at `res.public.onecdn.static.microsoft` while only the manifest
        // itself still lives on `officecdn.microsoft.com`. Both patterns take the
        // first match, so both read out of the same first dict — the pkg is the
        // build we report (`duo verify` re-checks that against the live endpoint,
        // and `microsoftOutlookInstallURLMatchesProbedBuild` guards it in CI).
        //
        // The `Microsoft_Outlook_<build>_Updater.pkg` shape is part of the pattern
        // on purpose: key order inside a dict is alphabetical, so BinaryUpdater
        // (B) and the delta `Location` (L) bracket the one key we want, and the
        // filename guard is what makes a delta unmatchable no matter how the
        // manifest is reordered.
        //
        // Version scheme: `Update Version` is the BUILD (16.109.26053122), not the
        // marketing string — the pkg's own Distribution declares
        // CFBundleShortVersionString 16.109.3 / CFBundleVersion 16.109.26053122 —
        // hence `versionIsBuild`. Signed `Developer ID Installer: Microsoft
        // Corporation (UBF8T346G9)`, the same Team as the installed app (read from
        // the pkg's xar signature 2026-08-09, no full download needed).
        VendorProbeRecipe(
            bundleID: "com.microsoft.Outlook",
            url: URL(string: "https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409OPIM2019.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>Update Version</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/outlook/outlook-for-business")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>FullUpdaterLocation</key>\s*<string>(https://[^<\s]+/Microsoft_Outlook_[0-9.]+_Updater\.pkg)</string>"#),
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
            versionPattern: #"sparkle:shortVersionString="([0-9]+(?:\.[0-9]+){1,3})""#,
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
        // `dev.warp.Warp-Stable` recipe above. Both capture groups matter: the app
        // reports the feed's `v<stamp>.<channel>_NN` as `<stamp>.NN`, so the
        // counter is joined back on (see `VendorProbeRecipe.version(of:in:)`).
        // Confirmed against real bundles on all three tracks in
        // `application-test/records/dev-warp-Warp-Stable.md` — including dev's
        // `_00`, which the app does spell out as a trailing `.00`.
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
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.preview_([0-9]+)""#,
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
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.dev_([0-9]+)""#,
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
        // `[^"]*` field bounds hold.
        //
        // We compare BUILDS, not the marketing version: the page names the current
        // installer as `WeTypeInstaller_2.2.2_647_<letter>.zip`, and the installed
        // bundle's `CFBundleVersion` is that same `647`, so both sides speak the
        // same scheme. Those installer links exist only for the CURRENT release
        // (verified 2026-08-16: the whole page yields exactly one version/build
        // pair). `displayVersionPattern` keeps the row reading `2.2.2` rather than a
        // bare `647`, and it reads that string out of the SAME filename — which
        // matters twice over: display extraction is first-match with no
        // `selectHighest`, and this page lists releases oldest-first, so the
        // `"platform":3`-gated object pattern would have shown the very first
        // macOS release ever published beside the current build.
        //
        // If a future page ever drops the installer links, the build pattern misses
        // and the probe degrades to "unknown" — never to a wrong version.
        //
        // DETECTION ONLY — the one-click was built, shipped in 0.3.25, and then
        // WITHDRAWN on 2026-08-16 after a user lost their WeType settings during
        // that work. State the evidence plainly, because it does not add up to a
        // proof and the decision does not depend on one:
        //   * `/Library/Input Methods/WeType.app` was never replaced by us — its
        //     mtime is still the vendor install's (Aug 6) and it is 2.2.2/647.
        //     The elevated swap never actually ran on this machine.
        //   * What DID run, during the one-click work, was a staged OLDER copy
        //     (2.2.1) placed in `~/Applications`, installed over, and the running
        //     input method restarted twice. `~/Library/Application Support/WeType/`
        //     `userDict` and `mmkv` were rewritten inside that window.
        // So the swap is not convicted; a second, older copy of an input method
        // registering itself is. Either way the blast radius is the user's own
        // dictionary and settings, and this class of app is not one to learn on.
        //
        // The real reason a bundle swap was always the wrong shape here: the
        // vendor's own `WeTypeInstaller.app` does more than copy. Its binary
        // carries `Registered input source from /Library/Input Methods/WeType.app,
        // result:` — it REGISTERS the input source with the system, and whatever
        // per-version migration sits alongside that. Replacing the bundle skips
        // every one of those steps.
        //
        // Kept for whoever revisits this: the real payload (not the ~3 MB stub the
        // page links) is `download.weread.qq.com/app/wxkb/mac/<ver>/WeType_<ver>_<build>.zip`,
        // constructible from the version+build this recipe already extracts, and
        // verified in 2026-08 to be a notarized `WeType.app`, Team 88L2Q4487U.
        // The missing piece is not the URL — it is doing the vendor installer's
        // registration/migration, which nothing here does.

        // Read the endpoint the vendor's OWN installer reads, not the marketing
        // page. `WeTypeInstaller.app` is an 8 MB stub that ships no payload — it
        // GETs `?channel=InstallInfo`, which 302s to a per-build JSON manifest:
        //
        //   {"zip_download_url": ".../2.2.3/WeType_2.2.3_657.zip",
        //    "zip_version": "2.2.3.657", "zip_download_md5": "…"}
        //
        // The previous recipe read `WeTypeInstaller_<x.y.z>_<build>_<letter>.zip`
        // filenames off `z.weixin.qq.com/web/change-log/macos`. Those numbers are
        // **the installer stub's own version, not the app's** — the stub in hand
        // is 2.2.0 (643) and installs 2.2.3 (657). The two tracked each other
        // closely enough for a while to look right, which is exactly how a
        // wrong-scheme recipe survives: it never fails, it just answers with a
        // number from the wrong namespace. `remote is BEHIND the installed copy`
        // in the nightly sweep is what finally caught it.
        //
        // That page also lags on its own account — its embedded per-platform JSON
        // still listed Mac at 2.2.2 while 2.2.3 was shipping — so neither the
        // filenames nor the notes on it are a version source.
        //
        // Still detection-only, and that has nothing to do with where the version
        // comes from: this endpoint hands over a perfectly good payload URL and an
        // md5. Overwriting the bundle skips the stub's input-source registration
        // and per-version migration, and was measured to lose user settings. See
        // the note above.
        VendorProbeRecipe(
            bundleID: "com.tencent.inputmethod.wetype",
            url: URL(string: "https://z.weixin.qq.com/web/mac/download?channel=InstallInfo")!,
            mode: .responseBody,
            versionPattern: #""zip_version"\s*:\s*"[0-9]+(?:\.[0-9]+){2}\.([0-9]+)""#,
            downloadURL: URL(string: "https://z.weixin.qq.com/"),
            changelogURL: URL(string: "https://z.weixin.qq.com/web/change-log/macos"),
            versionIsBuild: true,
            displayVersionPattern: #""zip_version"\s*:\s*"([0-9]+(?:\.[0-9]+){2})\.[0-9]+""#),

        // 豆包输入法 (DoubaoIme) — ByteDance's input method, installed from
        // `shurufa.doubao.com` into `/Library/Input Methods`. No SUFeedURL, no MAS
        // receipt, no Homebrew cask (the `doubao` cask ships `doubao.app`, the
        // unrelated AI chat client), so nothing in the priority chain answered and
        // the row sat on "unknown" — it was scanned but never checked.
        //
        // The site's own download button reads this endpoint (`platform` ∈
        // android/ios/macos/windows), which is the vendor's statement of what the
        // current shipping build is:
        //
        //   {"code":0,"data":{"url":".../DoubaoImeInstaller_v90602_release.zip",
        //    "version_code":1002007,"version_name":"V0.9.6"},"msg":"success"}
        //
        // VERSION SCHEME — three numbers in this response, and which one to compare
        // is the whole recipe:
        //   * the `v90602` in the zip filename is the vendor's version code, and the
        //     installed bundle carries THE SAME NUMBER in its custom Info.plist key
        //     `Wave Build Version Number` (also spelled `0.9.6.2` in
        //     `Wave Build Version`). `AppScanner` reads that key in place of
        //     `CFBundleVersion`, which is a flat "1" on every build. This pair is
        //     what we compare — exact, respins included.
        //   * `version_name` "V0.9.6" is the marketing string, and is what the row
        //     SHOWS (`displayVersionPattern`); it equals the installed
        //     `CFBundleShortVersionString`.
        //   * `version_code` 1002007 is a THIRD namespace that matches nothing local.
        //     Never compare it.
        //
        // The first draft of this recipe compared only the marketing version, on the
        // mistaken reading that 90602 had no local counterpart. It does — it is just
        // not under a standard key. The cost of that draft was a blind spot for
        // same-marketing-version respins (90601 → 90602, both "0.9.6"); comparing the
        // vendor's own code closes it.
        //
        // If the vendor ever drops that Info.plist key, `AppScanner` reports NO build
        // rather than falling back to "1", and `evaluate()` returns to comparing
        // `version_name` against the installed marketing version — degraded, but
        // never a phantom. See `AppScanner.waveBuildVersionNumber`.
        //
        // No `changelogURL` — the marketing site has no release-notes page at all.
        // The notes come from the ChangelogRecipe over `ime.doubao.com`'s update
        // feed, which is structured; there is nothing worth embedding as a fallback.
        //
        // DETECTION-ONLY, and not for want of an artifact: this response hands over a
        // notarized installer zip. `UpdatePolicy.isInputMethod` refuses one-click for
        // anything under `/Library/Input Methods` as a whole CLASS, after WeType's
        // one-click was withdrawn for losing user settings — an input method is
        // registered with the system by its vendor installer, not merely copied, and
        // the payload here is exactly that: `DoubaoImeInstaller.app`, a 202 MB stub
        // whose `Contents/Resources` holds `DoubaoIme.zip` + `install.sh`. Swapping
        // the bundle would skip the registration step entirely.
        VendorProbeRecipe(
            bundleID: "com.bytedance.inputmethod.doubaoime",
            url: URL(string: "https://ime.doubao.com/api/v1/app/download_url?platform=macos")!,
            mode: .responseBody,
            versionPattern: #"DoubaoImeInstaller_v([0-9]+)_release\.zip"#,
            downloadURL: URL(string: "https://shurufa.doubao.com/"),
            versionIsBuild: true,
            displayVersionPattern: #""version_name"\s*:\s*"[Vv]?([0-9]+(?:\.[0-9]+)+)""#),

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

        // 微信开发者工具 (WeChat DevTools) — Tencent's mini-program IDE, three
        // parallel channels: 稳定版 Stable, 预发布版 RC, 开发版 Nightly. All three are
        // the SAME install (one bundle, one app name), and since the 2.02 Electron
        // rewrite they all report `com.github.Electron` / `36.6.0` in Info.plist —
        // the channel AND the real version come from the app's own `package.json`
        // instead, and `AppScanner` re-files the install under the canonical
        // `com.tencent.wechatdevtools` these recipes key on. See
        // `AppScanner.weChatDevToolsIdentity`.
        //
        // ONE endpoint serves all three channels: `config.json` is what the official
        // docs site's own changelog page (`devtools/log.html`, a Vue SPA) reads to
        // render its download buttons — `channels[]` with `id` / `version` / macOS
        // `downloads[]`. Each recipe anchors on its own `"id": "<channel>"` and takes
        // the nearest following `version` and arm64 pkg URL, so a channel can never
        // read a sibling's build. Nightly's anchor is exact-quoted for a second
        // reason: the document also carries a `"nightly-old"` entry (the retired
        // NW.js 2.01 train), and an unanchored `nightly` prefix would match it.
        //
        // NOT the old `servicewechat.com/wxa-dev-logic/download_redirect?…&
        // version_type=N` endpoint: measured 2026-08-18, it ignores `version_type`
        // entirely and 302s all three values to the same Stable dmg.
        //
        // One-click: the arm64 `.pkg`, `Developer ID Installer: Tencent Technology
        // (Shanghai) Co., Ltd (FN2V63AD2J)`, notarized on all three channels
        // (checked with `pkgutil --check-signature` on 2.02.2608031 / 2608040 /
        // 2608182) — same Team as the installed app, so the signature gate holds.
        VendorProbeRecipe(
            bundleID: "com.tencent.wechatdevtools",
            url: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .responseBody,
            versionPattern: #""id":\s*"stable"[\s\S]*?"version":\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html"),
            changelogURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/log.html#stable"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""id":\s*"stable"[\s\S]*?"url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#),
                kind: .pkg),
            channel: .stable),
        VendorProbeRecipe(
            bundleID: "com.tencent.wechatdevtools",
            url: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .responseBody,
            versionPattern: #""id":\s*"rc"[\s\S]*?"version":\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html"),
            changelogURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/log.html#rc"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""id":\s*"rc"[\s\S]*?"url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#),
                kind: .pkg),
            channel: .rc),
        VendorProbeRecipe(
            bundleID: "com.tencent.wechatdevtools",
            url: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .responseBody,
            versionPattern: #""id":\s*"nightly"[\s\S]*?"version":\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html"),
            changelogURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/log.html#nightly"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""id":\s*"nightly"[\s\S]*?"url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#),
                kind: .pkg),
            channel: .nightly),

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
        // No `changelogURL`: the vendor's macOS log page exists but is abandoned.
        // `update.todesk.com/macos/uplog.html` is server-rendered with 30 real
        // versions, and its newest is 4.8.1.0 (2025.9.5) — while the installed
        // copy here is 4.10.0.0. It is not the whole site going stale: the same
        // host's `windows/uplog.html` was current to 2026.8.18 on the same day.
        // Pointing the pane at it would show notes for a version the user passed
        // two minor releases ago, which is the version-mismatch failure the
        // Notion and Figma changelogs were just moved away from.
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
        // No `changelogURL`, and not an oversight: Spotify publishes no release
        // notes for the desktop client anywhere. Checked 2026-08-22 — the only
        // things that exist are one-off community forum posts from a decade ago
        // (0.9.x, 1.0.9) and long-running threads asking for a changelog.
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
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
            // And the entry is chosen by the version it declares, not by position:
            // this feed is NOT newest-first. On 2026-08-17 it listed 4.86.0 (build
            // 236216) ahead of 4.87.0 (236836), so a first-match download fetched
            // 4.86.0 over an installed 4.86.0 — 574 MB, a 2.26 GB backup, "install
            // done", and the update still pending. `sparkle:shortVersionString` sits
            // in the same tag as the URL, so the two can no longer disagree.
            //
            // Verified 2026-08-09 on 4.85.0 (build 235549): `Docker.app` in the
            // image, bundle id com.docker.docker, Team 9BNSXJN65R, spctl "Notarized
            // Developer ID". 573 MB, arm64-specific feed path.
            install: VendorInstallSpec(
                urlSource: .bodyPatternHighestVersioned(
                    #"<enclosure[^>]*url="(https://desktop\.docker\.com/[^"]+/Docker\.dmg)"[^>]*sparkle:shortVersionString="([0-9][0-9.]*)""#),
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

        // Claude desktop — TWO endpoints, both listed, highest wins (see
        // `VendorProbeSource.best`). Anthropic runs a staged rollout, so "latest"
        // genuinely has two answers and which leads flips during a ramp:
        //
        //   1. the public GA redirect below — what claude.ai/download serves;
        //   2. the Squirrel rollout endpoint above — what THIS machine's own
        //      updater acts on, keyed by its device id.
        //
        // Neither alone is right. GA alone goes blind for the whole ramp: on
        // 2026-08-15, 1.30096.5 had been on the CDN for a day and the app's own
        // updater had already staged it for relaunch, while GA still said
        // 1.30096.1 — we'd have reported "up to date" the entire time. The rollout
        // endpoint alone would go blind the other way if a bucket is held back.
        //
        // The old reason for skipping the rollout endpoint — a synthetic device id
        // lands in an unrelated bucket, hiding real updates when behind and
        // inventing them when ahead — is answered by reading the id Claude itself
        // wrote (`ProbeIdentity`), not by inventing one.

        // (1) Public GA download redirect: no id, the current GA build, exactly
        // what the website's download button gives.
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
            versionPattern: #"/darwin/universal/([0-9]+(?:\.[0-9]+){1,3})/"#,
            downloadURL: URL(string: "https://claude.ai/download"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://downloads\.claude\.ai/releases/darwin/universal/[0-9.]+/Claude-[0-9a-f]+\.zip)"#),
                kind: .zip),
            followRedirects: false,
            variant: "ga"),

        // (2) Claude desktop — the staged-rollout endpoint its own Squirrel
        // updater calls. `device_id` is REQUIRED (no id → HTTP 400) and selects
        // the rollout bucket: four synthetic ids sampled on 2026-08-15 answered
        // .1/.5/.1/.1, which is exactly why the id must be this machine's real one
        // (`~/Library/Application Support/Claude/ant-did`, a base64-wrapped UUID)
        // and never a fabricated one. With the real id the answer is, by
        // construction, what Claude's own updater will do.
        //
        // The response is small JSON:
        //   {"currentRelease":"1.30096.5","releases":[{"version":…,"updateTo":{
        //     "name":…,"version":…,"pub_date":"2026-08-14T22:50:24.042387",
        //     "url":"https://downloads.claude.ai/releases/…zip","notes":…}}]}
        // `currentRelease` is the authoritative "what this device should be on" —
        // it's returned whether or not the device is behind, so the install URL
        // always resolves and there's no spurious `installURLUnresolved` once
        // we're current.
        //
        // The id rides in the query at fetch time only; `url` here keeps the
        // placeholder, and that is the copy logs and verify findings carry.
        // One-click is safe for the same reason as (1) and then some: this is
        // precisely the build allocated to this machine. Team Q6L2SF6YDW gates
        // the swap. `pub_date` is UTC (39s after the artifact's Last-Modified),
        // and it's what finally gets Claude into the Release Log timeline.
        VendorProbeRecipe(
            bundleID: "com.anthropic.claudefordesktop",
            url: URL(string: "https://api.anthropic.com/api/desktop/darwin/universal/squirrel/update?device_id=__IDENTITY__")!,
            mode: .responseBody,
            versionPattern: #""currentRelease"\s*:\s*"([0-9][0-9.]*)""#,
            downloadURL: URL(string: "https://claude.ai/download"),
            publishedAtPattern: #""pub_date"\s*:\s*"([0-9T:.\-]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://downloads\.claude\.ai/releases/darwin/universal/[0-9.]+/Claude-[0-9a-f]+\.zip)"#),
                kind: .zip),
            identities: [ProbeIdentity(
                applicationSupportPath: "Claude/ant-did",
                encoding: .base64,
                validationPattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#)],
            variant: "rollout"),

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

        // Codex — the endpoint ChatGPT's own updater asks, not the feed it ships
        // configured with. Those are different answers, which is the whole reason
        // this recipe looks like this.
        //
        // The app's `codexSparkleFeedUrl` is
        // `persistent.oaistatic.com/codex-app-prod/appcast.xml`, and reading it is
        // what we used to do. But `production-appcast-bootstrap.json` carries
        // `backendAppcastEnabled: true`, and Sparkle then asks the endpoint below,
        // which 307s to a per-target `appcast-<version>.xml`. The static file is a
        // PUBLISHING manifest; the redirect target is what the vendor is actually
        // shipping. On 2026-08-22 they disagreed for hours — the static feed listed
        // 26.818.41705 (published 06:11Z, real zip, real signature) while every
        // machine asking the endpoint was told 26.818.41509 was newest. Installing
        // the published-but-unshipped build starts a fight the app wins: its own
        // Sparkle stages 41509, waits for a quit, and our restart is the quit.
        //
        // That is also why this REPLACES the static feed rather than joining it as
        // a second endpoint. `VendorProbeSource.best(of:)` takes the highest, sound
        // only under its stated precondition — every endpoint must serve "a build
        // this machine may legitimately install". The publishing manifest doesn't.
        //
        // `app_version` is required (omit it, or send something unparseable, and
        // there is no redirect) but does not participate: 0.0.0, the installed
        // version, and 99.999.99999 all resolved to the same target. A sentinel is
        // deliberate — if OpenAI ever does step upgrades, 0.0.0 is the value most
        // likely to be rejected outright, which `duo verify` reports, rather than
        // to answer plausibly and wrongly. The app also sends `os-version` and a
        // `codex_cache_bust` counter; neither changes the redirect target
        // (measured 2026-08-24: os-version 13.0.0 / 26.0.0 / 27.0.0 / omitted
        // resolve alike, and the counter is not stable even across the app's own
        // checks — 8, then 2, then 4), so this URL stays as short as it can be.
        //
        // `installation_id` selects the rollout bucket and grants nothing; see
        // `ProbeIdentity` for why it never reaches a log, a report, or the
        // recipe's own recorded URL.
        //
        // `plan_type` is the second thing the endpoint keys on, and unlike
        // `app_version` it decides the answer. Measured 2026-08-24, same
        // installation_id, only this parameter varying:
        //
        //     free | go | plus | pro | team   → appcast-26.818.61809.xml
        //     business | enterprise | ent26   → appcast-26.818.41509.xml
        //     unknown | omitted | nonsense    → appcast-26.818.41509.xml
        //
        // Two rollout tracks, not per-tier builds: the five consumer values
        // return byte-identical XML, as do the three enterprise ones. The
        // enterprise feed does not merely sort 61809 lower — it has no such
        // item. This is the "enterprise-plan recognition" of openai/codex
        // 0.146.0 (PRs #35238, #35537): business tiers roll out behind consumer
        // ones so IT can qualify a build.
        //
        // The split is a WINDOW, not a standing structure: by 15:29Z the same
        // day every value above — `business`, `enterprise` and omitted included
        // — resolved to 26.818.61809. So nothing can assert on the split, and
        // `duo verify` cannot tell whether this parameter is doing anything:
        // outside the window both answers agree. It earns its place only inside
        // the window, which is exactly when getting it wrong starts the fight
        // described below.
        //
        // So omitting it is not neutral — it silently books this machine onto
        // the enterprise track. That is what made `duo verify` report "remote is
        // BEHIND the installed copy" while ChatGPT itself was installing 61809.
        // And hardcoding a consumer value is worse than omitting: on an actual
        // business account we would offer a build that account's own updater
        // refuses, which is precisely the fight described above — its Sparkle
        // stages the older build, waits for a quit, and our restart is the quit.
        //
        // Hence reading the real value. It is an account attribute rather than a
        // machine id, so it lives with the account state in `~/.codex/auth.json`
        // — ChatGPT.app bundles the `codex` CLI at `Contents/Resources/codex`
        // and both resolve `CODEX_HOME ?? ~/.codex`, so it is one file for one
        // product. `ProbeIdentity.jwtClaim` reaches that one claim and nothing
        // else. Absent — never signed in, or the file moved — falls back to
        // "unknown", which is what OpenAI's own `codex doctor` hardcodes
        // (codex-rs/cli/src/doctor/updates.rs) and which lands on the cautious
        // track: the same answer we gave before this parameter existed.
        //
        // What is shared is the FILE and the LOGIN EVENTS. The VALUE is not.
        // Measured on one machine, 2026-08-24:
        //
        //   * signing out of ChatGPT.app DELETES `~/.codex/auth.json`, after
        //     which `codex login status` reports "Not logged in" — the app
        //     drives that file;
        //   * signing in again through `codex` recreates it, and the app returns
        //     to a signed-in state on its own;
        //   * but with the file holding a `team` token while the app's session
        //     was `free`, the app sent `plan_type=free` and never touched the
        //     file (mtime unchanged). It does not consult this file to answer.
        //
        // The app builds its value from the live session of the ACTIVE account
        // (`setSparkleQueryParams({beta, planType})`, fed from the account
        // object; default `unknown`), and that plan is not persisted anywhere we
        // can read — `~/Library/Application Support/com.openai.codex/` holds
        // only the bootstrap json above and a web session directory. So this
        // claim is the best local source that exists, not the app's own value.
        //
        // Ours is right whenever the login is the one the app is using — the
        // ordinary case, and strictly better than omitting the parameter (which
        // books every machine onto the enterprise track) or hardcoding one
        // (wrong in the dangerous direction on a business account). But four
        // things drift it, all silently:
        //
        //   * `codex login --with-api-key` — auth_mode becomes apikey and the
        //     token carries no `chatgpt_plan_type` at all, so we send "unknown"
        //     while the app sends the account's real plan;
        //   * a plan change between token refreshes leaves the claim stale;
        //   * switching the active workspace inside the app is not a re-login,
        //     so the minted claim need not follow it. UNVERIFIED: the account on
        //     hand belonged to no workspace, so no switcher appeared;
        //   * `CODEX_HOME` moves the file, and this path is hardcoded. Real
        //     setups do it — openai/codex#35817 is an XDG-style
        //     `CODEX_HOME=$HOME/.local/share/codex` on macOS whose `~/.codex`
        //     holds nothing but a stray Desktop sqlite dir. Those machines get
        //     the pre-fix behaviour. Reading the variable is NOT the fix: the
        //     GUI app is launched by launchd and does not inherit the user's
        //     shell environment, so `duo verify` (which does) would go green
        //     over a machine where the app still falls back.
        //
        // All four fail toward "unknown" or a stale consumer value, never toward
        // claiming enterprise on a consumer account, so the blast radius is the
        // cautious track — where omitting the parameter put everyone anyway.
        //
        // The first of the four is no longer silent, at least in a sweep: this
        // rides in `track` rather than `identities`, and `duo verify` reports a
        // machine that fell back WHILE the vendor's two tracks are actually
        // apart. See `RolloutTrack` for why that combination is the only one
        // worth a finding.
        VendorProbeRecipe(
            bundleID: "com.openai.codex",
            url: URL(string: "https://chatgpt.com/backend-api/wham/app/appcast?installation_id=__IDENTITY__&arch=arm64&beta=false&app_version=0.0.0&plan_type=__PLANTYPE__")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9][^<]*)</sparkle:shortVersionString>"#,
            // Required of any identity recipe: without it `.responseBody` falls back
            // to `recipe.url` as the download, which here is an unfetchable
            // placeholder (`ProbeIdentityRedactionTests`). The vendor's own page,
            // titled "Download ChatGPT" — behind a Cloudflare interstitial, so a
            // script gets 403 and only a browser confirms it.
            //
            // The tempting alternative is the direct artifact the site's button
            // serves, `codex-app-prod/Codex.dmg`. Do not use it, and not only
            // because `PageURLTests` requires a page: that dmg tracks the
            // PUBLISHING manifest. Its Last-Modified was 06:12:52Z on 2026-08-22,
            // ninety seconds after 26.818.41705 published — the very build the
            // rollout was still withholding. Pointing anything at it walks straight
            // back into the fight this recipe exists to end.
            downloadURL: URL(string: "https://chatgpt.com/download/"),
            changelogURL: URL(string: "https://developers.openai.com/codex/changelog?type=codex-app")!,
            // Redirect followed (the default), so the body parsed here is the
            // pinned appcast. Its enclosure points at the full zip; the `.delta`
            // urls are ignored, unchanged from when this read the static feed.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"url="([^"]+\.zip)""#),
                kind: .zip),
            identities: [
                ProbeIdentity(
                    applicationSupportPath: "com.openai.codex/production-appcast-bootstrap.json",
                    encoding: .jsonKey("installationId"),
                    validationPattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#),
            ],
            // The plan is NOT an identity — it names which builds come back, not
            // which bucket this machine is in — so it rides here, where the
            // sweep can also check whether it is still deciding anything.
            //
            // `business` is the contrast because it is the value the two-track
            // split is actually about; when the endpoint answers it the same way
            // it answers ours, the rollout has merged and today's value cannot be
            // wrong. `validationPattern` is deliberately permissive: we are a
            // passthrough, not an authority on OpenAI's tier names. A slug we
            // have never seen is forwarded as-is and the vendor decides; only
            // something that isn't a slug at all falls back. `maxBytes` is raised
            // because this file holds JWTs — see `.jwtClaim` for what is and is
            // not read out of it, and `RegistrySecurity` for the allow-list that
            // keeps it that way.
            track: RolloutTrack(
                selector: ProbeIdentity(
                    location: .home(".codex/auth.json"),
                    encoding: .jwtClaim(
                        tokenPath: ["tokens", "access_token"],
                        claimPath: ["https://api.openai.com/auth", "chatgpt_plan_type"]),
                    validationPattern: #"[a-z0-9_]{1,32}"#,
                    placeholder: "__PLANTYPE__",
                    fallback: "unknown",
                    maxBytes: 32768),
                contrastValue: "business",
                contrastTrackName: "the enterprise track")),

        // ChatWise — Squirrel releases endpoint; array of versions, take highest.
        VendorProbeRecipe(
            bundleID: "app.chatwise",
            url: URL(string: "https://releases.chatwise.app/releases?version=0.0.0&platform=osx")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://conductor.build/changelog"),
            // Tauri updater `url` is the `Conductor.app.tar.gz` (CDN asset id, no
            // file extension — VendorInstaller renames by kind before unpacking).
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"([^"]+)""#),
                kind: .tarGz)),

        // Tailscale — official package index. `MacZipsVersion` is the macsys
        // build (top-level `Version` is the Linux/Windows train — wrong here).
        // Three public tracks share `io.tailscale.ipn.macsys`; the channel gate
        // routes each install to its own endpoint per the app's opt-in toggle
        // (see `TailscaleChannel`). `pkgs.tailscale.com/rc` 404s, but that's just
        // the wrong guessed path — the real release-candidate track lives at
        // `pkgs.tailscale.com/release-candidate/` (verified 2026-08-21: HTTP 200,
        // same JSON shape as stable/unstable below).
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
        // Tailscale release candidate — same JSON shape on the
        // `/release-candidate/` track. Only reached when the install opted in via
        // `RCUpdatesEnabled`; the same Tailscale-signed pkg path.
        //
        // On version numbers: per Tailscale's own docs the RC track carries the
        // *next patch of the current stable line*, so it normally reads equal to
        // stable (right after a promotion — both were 1.102.3 on 2026-08-21) or
        // ahead of it (while a patch is being tested), not behind. Either way
        // nothing here depends on that: `VersionComparator.isNewer` requires
        // strictly-greater, so an equal or lower RC version offers no update
        // rather than proposing a downgrade.
        VendorProbeRecipe(
            bundleID: "io.tailscale.ipn.macsys",
            url: URL(string: "https://pkgs.tailscale.com/release-candidate/?mode=json")!,
            mode: .responseBody,
            versionPattern: #""MacZipsVersion"\s*:\s*"([0-9.]+)""#,
            changelogURL: URL(string: "https://tailscale.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #""universal-package"\s*:\s*"(Tailscale-[^"]+\.pkg)""#,
                    base: URL(string: "https://pkgs.tailscale.com/release-candidate/")!),
                kind: .pkg),
            channel: .rc),
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
            versionPattern: #""notes"\s*:\s*\[\s*\{[^}]*"version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
            versionPattern: #"releases\.warp\.dev/stable/v([0-9.]+)\.stable_([0-9]+)"#,
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
        //
        // 2026-08-16: the patterns no longer name the CDN HOST. Discord moved
        // stable's downloads from `stable.dl2.discordapp.net` to plain
        // `dl.discordapp.net` and the host-anchored pattern stopped matching —
        // `duo verify` reported `versionPatternNoMatch` on an 8801-byte body that
        // was otherwise perfectly well-formed. The channel lives in the URL PATH
        // (`/distro/app/stable/…`), which is the part that actually has to be
        // pinned: it is what keeps a channel's recipe off its siblings' numbers.
        // ptb/canary were still on `*.dl2` when this was written and were moved to
        // the same host-agnostic shape so the identical break can't repeat there.
        VendorProbeRecipe(
            bundleID: "com.hnc.Discord",
            url: URL(string: "https://updates.discord.com/distributions/app/manifests/latest?channel=stable&platform=osx&arch=x64")!,
            mode: .responseBody,
            versionPattern: #"discordapp\.net/distro/app/stable/osx/universal/([0-9]+(?:\.[0-9]+){1,3})/"#,
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
            versionPattern: #"discordapp\.net/distro/app/ptb/osx/universal/([0-9]+(?:\.[0-9]+){1,3})/"#,
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
            versionPattern: #"discordapp\.net/distro/app/canary/osx/universal/([0-9]+(?:\.[0-9]+){1,3})/"#,
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
            // The desktop what's-new page, NOT www.notion.com/releases: that one is
            // the product announcement feed whose "versions" are post titles with no
            // build number, which is the mismatch the changelog recipe moved away
            // from. This is the WebView fallback, so pointing it at the old page put
            // the user right back on the feed that doesn't match their install.
            changelogURL: URL(
                string: "https://notion.notion.site/What-s-New-Mac-Windows-5936dabc8dd6497895786c91b9d6f12a")!,
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
            versionPattern: #""latestVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
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
        // exists), so it can't be used for a stable install.
        //
        // The version comes from the stable channel's RSS FEED
        // (`…/mac/stable/index.xml`), not from scraping the HTML page beside it:
        // a feed is a published interface with fixed element names, while the
        // page's version sat in a `c-updates__title` class that a redesign renames
        // without anyone calling it breaking. The same feed backs
        // `ChangelogRecipe(com.1password.1password)`.
        //
        // `selectHighest` rather than first-match, because the feed is ASCENDING
        // (8.7.0 from 2022 is item 1 of 89) — first-match here would report a
        // four-year-old release as current, which reads as "up to date" forever.
        // Comparing numerically means the order stops mattering at all.
        //
        // ONE-CLICK — but NOT from the URL the download page hands out.
        // `downloads.1password.com/mac/1Password.zip` looks perfect (stable URL,
        // Developer ID 2BUA8C4S2C, notarized) and is a trap: it contains
        // `1Password Installer.app` (`com.1password.1password-installer`, 21 MB), a
        // stub that fetches the real app. Swapping THAT over
        // `/Applications/1Password.app` would replace the password manager with its
        // own installer — and every signature gate would pass, because the stub is
        // genuinely signed by AgileBits. Only the bundle-id gate stands between
        // that URL and a broken install.
        //
        // The payload the stub itself downloads is per-architecture and public
        // (read out of the installer binary's own strings, 2026-08-16):
        //   downloads.1password.com/mac/1Password-latest-{aarch64,x86_64}.zip
        // plus `.BETA-` / `.NIGHTLY-` variants for the other channels. Verified by
        // downloading the aarch64 one (214,254,924 B): it unzips to `1Password.app`
        // itself — com.1password.1password, 8.12.33, Team 2BUA8C4S2C, notarized
        // Developer ID, spctl accepted, arm64.
        //
        // A "latest" URL rather than a version template: 1Password publishes no
        // versioned artifact path, so this can in principle serve a build newer
        // than the page reported. That is the same shape as the other `latest`
        // installs here (Termius, iStat Menus) and the gates still apply; what it
        // must never become is the stub URL above.
        VendorProbeRecipe(
            bundleID: "com.1password.1password",
            url: URL(string: "https://releases.1password.com/mac/stable/index.xml")!,
            mode: .responseBody,
            versionPattern: #"<title>1Password for Mac\s+([0-9]+\.[0-9]+\.[0-9]+)</title>"#,
            downloadURL: URL(string: "https://1password.com/downloads/mac/"),
            changelogURL: URL(string: "https://releases.1password.com/mac/stable/"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://downloads.1password.com/mac/1Password-latest-aarch64.zip")!),
                kind: .zip)),

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
            versionPattern: #"class="latest"><i>Version:</i>\s*(Build\s+[0-9]+)"#,
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
            // NOT widened to a variable segment count like its neighbours. The feed's
            // value is `1.115.0.426-4e960a1d` and this pattern has no closing
            // delimiter, so the capture is bounded only by how many segments it
            // asks for: three yields the marketing version, four would silently
            // start reporting `1.115.0.426` — a build number the app does not
            // report, which is a phantom update. Verified against the live feed
            // 2026-08-19.
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

        // Alcove — the PUBLIC, no-credential fallback. The authoritative source is
        // `AlcoveUpdateSource` (the licensed api.tryalcove.com channel the app's own
        // "Reworked update manager" uses), wired ahead of this probe so it answers
        // first whenever the user's license credentials are seeded; this recipe is
        // what everyone else gets.
        //
        // The old endpoint (update.tryalcove.com) is GONE — verified 2026-07-29 it no
        // longer resolves at all (NXDOMAIN), so the previous recipe silently produced
        // no version and left uncredentialed users with ZERO Alcove detection (the
        // henrikruscon/alcove-releases GitHub mirror had already been retired for
        // lagging; see GitHubReleasesSource). Its replacement is the download host's
        // own metadata endpoint, `download.tryalcove.com/latest` — a small
        // unauthenticated JSON doc:
        //   {"version":"1.7.9","build":203,"published_at":"…","assets":[…],
        //    "minimum_system_version":"15 Sequoia"}
        // `version` is the marketing string (== CFBundleShortVersionString — no build
        // trap; `build` is carried separately and we ignore it). Verified 2026-07-29
        // it reported exactly 1.7.9 (203), matching the installed licensed build
        // build-for-build — so unlike every mirror before it, this one is IN SYNC with
        // the licensed channel rather than trailing it. Single-channel: `?channel=beta`
        // 404s ("No releases available") and an `X-Channel` header changes nothing.
        //
        // The pattern requires `{` or `,` before the key so it can never drift onto
        // the sibling `minimum_system_version` (whose value, "15 Sequoia", isn't
        // version-shaped anyway) if the vendor reorders fields.
        //
        // DETECTION-ONLY, deliberately — do NOT re-attach an install spec. The public
        // binaries at download.tryalcove.com/{Alcove.dmg,Alcove.zip} are the *trial*
        // build and lag this metadata badly: on 2026-07-29 the dmg was 1.7.7 (199)
        // (`x-alcove-version: 1.7.7`, confirmed by mounting it and reading the
        // bundle's Info.plist) while /latest already said 1.7.9. Installing it while
        // claiming 1.7.9 would leave a permanent phantom "update available" that no
        // install can ever clear. There is no versioned public download path either
        // (`/1.7.9/Alcove.dmg`, `?version=…` etc. all 404 or serve the same stale
        // trial build), so users without a license key are sent to the download page
        // by hand — and Alcove's own updater keeps them current regardless.
        //
        // Notes come from `changelogURL` in a WebView rather than a ChangelogRecipe.
        // www.tryalcove.com/changelog is a real page — it server-renders every version
        // and date, newest 1.7.9 — but it is not scrapable: each entry's body is an
        // empty placeholder, with the actual features/fixes arrays inlined in a
        // content-hashed minified route chunk (`/assets/ChangelogPage-<hash>.js`)
        // whose filename changes on every deploy. Embedding the page renders it
        // correctly with none of that fragility.
        VendorProbeRecipe(
            bundleID: "com.henrikruscon.Alcove",
            url: URL(string: "https://download.tryalcove.com/latest")!,
            mode: .responseBody,
            versionPattern: #"(?:^|[{,])\s*"version"\s*:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)*)""#,
            downloadURL: URL(string: "https://www.tryalcove.com/download")!,
            changelogURL: URL(string: "https://www.tryalcove.com/changelog"),
            // Single-release document, so the first (only) `published_at` is
            // unambiguously this version's — ISO8601 with fractional seconds
            // ("2026-06-30T20:57:57.000Z"), which ReleaseDate parses. Gives the
            // Release Log an exact time instead of an estimated "≈" window, even
            // without a license key.
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#),

        // (Surge needs no recipe here: it declares a Sparkle SUFeedURL, so the
        // higher-priority SparkleAppcastSource handles it, and `SurgeChannel`
        // retargets that feed to the release/beta appcast per the user's choice.)

        // MARK: - 2026-08-17 AI desktop apps

        // Wispr Flow — official RELEASES.json, the same endpoint Homebrew uses.
        // `currentRelease` is authoritative and matches both version fields in the
        // mounted app (1.6.531). The feed is architecture-specific and the vendor
        // publishes separate Intel/arm64 installers; VendorInstallSpec has no
        // host-architecture substitution, so this stays detection-only rather
        // than risking a cross-architecture swap. com.electron.wispr-flow, Team
        // C9VQZ78H85, notarized; no SUFeedURL.
        VendorProbeRecipe(
            bundleID: "com.electron.wispr-flow",
            url: URL(string: "https://dl.wisprflow.com/wispr-flow/darwin/arm64/RELEASES.json")!,
            mode: .responseBody,
            versionPattern: #"\"currentRelease\"\s*:\s*\"([0-9]+(?:\.[0-9]+)+)\""#,
            downloadURL: URL(string: "https://wisprflow.ai/downloads")),

        // Granola — its public latest-mac.yml redirects to a versioned CloudFront
        // manifest. `version` equals both Info.plist version fields. The dmg path is
        // deterministic from that exact resolved version and is universal, so it
        // is safe for one-click. Mounted dmg: com.granola.app, Team QZ7DHHLN25,
        // notarized. The manifest's sha512 is for the zip, not the dmg, so the
        // signature/Team gate is the integrity check for this installer.
        VendorProbeRecipe(
            bundleID: "com.granola.app",
            url: URL(string: "https://api.granola.ai/v1/check-for-update/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://www.granola.ai/"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://dr2v7l5emb758.cloudfront.net/{version}/Granola-{version}-mac-universal.dmg"),
                kind: .dmg)),

        // Comet — the cask's JSON update API is rollout-stale (145.x while the
        // public download already contains 151.x), so probing it would report a
        // downgrade. The official stable download GET redirects to a signed R2 URL
        // whose versioned directory exactly matches the mounted bundle's marketing
        // version. HEAD is a vendor trap (redirects to example.com), hence GET with
        // redirects disabled. Detection-only: the signed URL expires and the fixed
        // gateway is architecture-specific. ai.perplexity.comet, Team 7S8W4W365S,
        // notarized; Keystone updater, no Sparkle feed.
        VendorProbeRecipe(
            bundleID: "ai.perplexity.comet",
            url: URL(string: "https://www.perplexity.ai/rest/browser/download?channel=stable&platform=mac_arm64")!,
            mode: .redirectFilename,
            versionPattern: #"/([0-9]+(?:\.[0-9]+)+)/comet_latest\.dmg"#,
            downloadURL: URL(string: "https://www.perplexity.ai/comet"),
            followRedirects: false),

        // Devin Desktop (formerly Windsurf) — official stable update JSON. The
        // `windsurfVersion` field is the app's own 3.7.25 marketing/build version;
        // `productVersion` is the upstream VS Code base and must never be parsed.
        // The response carries an arm64-only installer URL, so detection remains
        // architecture-neutral but one-click is omitted. com.exafunction.windsurf,
        // Team 83Z2LHX6XW, notarized.
        VendorProbeRecipe(
            bundleID: "com.exafunction.windsurf",
            url: URL(string: "https://windsurf-stable.codeium.com/api/update/darwin-arm64-dmg/stable/latest")!,
            mode: .responseBody,
            versionPattern: #"\"windsurfVersion\"\s*:\s*\"([0-9]+(?:\.[0-9]+)+)\""#,
            downloadURL: URL(string: "https://devin.ai/desktop"),
            changelogURL: URL(string: "https://windsurf.com/editor/releases/")),

        // AionUi — official electron-builder arm64 manifest. `version` matches the
        // mounted app exactly. Intel has a separate manifest and artifact, so keep
        // this detection-only until VendorInstallSpec can select by host arch.
        // com.aionui.app, Team 52JQX2HUSC, notarized.
        VendorProbeRecipe(
            bundleID: "com.aionui.app",
            url: URL(string: "https://static.aionui.com/releases/latest-arm64-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*v?([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://www.aionui.com/"),
            changelogURL: URL(string: "https://github.com/iOfficeAI/AionUi/releases"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#),

        // Msty Studio — official electron-builder manifest lists both x64 and
        // arm64 assets and reports the same version as Info.plist. Detection-only:
        // selecting the correct one-click asset needs host-architecture-aware
        // VendorInstallSpec support. MstyStudio, Team S6CF5A8MX9, notarized.
        VendorProbeRecipe(
            bundleID: "MstyStudio",
            url: URL(string: "https://next-assets.msty.studio/app/latest/mac/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*v?([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://msty.ai/"),
            changelogURL: URL(string: "https://msty.ai/resources/changelog/studio/"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#),

        // TRAE is deliberately absent here. Its official manifest exposes only
        // the packaging line `2.3.61406`, while the exact dmg at that manifest URL
        // reports CFBundleShortVersionString/CFBundleVersion `3.5.81`. The embedded
        // product.json ties the two together (`tronBuildVersion` / `appVersion`),
        // but the network response never publishes `appVersion`; neither string can
        // safely be compared to the installed Info.plist. See the persisted audit.

        // MARK: - 2026-08-16 Google desktop apps

        // Gemini — Google's Omaha update service, which answers only a POST. The
        // published download URL carries no version (`.../release2/Gemini.dmg`,
        // unchanged across releases so far) and the download page answers a plain
        // fetch with Google's bot challenge (302 → /sorry, observed 2026-08-16),
        // so nothing reachable states a version. This service does; it was found
        // by reading the app's own update request. Asking as version `0.0.0.0`
        // makes it answer with the manifest for the newest build, not "noupdate".
        //
        // Verified 2026-08-16 on the installed copy: manifest `1.94.11.734`
        // against `CFBundleShortVersionString` 1.94.11.734 — the same scheme, so
        // no build-vs-marketing trap here. The reply is prefixed with Google's
        // `)]}'` anti-hijacking line, which the regex simply skips.
        //
        // The manifest publishes a sha256, but `checksumPattern` verifies a
        // base64 SHA-512, so it goes unused; the signature gate still applies.
        // No `changelogURL`: `gemini.google/release-notes` is the Gemini *Apps*
        // product feed — model and feature announcements keyed by DATE
        // (2023.04.10, …), with no desktop build number anywhere. The installed
        // app reports 1.96.4.775, so nothing on that page can ever line up with
        // the version on this row. Exactly the mismatch the Notion changelog was
        // moved off of; wiring it here would reintroduce it. (Checked 2026-08-22.)
        VendorProbeRecipe(
            bundleID: "com.google.GeminiMacOS",
            url: URL(string: "https://update.googleapis.com/service/update2/json")!,
            mode: .responseBody,
            versionPattern: #""manifest":\{"version":"([0-9][0-9.]*)""#,
            downloadURL: URL(string: "https://gemini.google.com/download"),
            install: VendorInstallSpec(
                // The manifest splits the download in two: a list of CDN bases
                // and the package name. Join Google's own host with the name.
                urlSource: .bodyTemplate("{0}{1}", fields: [
                    #""codebase":"(https://dl\.google\.com/[^"]+)""#,
                    #""name":"(Gemini-[0-9.]+\.dmg)""#,
                ]),
                kind: .dmg),
            requestBody: .init(json: """
                {"request":{"protocol":"3.0","os":{"platform":"mac","arch":"arm64"},\
                "app":[{"appid":"com.google.GeminiMacOS","tag":"m1-prod",\
                "version":"0.0.0.0","updatecheck":{}}]}}
                """)),

        // Antigravity — its own electron-builder feed, on the Cloud Run service the
        // app's updater polls (found by capturing that request, 2026-08-16; there
        // is no Omaha entry — six plausible appids answered
        // `error-unknownApplication` while Gemini's returned `ok`).
        //
        // Preferred over the download page, which was the first thing that worked
        // and is a far worse source: it advertises two products at once (the IDE,
        // under `.../antigravity/stable/`, at its own version) and prints this one
        // as `2.8.1-6512087774658560` while the shipped bundle reports a plain
        // `2.8.1`. The feed states the bundle's own string directly.
        //
        // Verified 2026-08-16 on the mounted artifact: com.google.antigravity,
        // `CFBundleShortVersionString` 2.8.1, Team EQHXZ8M8AV, notarized, and no
        // SUFeedURL (so nothing else covers it). The app sends an
        // `x-user-staging-id` header for its staged rollout; we deliberately do
        // not — the feed answers the same manifest without it, and that header is
        // a per-machine identifier. The consequence is that a release still
        // rolling out (`stagingPercentage` below 100) would be offered here
        // before the app itself takes it.
        //
        // The feed's `sha512` is verifiable: the served zip's Content-Length is
        // exactly the `size` it states (165926585 on 2026-08-16), so the hash was
        // taken on the bytes we will actually download — unlike Signal's feed,
        // where a size delta gave away a hash computed before stapling.
        VendorProbeRecipe(
            bundleID: "com.google.antigravity",
            url: URL(string: "https://antigravity-hub-auto-updater-974169037036"
                + ".us-central1.run.app/manifest/latest-arm64-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*([0-9][0-9.]*)\s*$"#,
            changelogURL: URL(string: "https://antigravity.google/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"url:\s*(https://storage\.googleapis\.com/\S+\.zip)"#),
                kind: .zip,
                checksumPattern: #"sha512:\s*([A-Za-z0-9+/=]+)"#)),

        // Antigravity IDE — a SECOND, separate app from the one above. Different
        // bundle id (`com.google.antigravity-ide`), different version line (2.5.5
        // against the other's 2.9.1), different binary (Electron — it is a VS Code
        // fork, the Windsurf/Codeium lineage Google acquired). It was installed and
        // scanned but matched no recipe, so its row had no source and no notes at
        // all. The sibling recipe's own comment had already noticed this product
        // existed ("the IDE, under `.../antigravity/stable/`") without covering it.
        //
        // Nothing else covers it either: no `SUFeedURL`, no electron-updater
        // `app-update.yml`, and its VS Code `product.json` sets `updateUrl` to the
        // literal `https://example.com`, so the built-in update channel is inert.
        // The real endpoint is in `out/main.js` — a sibling Cloud Run service under
        // the same GCP project number as the hub updater above:
        //   /api/update/{platform}/{quality}/{commit}/{sha256(hostname)}
        //
        // Two deliberate choices in the URL:
        //
        // The last path component is a per-machine identifier (the app sends a
        // SHA-256 of the hostname). We send `no_hostname` — the app's OWN fallback
        // literal from the same code, so it is a value the service already handles
        // rather than something invented, and no machine fingerprint leaves here.
        // Same reasoning as the `x-user-staging-id` header the sibling omits.
        //
        // The commit slot is all zeroes. This is VS Code's update API: it answers
        // 204 No Content when the commit you name is already current, and the
        // update JSON otherwise. Naming the installed commit would therefore return
        // nothing to compare against — and we cannot name it anyway, since it lives
        // in `product.json` inside the bundle, which the scanner does not read. A
        // well-formed hash that can never be a real commit always gets the latest.
        // Verified 2026-08-22: the real commit → 204, all-zeroes → 200 with the
        // manifest.
        //
        // The version comes from the download URL, NOT from any version field in
        // that response — every one of those is the VS Code base (`productVersion`
        // and `name` are both 1.107.0, `version` is a commit hash), while the
        // shipped bundle reports 2.5.5. Comparing 1.107.0 against 2.5.5 would be a
        // permanent phantom update. The URL path carries the real one:
        //   .../antigravity/stable/2.5.5-4923483625488384/darwin-arm/...
        // and the pattern stops at the `-`, so the build id does not ride along —
        // the exact trap the sibling recipe documents for the hub feed.
        //
        // Detection only for now: the artifact is a zip on Google's edgedl CDN with
        // a `sha256hash` beside it, so an install spec is plausible, but it has not
        // been downloaded and signature-checked yet, and the URL is arm64-specific.
        VendorProbeRecipe(
            bundleID: "com.google.antigravity-ide",
            url: URL(string: "https://antigravity-ide-auto-updater-974169037036"
                + ".us-central1.run.app/api/update/darwin-arm64/stable/"
                + "0000000000000000000000000000000000000000/no_hostname")!,
            mode: .responseBody,
            versionPattern: #"/antigravity/stable/([0-9][0-9.]*)-"#,
            // Detection-only rows have no install action, so the page link is the
            // only thing the row can offer — a recipe without one is a dead end
            // (`PageURLTests.detectionOnlyRecipesCarryAPage` enforces it, and
            // caught this omission).
            //
            // No `changelogURL`: the hub's points at `antigravity.google/changelog`,
            // but that page is JS-rendered — 88 KB with zero version strings in the
            // served HTML — so there is no way to confirm from here that it even
            // describes the IDE rather than only the hub. Linking it would be a
            // guess dressed up as coverage.
            downloadURL: URL(string: "https://antigravity.google/download")),

        // AnyDesk — the plain-text changelog its own Homebrew cask reads for
        // livecheck, and the one thing on that host a script can fetch: the
        // download page and `anydesk.com/en/changelog/mac-os` both answer 403 with
        // a Cloudflare challenge even under a full Safari UA, which is why an
        // earlier sweep wrote this app off entirely. `changelog.txt` answers 200.
        //
        // Every platform's releases share the file, newest first, as
        // `22.07.2026 - 9.7.3 (macOS)`. The `(macOS)` anchor is load-bearing and
        // `selectHighest` must stay off: Windows is on a HIGHER number (9.7.14 the
        // day this was written), so an unanchored or highest-wins pattern reports
        // a version this app will never install.
        //
        // Verified 2026-08-16 on the downloaded dmg: AnyDesk.app 9.7.3,
        // com.philandro.anydesk, Developer ID `AnyDesk Software GmbH (KHRWM533LU)`
        // — the same Team as the installed copy — notarized and accepted by
        // `spctl`. The dmg URL carries no version, but it does not need to: it
        // always serves the release this file names first (its `Last-Modified`,
        // 2026-07-22, matches that entry's date).
        VendorProbeRecipe(
            bundleID: "com.philandro.anydesk",
            url: URL(string: "https://download.anydesk.com/changelog.txt")!,
            mode: .responseBody,
            versionPattern: #"([0-9]+(?:\.[0-9]+)+)\s+\(macOS\)"#,
            downloadURL: URL(string: "https://anydesk.com/en/downloads/mac-os"),
            changelogURL: URL(string: "https://anydesk.com/en/changelog/mac-os"),
            install: VendorInstallSpec(
                urlSource: .fixed(URL(string: "https://download.anydesk.com/anydesk.dmg")!),
                kind: .dmg)),

        // Kiro — the Squirrel.Mac metadata its own updater reads (found by
        // capturing that request, 2026-08-16). One 323-byte JSON, already scoped
        // to this architecture by its filename, stating `currentRelease` and the
        // exact artifact for it.
        //
        // Preferred over the download page, which was the first thing that worked:
        // that page carries both architectures' links under the same version and
        // its version text sits in hash-named utility classes, so reading it meant
        // naming the architecture in a regex and hoping the markup held. Guessing
        // at a manifest had failed earlier — every `latest-mac.yml` / `latest.yml`
        // / `/latest` shape on this host answers 403 — which is why the page was
        // used at all.
        //
        // The metadata offers a zip where the page offers a dmg; the zip is the
        // same release and unpacks straight into the swap, so it is the better of
        // the two. `pub_date` is a bare `2026-08-13`, which `ReleaseDate` does not
        // parse (it wants a time), so no `publishedAtPattern` here.
        //
        // Verified 2026-08-16 on the downloaded artifact: Kiro.app 1.0.309,
        // dev.kiro.desktop, Developer ID `AMZN Mobile LLC (94KV3E626L)`, notarized
        // and accepted by `spctl`. Not installed on the machine this was written
        // on, so the comparison against an installed copy's Team is unverified —
        // the gate performs it at install time regardless.
        VendorProbeRecipe(
            bundleID: "dev.kiro.desktop",
            url: URL(string: "https://prod.download.desktop.kiro.dev"
                + "/stable/metadata-darwin-arm64-stable.json")!,
            mode: .responseBody,
            versionPattern: #""currentRelease":\s*"([0-9][0-9.]*)""#,
            downloadURL: URL(string: "https://kiro.dev/downloads/"),
            changelogURL: URL(string: "https://kiro.dev/changelog/ide/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url":\s*"(https://prod\.download\.desktop\.kiro\.dev/[^"]+darwin-arm64\.zip)""#),
                kind: .zip)),
        // MARK: - 2026-08-16 vendor batch
        //
        // Mainstream Homebrew casks with no Sparkle feed of their own. Every line
        // states what was read off the artifact the install spec actually
        // resolves to, on a mounted/expanded copy of the real download — bundle
        // id, `CFBundleShortVersionString` and `codesign`/`spctl` — because the
        // trap in this batch is never "no version anywhere", it is a version that
        // is not the same KIND of string the installed bundle reports.

        // Wave Terminal — electron-builder feed. Verified 2026-08-16: the zip
        // holds `Wave.app`, dev.commandline.waveterm, 0.14.5, Team M4LA8V687Y,
        // notarized — the same string the feed's `version:` carries.
        VendorProbeRecipe(
            bundleID: "dev.commandline.waveterm",
            url: URL(string: "https://dl.waveterm.dev/releases-w2/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://waveterm.dev/download"),
            changelogURL: URL(string: "https://github.com/wavetermdev/waveterm/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Wave-darwin-arm64-[^\s]+\.zip)"#,
                    base: URL(string: "https://dl.waveterm.dev/releases-w2/")!),
                kind: .zip)),

        // Lens — electron-builder feed. The version carries a literal `-latest`
        // suffix (`2026.6.260931-latest`) and so does the shipped bundle's own
        // `CFBundleShortVersionString`, verified on the mounted dmg
        // (com.electron.kontena-lens, Team JJ22T2W355, notarized). Both sides
        // therefore compare like-for-like; do NOT "clean up" the suffix here,
        // that would make every check report a phantom update.
        VendorProbeRecipe(
            bundleID: "com.electron.kontena-lens",
            url: URL(string: "https://api.k8slens.dev/binaries/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://k8slens.dev/"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Lens-[^\s]+-arm64\.dmg)"#,
                    base: URL(string: "https://api.k8slens.dev/binaries/")!),
                kind: .dmg)),

        // Termius — electron-builder feed, one per architecture. The artifacts
        // are unversioned (`Termius.dmg`), so the install URL is fixed and the
        // version comes from the feed. Verified 2026-08-16 on the arm64 dmg:
        // com.termius-dmg.mac, 9.43.1, Team 6KN952WR85, notarized.
        VendorProbeRecipe(
            bundleID: "com.termius-dmg.mac",
            url: URL(string: "https://autoupdate.termius.com/mac-arm64/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://termius.com/download/macos"),
            changelogURL: URL(string: "https://termius.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://autoupdate.termius.com/mac-arm64/Termius.dmg")!),
                kind: .dmg)),

        // Unity Hub — electron-builder feed. Despite the "Setup" in the asset
        // name this zip is NOT a stub installer: it expands to `Unity Hub.app`
        // itself (com.unity3d.unityhub, 3.20.1, Team 9QW8UQUTAA, notarized),
        // which is what makes one-click safe here and not the 1Password trap.
        VendorProbeRecipe(
            bundleID: "com.unity3d.unityhub",
            url: URL(string: "https://public-cdn.cloud.unity3d.com/hub/prod/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://unity.com/unity-hub"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"([0-9][^\s/]*/UnityHubSetup-[^\s]+-arm64\.zip)"#,
                    base: URL(string: "https://public-cdn.cloud.unity3d.com/hub/prod/")!),
                kind: .zip)),

        // iStat Menus — a "latest" link that 302s straight to the versioned zip
        // (`…/versions/iStatMenus7.30.zip`), so the redirect target is both the
        // version signal and the download. Verified 2026-08-16: the zip holds
        // `iStat Menus.app`, com.bjango.istatmenus, 7.30, Team Y93TK974AT,
        // notarized. The pattern skips the `7` in the product name and takes the
        // version that follows it.
        VendorProbeRecipe(
            bundleID: "com.bjango.istatmenus",
            url: URL(string: "https://download.istatmenus.app/istatmenus7/download/")!,
            mode: .redirectFilename,
            versionPattern: #"iStatMenus([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.zip"#,
            downloadURL: URL(string: "https://bjango.com/mac/istatmenus/"),
            changelogURL: URL(string: "https://bjango.com/mac/istatmenus/versionhistory/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.istatmenus.app/istatmenus7/download/")!),
                kind: .zip)),

        // Inkscape — `/release/` 302s to `/release/inkscape-1.4.4/`, a clean
        // version signal.
        //
        // ONE-CLICK via `.versionTemplate`. An earlier note here said the dmg was
        // unreachable, because the download PAGE hands the file out through an
        // HTML `<meta http-equiv="Refresh">` to `/gallery/item/<id>/…` with a
        // per-release id (59498 for 1.4.4_arm64) that no template can predict.
        // That was the wrong place to look: the same file also sits at a plain
        // version-named path on the media host, no gallery id involved —
        // `media.inkscape.org/dl/resources/file/Inkscape-<ver>_arm64.dmg`
        // (2026-08-16: 1.4.4 → 200, 156,920,591 B; 1.4.3 → 200).
        //
        // The naming does NOT reach back forever — 1.4.2 is a 404 under every
        // variant tried — but that costs nothing here: the URL is only ever built
        // for the version the probe just resolved, i.e. the current release. A
        // future rename fails the download loudly (the row stays red) rather than
        // installing something else.
        //
        // Verified 2026-08-16 by mounting the 1.4.4 dmg: `Inkscape.app`,
        // org.inkscape.Inkscape, CFBundleShortVersionString `1.4.4` — same scheme
        // the redirect publishes — Team SW3D6BB6A6 (Rene de Hesselle, who also
        // signs Meld above), notarized Developer ID, spctl accepted. arm64-only
        // artifact, so an Intel Mac is refused by the runnable-arch gate rather
        // than handed a build it can't run.
        VendorProbeRecipe(
            bundleID: "org.inkscape.Inkscape",
            url: URL(string: "https://inkscape.org/release/")!,
            mode: .redirectFilename,
            versionPattern: #"inkscape-([0-9]+\.[0-9]+(?:\.[0-9]+)?)"#,
            downloadURL: URL(string: "https://inkscape.org/release/"),
            changelogURL: URL(string: "https://inkscape.org/news/"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://media.inkscape.org/dl/resources/file/Inkscape-{version}_arm64.dmg"),
                kind: .dmg),
            followRedirects: false),

        // Deliberately NOT covered — Android File Transfer
        // (`com.google.android.mtpviewer`). `…/mtp/current/AndroidFileTransfer.dmg`
        // does 302 to a versioned path, but the number there is `5071136` while the
        // shipped bundle reports `1.0.12` (build `1.0.507.1136`) — the redirect
        // squashes the build's last two segments together. Neither string can be
        // compared with the other, so a recipe would report a permanent update.
        // (Homebrew's cask uses 5071136 as its own bookkeeping version, which is
        // what makes this look workable from the outside.)

        // MARK: - 2026-08-16 group B (Emacs, Tor Browser, Zotero)

        // Emacs for Mac OS X — the maintainer's own Atom feed, newest entry first.
        // `<title>Emacs Version 30.2-2</title>`.
        //
        // VERSION SCHEME TRAP: some entries carry a `-N` repack suffix (`30.2-2`,
        // `30.2-1`) for a re-signed rebuild of the SAME release, but the shipped
        // app does not: mounting the 30.2-2 dmg and reading Info.plist gives
        // `CFBundleShortVersionString = 30.2` (no suffix at all; `CFBundleVersion`
        // is an unrelated `9.0`, not usable either). Capturing the suffix would
        // make the probe report `30.2-2 > 30.2` forever — a phantom update that can
        // never clear. The pattern anchors to the `<title>` tag (skipping the
        // duplicate plain-text title inside `<content>`) and captures only the two
        // numeric segments, dropping any `-N` tail.
        //
        // One-click verified 2026-08-16 by mounting the 30.2-2 dmg: Emacs.app is
        // org.gnu.Emacs, CFBundleShortVersionString 30.2, Team 5BRAQAFB8B
        // (Galvanix), notarized Developer ID. The install pattern reuses the same
        // `<title>`-scoped entry's `<link type="binary/octet-stream">` href, so it
        // always fetches the dmg for the version just matched (suffix included,
        // since that's the real filename) rather than a template that would guess
        // wrong when a repack bumps only the suffix.
        VendorProbeRecipe(
            bundleID: "org.gnu.Emacs",
            url: URL(string: "https://emacsformacosx.com/atom/release")!,
            mode: .responseBody,
            versionPattern: #"<title>Emacs Version ([0-9]+\.[0-9]+)(?:-[0-9]+)?</title>"#,
            downloadURL: URL(string: "https://emacsformacosx.com/"),
            changelogURL: URL(string: "https://www.gnu.org/software/emacs/news/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<link type="binary/octet-stream" href="(https://emacsformacosx\.com/emacs-builds/Emacs-[^"]+-universal\.dmg)""#),
                kind: .dmg)),

        // Tor Browser — the official Tor Project update-check JSON
        // (`aus1.torproject.org`, the same host the browser's own updater
        // consults). Single small object: `{"binary": "...", "version": "15.0.19",
        // ...}`, no other version-shaped numbers nearby, so a bare `"version"` key
        // match is safe here.
        //
        // Verified against the real install, not assumed: mounting the 15.0.19 dmg
        // gives CFBundleShortVersionString exactly `15.0.19` — same three-segment
        // scheme as the feed, no build/marketing mismatch to work around (unlike
        // Emacs above). org.torproject.torbrowser, Team MADPSAYN6T (The Tor
        // Project, Inc), notarized Developer ID, ticket stapled. `"binary"` is the
        // exact dmg URL for this version, so the install spec reads it straight
        // from the same response rather than templating one.
        VendorProbeRecipe(
            bundleID: "org.torproject.torbrowser",
            url: URL(string: "https://aus1.torproject.org/torbrowser/update_3/release/download-macos.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.torproject.org/download/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""binary"\s*:\s*"(https://[^"]+\.dmg)""#),
                kind: .dmg)),

        // Zotero — no version API at all: `update.xml` and every `manifests/*.json`
        // path 404, and `dl.php` merely echoes back whatever version is passed to
        // it (not a source of truth). The one stable anchor is an inline JS literal
        // on the download page, `www.zotero.org/download/`:
        // `"standaloneVersions":{"mac":"10.0","win32":"10.0",...}`. The pattern
        // is scoped to the `standaloneVersions` object and its `"mac"` key
        // specifically, so it can't drift onto a Windows/Linux number in the same
        // literal, and to the closing quote so it can't capture a truncated value.
        //
        // The version component count is NOT fixed at three: Zotero 10.0 shipped
        // as a two-segment string (2026-08-17), which is what broke the original
        // `[0-9]+\.[0-9]+\.[0-9]+` pattern — the literal is still on the page,
        // unchanged in shape. Verified 2026-08-19 by mounting
        // `Zotero-10.0.dmg`: CFBundleShortVersionString and CFBundleVersion are
        // both exactly `10.0`, so the page string still matches what the installed
        // bundle self-reports and no phantom update is possible; still
        // org.zotero.zotero, Team 8LAYR367YV, notarized Developer ID
        // (`spctl -t install`: accepted). The vendor's own
        // `download/client/dl?channel=release&platform=mac` redirect resolves to
        // exactly the templated URL below, so the template shape is unchanged.
        //
        // One-click originally verified 2026-08-16 by mounting
        // `download.zotero.org/client/release/9.0.6/Zotero-9.0.6.dmg`:
        // CFBundleShortVersionString is exactly `9.0.6` (matches the page verbatim,
        // no scheme mismatch), org.zotero.zotero, Team 8LAYR367YV (Corporation for
        // Digital Scholarship), notarized Developer ID, universal binary. Zotero
        // publishes every release at that exact path/filename shape, so the
        // install URL is templated from the matched version rather than scraped
        // (there is no link to scrape — the download button is client-rendered).
        VendorProbeRecipe(
            bundleID: "org.zotero.zotero",
            url: URL(string: "https://www.zotero.org/download/")!,
            mode: .responseBody,
            versionPattern: #""standaloneVersions"\s*:\s*\{\s*"mac"\s*:\s*"([0-9]+(?:\.[0-9]+){1,2})""#,
            downloadURL: URL(string: "https://www.zotero.org/download/"),
            changelogURL: URL(string: "https://www.zotero.org/support/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.zotero.org/client/release/{0}/Zotero-{0}.dmg",
                    fields: [#""standaloneVersions"\s*:\s*\{\s*"mac"\s*:\s*"([0-9]+(?:\.[0-9]+){1,2})""#]),
                kind: .dmg)),

        // MARK: - 2026-08-16 group D (directory indexes)
        //
        // All three below are the same shape: a vendor's plain Apache/MirrorBrain
        // directory listing of version folders, sorted ALPHABETICALLY (not
        // numerically) by every one of these servers — confirmed for Opera by
        // diffing the default listing against an explicit `?C=N;O=A` (name,
        // ascending) request: identical. Alphabetical sort makes `selectHighest`
        // mandatory (`"100.0…" < "99.0…"` as strings, so first-in-document is
        // often not the newest), and — for exactly the same reason — makes it UNSAFE
        // to build the install/download URL from ANY single match (first OR last):
        // once a version component crosses a digit-width boundary (Opera's 3-digit
        // major overtaking 2-digit, pgAdmin's major eventually reaching v10 and
        // sorting ahead of v9.x, a LibreOffice patch someday reaching two digits)
        // the alphabetically-first-or-last entry silently stops being the numeric
        // maximum, and a template built from it would download an OLDER build than
        // the one just reported as available. `VendorInstallSpec.URLSource` has no
        // "take the true max of every match" mode — only first (`bodyPattern`/
        // `bodyTemplate`) or last (`bodyPatternLast`) — so none of it can be made
        // to agree with `selectHighest`'s numeric max safely. All three are
        // therefore detection-only, even though every one of them mounts to a
        // genuine, notarized, Developer-ID-signed app (verified below) — the
        // blocker is this URL-construction gap, not the artifact.

        // Opera — `get.geo.opera.com` is Opera's own CDN mirror index, one folder
        // per released version (`134.0.5954.56/`), each holding a `mac/` dir with
        // `Opera_<version>_Setup.dmg`. The `href="…/"` anchor matches nothing but
        // version folders on this page (checked: every 4-dot-separated number in
        // the raw body is inside an `href`, none appear elsewhere — no stray dates
        // or sizes share that shape here).
        //
        // VERSION SCHEME TRAP: verified 2026-08-16 by mounting
        // `Opera_134.0.5954.56_Setup.dmg` — it holds `Opera.app`, notarized
        // Developer ID (Team A2P9LX4JPN, "Opera Software AS"), spctl accepted. But
        // `CFBundleShortVersionString` is only `"134.0"` while `CFBundleVersion` is
        // `"134.0.5954.56"` — exactly what the folder name carries. Comparing the
        // 4-part folder version against the 2-part marketing string would read
        // every release as a phantom major upgrade forever, so this is a build
        // comparison (`versionIsBuild`), not a marketing one.
        VendorProbeRecipe(
            bundleID: "com.operasoftware.Opera",
            url: URL(string: "https://get.geo.opera.com/pub/opera/desktop/")!,
            mode: .responseBody,
            versionPattern: #"href="([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/""#,
            downloadURL: URL(string: "https://www.opera.com/download"),
            changelogURL: URL(string: "https://blogs.opera.com/desktop/"),
            selectHighest: true,
            versionIsBuild: true,
            // ONE-CLICK via `.versionTemplate` — see LibreOffice below for why the
            // template must fill the RESOLVED version and not a first-match regex
            // on this alphabetically-sorted index.
            //
            // Despite the "Setup" in the filename this dmg is NOT a stub
            // downloader (the 1Password trap): verified 2026-08-16 by mounting
            // `Opera_134.0.5954.56_Setup.dmg` (260,530,261 B) — it carries
            // `Opera.app` itself, 560 MB on disk, com.operasoftware.Opera,
            // universal (x86_64 + arm64), Team A2P9LX4JPN (Opera Software AS),
            // notarized Developer ID, spctl accepted. Its `CFBundleVersion` is
            // `134.0.5954.56`, i.e. exactly the folder name this recipe compares,
            // which is what makes the template safe as well as the comparison.
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://get.geo.opera.com/pub/opera/desktop/"
                    + "{version}/mac/Opera_{version}_Setup.dmg"),
                kind: .dmg)),

        // LibreOffice — `download.documentfoundation.org/libreoffice/stable/` is a
        // MirrorBrain index of version folders (`26.2.5/`). `href="X.Y.Z/"` matches
        // only version folders; the page carries no other dotted-numeric hrefs.
        //
        // ONE-CLICK, via `.versionTemplate`. The mac artifact sits two levels below
        // the index, at a path that is fully determined by the version:
        // `<ver>/mac/aarch64/LibreOffice_<ver>_MacOS_aarch64.dmg` (HEAD 2026-08-16:
        // 302 to a MirrorBrain mirror, e.g. `mirror.usi.edu` / `mirror.fcix.net` —
        // the mirror changes per request, which is why the URL is built from the
        // canonical host and never cached). An earlier note here called the deeper
        // path a blocker; it isn't — what would have been a blocker is
        // `.bodyTemplate`, whose regexes take the FIRST match while this index is
        // sorted alphabetically and `selectHighest` deliberately picks a different
        // entry, so the URL could name an older release than the one reported.
        // `.versionTemplate` fills the resolved version instead, which is exactly
        // the string that was compared.
        //
        // aarch64 only, like the other arm64-pinned recipes here (GIMP, pgAdmin,
        // Meld). On an Intel Mac the download is refused by the runnable-arch gate
        // rather than installed — the fail-safe direction; LibreOffice does publish
        // an x86-64 dmg, and picking between them needs arch-aware plumbing the
        // vendor path doesn't have yet (only the GitHub rules do).
        //
        // VERSION SCHEME TRAP (the one flagged in the brief): the index publishes
        // 3-segment versions (`26.2.5`) but the installed bundle reports 4
        // (`CFBundleShortVersionString` AND `CFBundleVersion` both `26.2.5.2`,
        // verified 2026-08-16 by mounting the aarch64 dmg — notarized Developer ID,
        // Team 7P5S3ZLCN7, "The Document Foundation", spctl accepted). Comparing a
        // bare `26.2.5` against `26.2.5.2` is safe either way `VersionComparator`
        // treats missing trailing components as `0`: it reads the installed copy as
        // (at worst) equal, never triggers a phantom update. The only blind spot is
        // a pure 4th-component hotfix under an unchanged 3-segment folder, which
        // this index can't see at all — same acceptable direction as OneDrive's
        // first-three-components recipe above.
        VendorProbeRecipe(
            bundleID: "org.libreoffice.script",
            url: URL(string: "https://download.documentfoundation.org/libreoffice/stable/")!,
            mode: .responseBody,
            versionPattern: #"href="([0-9]+\.[0-9]+\.[0-9]+)/""#,
            downloadURL: URL(string: "https://www.libreoffice.org/download/download-libreoffice/"),
            changelogURL: URL(string: "https://www.libreoffice.org/release-notes/"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://download.documentfoundation.org/libreoffice/stable/"
                    + "{version}/mac/aarch64/LibreOffice_{version}_MacOS_aarch64.dmg"),
                kind: .dmg)),

        // pgAdmin4 — `ftp.postgresql.org/pub/pgadmin/pgadmin4/` lists both version
        // folders (`v9.17/`) and non-version siblings (`apt/`, `autoupdate/`,
        // `snapshots/`, `yum/`, `README`) — none of the siblings carry a digit
        // immediately after the `v`, so anchoring on `href="v([0-9.]+)/"` takes only
        // the releases; `snapshots/` in particular is a trap left alone deliberately
        // (dev builds, not what a stable-channel install should ever be pointed at).
        // The mac artifact is one level deeper (`v9.17/macos/pgadmin4-9.17-arm64.dmg`),
        // which is what makes this the same shape as LibreOffice above.
        //
        // Verified 2026-08-16 by mounting `pgadmin4-9.17-arm64.dmg`: `pgAdmin 4.app`,
        // CFBundleShortVersionString exactly `"9.17"` (matches the probe 1:1, no
        // build/marketing mismatch here), notarized Developer ID, Team TCHGL2R7C5
        // ("David Page"), spctl accepted.
        VendorProbeRecipe(
            bundleID: "org.pgadmin.pgadmin4",
            url: URL(string: "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/")!,
            mode: .responseBody,
            versionPattern: #"href="v([0-9]+\.[0-9]+)/""#,
            downloadURL: URL(string: "https://www.pgadmin.org/download/pgadmin-4-macos/"),
            changelogURL: URL(string: "https://www.pgadmin.org/docs/pgadmin4/latest/release_notes.html"),
            selectHighest: true,
            // ONE-CLICK via `.versionTemplate` (same reasoning as Opera and
            // LibreOffice: the resolved version, never a first-match regex, on an
            // index whose ordering is alphabetical — `v10.0` will one day sort
            // before `v9.17`, and that day this template still builds the right
            // URL because it is handed the number that won the comparison).
            //
            // Verified 2026-08-16 by mounting `pgadmin4-9.17-arm64.dmg`
            // (233,075,920 B): `pgAdmin 4.app`, org.pgadmin.pgadmin4,
            // CFBundleShortVersionString `9.17` — exactly what the index publishes,
            // so no scheme mismatch — Team TCHGL2R7C5 (David Page), notarized
            // Developer ID, spctl accepted. (`CFBundleVersion` is an unrelated
            // `4280.88`; the recipe compares marketing, which is the field that
            // agrees.) arm64-only artifact, like the other arm64-pinned recipes
            // here; an Intel Mac is refused by the runnable-arch gate rather than
            // given a build it can't run.
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/"
                    + "v{version}/macos/pgadmin4-{version}-arm64.dmg"),
                kind: .dmg)),

        // MARK: - 2026-08-16 group A (GIMP, Compass, Meld)

        // GIMP — the project's own `gimp_versions.json` (served from gimp.org,
        // status 200, 139419 bytes when checked 2026-08-16). `STABLE` is a single
        // release object (not an array of channels), so anchoring on the "STABLE"
        // key and taking the object's own `"version"` field is enough — no risk of
        // reading `DEVELOPMENT`'s or `NIGHTLY`'s number instead. Verified value:
        // `3.2.4`, which matches BOTH `CFBundleShortVersionString` and
        // `CFBundleVersion` of the mounted arm64 dmg — the same scheme the app
        // reports, so no `versionIsBuild`.
        //
        // One-click: the JSON carries no download URL, only a `macos` array of
        // per-arch filenames (`gimp-3.2.4-arm64.dmg`). The real download host
        // (`download.gimp.org/gimp/v{major.minor}/macos/{filename}`) was confirmed
        // by HEAD (200, resolves through their mirror network via `Location`), so
        // the install URL is rebuilt from two captures off the same `macos` block:
        // the filename's major.minor and the filename itself. The published
        // `sha512`/`sha256` fields are HEX, not the base64 SHA-512 `checksumPattern`
        // verifies, so no checksum is wired — the Team-ID signature gate is the
        // only defense, same tradeoff as Gemini above.
        // Installed-bundle identity confirmed 2026-08-16: `org.gimp.gimp`,
        // notarized Developer ID, Team T25BQ8HSJF (GNOME Foundation) — `spctl`
        // accepted as "Notarized Developer ID".
        VendorProbeRecipe(
            bundleID: "org.gimp.gimp",
            url: URL(string: "https://www.gimp.org/gimp_versions.json")!,
            mode: .responseBody,
            versionPattern: #""STABLE"\s*:\s*\[\s*\{\s*"version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.gimp.org/downloads/"),
            changelogURL: URL(string: "https://www.gimp.org/news/"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.gimp.org/gimp/v{0}/macos/{1}",
                    fields: [
                        #""filename"\s*:\s*"gimp-([0-9]+\.[0-9]+)\.[0-9]+-arm64\.dmg""#,
                        #""filename"\s*:\s*"(gimp-[0-9.]+-arm64\.dmg)""#,
                    ]),
                kind: .dmg)),

        // MongoDB Compass — the vendor's own download-center JSON
        // (`s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json`,
        // status 200, 7814 bytes when checked 2026-08-16). `versions` is
        // newest-first (a single current entry in practice); `versions[0]._id`
        // read `1.49.14`, matching BOTH `CFBundleShortVersionString` and
        // `CFBundleVersion` of the mounted arm64 dmg — no `versionIsBuild` needed.
        // The same entry's `platform` array carries a `download_link` per
        // arch/os; the arm64/darwin one is captured directly (no template
        // needed, unlike GIMP). No checksum is published in this feed.
        // Installed-bundle identity confirmed 2026-08-16: `com.mongodb.compass`,
        // notarized Developer ID, Team 4XWMY46275 (MongoDB, Inc.) — `spctl`
        // accepted as "Notarized Developer ID".
        VendorProbeRecipe(
            bundleID: "com.mongodb.compass",
            url: URL(string: "https://s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json")!,
            mode: .responseBody,
            versionPattern: #""_id"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.mongodb.com/try/download/compass"),
            changelogURL: URL(string: "https://www.mongodb.com/docs/compass/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""arch"\s*:\s*"arm64"\s*,\s*"os"\s*:\s*"darwin"\s*,\s*"name"\s*:\s*"[^"]*"\s*,\s*"download_link"\s*:\s*"([^"]+)""#),
                kind: .dmg)),

        // Meld — TRAP: upstream GNOME Meld (gitlab.gnome.org) is at 3.24.0, but
        // there is no official macOS build; the only one is a third-party repack
        // by dehesselle (`gitlab.com/dehesselle/meld_macos`) that stalled the
        // wrapped app at upstream 3.22.3 and instead versions ITS OWN repacks with
        // a trailing `+<build>` (`v3.22.3+105`). Reading gitlab.gnome.org would
        // report an update (3.24.0) this macOS build can never actually install.
        // Probed `gitlab.com/api/v4/projects/dehesselle%2Fmeld_macos/releases`
        // (status 200, 24296 bytes / 7 releases when checked 2026-08-16), whose
        // default order (`order_by=released_at&sort=desc`, confirmed by the
        // response's own `Link` header) puts the newest release first, so
        // first-match is correct without `selectHighest`.
        //
        // The mounted arm64 dmg's `CFBundleShortVersionString` is `3.22.3` and
        // `CFBundleVersion` is `105` — i.e. the tag's two halves map to the
        // bundle's two DIFFERENT version fields. Three separate releases share
        // marketing `3.22.3` with different builds (`+96`, `+100`, `+105`, all
        // 2025 repack-only bumps with no upstream version change) — comparing
        // only the marketing half would silently miss those updates (the
        // "folded-build" gap). So `versionPattern` captures ONLY the build
        // integer and `versionIsBuild` routes it against `CFBundleVersion`;
        // `displayVersionPattern` captures the full `3.22.3+105` string so the
        // row still shows the vendor's own scheme instead of a bare `105`.
        // The feed carries no base64 SHA-512 (GitLab's `x-checksum-sha256`
        // response header is hex, and isn't in the body anyway), so no
        // `checksumPattern`; the downloaded arm64 dmg's sha256 was independently
        // verified to match that header byte-for-byte, but that's outside what
        // `checksumPattern` can express (base64 SHA-512 only).
        // Installed-bundle identity confirmed 2026-08-16: `org.gnome.Meld`,
        // notarized Developer ID, Team SW3D6BB6A6 (Rene de Hesselle) — `spctl`
        // accepted as "Notarized Developer ID".
        VendorProbeRecipe(
            bundleID: "org.gnome.Meld",
            url: URL(string: "https://gitlab.com/api/v4/projects/dehesselle%2Fmeld_macos/releases")!,
            mode: .responseBody,
            versionPattern: #""tag_name"\s*:\s*"v[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)""#,
            downloadURL: URL(string: "https://gitlab.com/dehesselle/meld_macos/-/releases"),
            changelogURL: URL(string: "https://gitlab.com/dehesselle/meld_macos/-/releases"),
            versionIsBuild: true,
            displayVersionPattern: #""tag_name"\s*:\s*"v([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""name"\s*:\s*"Meld-[0-9.+]+_arm64\.dmg"[^}]*"direct_asset_url"\s*:\s*"([^"]+)""#),
                kind: .dmg)),

        // MARK: - 2026-08-16 Telegram Desktop

        // Telegram Desktop (com.tdesktop.Telegram — NOT the App Store's Telegram
        // for macOS, ru.keepcoder.Telegram, which is a different app entirely and
        // stays on the MAS channel). The official download link 302s straight to
        // the versioned dmg — `telegram.org/dl/desktop/mac` →
        // `td.telegram.org/tmac/tsetup.7.0.9.dmg` — so the redirect filename is
        // both the version signal and the download.
        //
        // NOT `td.telegram.org/current4`, which is what the app's own updater
        // reads: that JSON states versions as PACKED INTEGERS (`"armac": {"stable":
        // {"released": "7000009"}}` = 7.0.9, major*10^6 + minor*10^3 + patch).
        // Decoding it needs arithmetic, and every recipe here is regex-only — a
        // pattern could only ever carry `7000009` forward, which compares against
        // nothing the bundle reports. The redirect states the same release in the
        // scheme the app actually uses.
        //
        // Verified 2026-08-16 by downloading and mounting the 7.0.9 dmg:
        // `Telegram.app`, com.tdesktop.Telegram, CFBundleShortVersionString AND
        // CFBundleVersion both exactly `7.0.9` (no build/marketing split to work
        // around), Team C67CF9S4VU (Telegram FZ-LLC), notarized Developer ID
        // (`spctl`: source=Notarized Developer ID), universal (x86_64 + arm64).
        VendorProbeRecipe(
            bundleID: "com.tdesktop.Telegram",
            url: URL(string: "https://telegram.org/dl/desktop/mac")!,
            mode: .redirectFilename,
            versionPattern: #"tsetup\.([0-9]+(?:\.[0-9]+)+)\.dmg"#,
            downloadURL: URL(string: "https://desktop.telegram.org/"),
            changelogURL: URL(string: "https://telegram.org/blog"),
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://telegram.org/dl/desktop/mac")!),
                kind: .dmg),
            followRedirects: false),

        // EasyFind (DEVONtechnologies) — no Sparkle at all: the app carries
        // neither `Sparkle.framework` nor an `SUFeedURL` (verified 2026-08-16 by
        // unpacking the shipped zip), so a copy installed from the vendor's site
        // has no source whatsoever. Homebrew's cask is `auto_updates:false` and
        // therefore covers brew-installed copies already — this recipe is for the
        // direct-download ones.
        //
        // The source is the shared freeware page, which lists several unrelated
        // apps with their own version numbers (1.9.11, 6.0.1, 4.5.3 …). The
        // pattern is anchored to EasyFind's own download PATH rather than to any
        // "Version X" text, so it cannot drift onto a neighbour's number:
        //   …/download/freeware/easyfind/5.0.2/EasyFind.app.zip
        // The install URL is the same link, read from the same page — no
        // templating, so a vendor rename of the artifact can't silently 404.
        //
        // One-click verified 2026-08-16 against that zip: `EasyFind.app`,
        // org.grunenberg.EasyFind, 5.0.2, Team 679S2QUWR8 (DEVONtechnologies,
        // LLC), notarized Developer ID, spctl accepted.
        VendorProbeRecipe(
            bundleID: "org.grunenberg.EasyFind",
            url: URL(string: "https://www.devontechnologies.com/apps/freeware")!,
            mode: .responseBody,
            versionPattern:
                #"/download/freeware/easyfind/([0-9]+(?:\.[0-9]+)+)/EasyFind\.app\.zip"#,
            downloadURL: URL(string: "https://www.devontechnologies.com/apps/freeware"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://download\.devontechnologies\.com/download/freeware/easyfind/[0-9.]+/EasyFind\.app\.zip)"#),
                kind: .zip)),

        // MARK: - 2026-08-16 group C (SourceForge)

        // GrandPerspective — Developer ID (Erwin Bonsma, 3Z75QZGN66), notarized,
        // stapled ticket; `spctl -a -t exec` accepts the mounted app. One-click
        // verified 2026-08-16 against the 3.7.2 dmg: `CFBundleIdentifier` and
        // `CFBundleShortVersionString` on the mounted app match what the probe
        // reports.
        sourceForgeMacRecipe(
            bundleID: "net.sourceforge.grandperspectiv",
            project: "grandperspectiv",
            versionPattern:
                #""mac":\s*\{[^}]*?"filename":\s*"/grandperspective/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/GrandPerspective-[0-9_]+\.dmg""#,
            changelogURL: URL(string: "https://sourceforge.net/p/grandperspectiv/news/")!,
            installKind: .dmg),

        // TigerVNC — Developer ID (Brian Hinz, S5LX88A9BW), notarized; `spctl`
        // accepts the mounted app. One-click verified 2026-08-16 against the
        // 1.16.0 dmg the same way.
        sourceForgeMacRecipe(
            bundleID: "com.tigervnc.tigervnc",
            project: "tigervnc",
            versionPattern:
                #""mac":\s*\{[^}]*?"filename":\s*"/stable/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/TigerVNC-[0-9.]+\.dmg""#,
            changelogURL: URL(string: "https://github.com/TigerVNC/tigervnc/releases")!,
            installKind: .dmg),

        // qBittorrent is NOT here — it moved to a GitHub release rule (see
        // `GitHubReleasesSource`). Upstream publishes the same macOS dmg on both
        // SourceForge and GitHub Releases, and GitHub is the better read: no WAF
        // to work around (this file's SourceForge recipes need a UA override),
        // and the tag is the release itself rather than a "best release" guess.
        // It stays detection-only either way — that is a property of upstream's
        // signature, not of the endpoint.

        // MARK: - 2026-08-25 Longbridge Desktop

        // Longbridge Desktop — the vendor's compact stable JSON is the same
        // manifest used by its release-notes site. `version` matches the mounted
        // app's CFBundleShortVersionString exactly (0.19.1); CFBundleVersion is a
        // timestamp-like build (20260820.080114) and must not be compared.
        //
        // The response carries both macOS architectures. DuoUpdater currently
        // runs this official-website install path on Apple Silicon, so the URL
        // pattern is deliberately pinned to `macos-aarch64.dmg` instead of taking
        // the first arbitrary dmg asset. Verified against the mounted 0.19.1
        // artifact: com.longbridge.app.desktop, Team 45NG8MW7WK, accepted by
        // Gatekeeper as Notarized Developer ID. The DMG is self-contained.
        VendorProbeRecipe(
            bundleID: "com.longbridge.app.desktop",
            url: URL(string: "https://assets.lbkrs.com/github/release/longbridge-desktop/stable/latest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,4})""#,
            downloadURL: URL(string: "https://longbridge.com/desktop/")!,
            changelogURL: URL(string: "https://longbridge.com/desktop/release-notes/")!,
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://assets\.lbkrs\.com/github/release/longbridge-desktop/stable/longbridge-v[0-9.]+-macos-aarch64\.dmg)""#),
                kind: .dmg)),

        // Longbridge Desktop Preview — a SEPARATE bundle id
        // (`com.longbridge.app.desktop.preview`, "Longbridge Preview.app"), so
        // `ReleaseChannel.detect` resolves it via the `.preview` bundle-id suffix
        // and the two trains cannot be confused by bundle id alone.
        //
        // The channel has been DE-LISTED from the vendor's site but not retired:
        // `/desktop/release-notes/preview/` still returns 200 while rendering an
        // EMPTY version list (stable's index server-renders 48 links), and
        // `/desktop/preview/` is 404 — there is no download landing page. The
        // per-version notes pages, this manifest, and the artifacts are all still
        // published, so a user who already runs Preview can be updated in place;
        // they just cannot discover a new one through the website. That is why
        // `changelogURL` points at the (currently empty) preview index rather than
        // a version-specific page: it is the right place conceptually and will
        // repopulate on its own if the vendor restores the listing.
        //
        // Two structural differences from the stable manifest, both deliberate
        // here: the version carries a `-preview.N` suffix (so the pattern requires
        // it — the stable pattern's trailing quote cannot match this shape, and
        // this one cannot match stable's, verified both directions against the
        // live bodies), and preview assets ship WITHOUT the `sha256` field stable
        // includes. No checksum is asserted either way (`checksumPattern` wants a
        // base64 SHA-512), so this costs nothing today, but it is a sign the
        // preview manifest is maintained at a lower standard than stable's.
        //
        // Verified 2026-08-26 against the downloaded 0.19.0-preview.1 artifact
        // (75,399,519 B): com.longbridge.app.desktop.preview, arm64,
        // Team 45NG8MW7WK — the SAME team as stable, which is what
        // `VendorInstaller`'s signature gate requires — spctl accepted as
        // Notarized Developer ID.
        VendorProbeRecipe(
            bundleID: "com.longbridge.app.desktop.preview",
            url: URL(string: "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/latest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,4}-preview\.[0-9]+)""#,
            changelogURL: URL(string: "https://longbridge.com/desktop/release-notes/preview/")!,
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://assets\.lbkrs\.com/github/release/longbridge-desktop/preview/longbridge-v[0-9.]+-preview\.[0-9]+-macos-aarch64\.dmg)""#),
                kind: .dmg),
            channel: .preview),
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

    /// One recipe for a project on SourceForge's `best_release.json` API — the
    /// shape GrandPerspective, TigerVNC and qBittorrent all share.
    ///
    /// TRAP: the API's TOP-LEVEL `release` key names whichever platform
    /// SourceForge treats as the project's primary download — often Windows
    /// (verified on tigervnc and qbittorrent, both of which put a `.exe` there).
    /// The only field naming THIS project's macOS artifact is
    /// `platform_releases.mac`, so every regex here is anchored to that one
    /// block. Even that isn't automatically trustworthy in general — a sibling
    /// project, gtkwave, points its `mac` entry at a source tarball that was
    /// never shipped as a macOS app — so `versionPattern` is supplied by the
    /// caller per project, verified against that project's real filename
    /// convention, rather than guessed from a shared template.
    ///
    /// The API's own `platform_releases.mac.url` is a pre-signed, time-limited
    /// CDN link (`…?ts=…`), unusable as a stable install source. The install
    /// spec instead rebuilds SourceForge's documented permanent redirect —
    /// `sourceforge.net/projects/<project>/files<filename>/download` — from the
    /// same block's `filename` field, which every project's `mac` entry carries
    /// in the same generic shape.
    private static func sourceForgeMacRecipe(
        bundleID: String,
        project: String,
        versionPattern: String,
        downloadURL: URL? = nil,
        changelogURL: URL,
        installKind: VendorInstallerKind?
    ) -> VendorProbeRecipe {
        let filenameCapture = #""mac":\s*\{[^}]*?"filename":\s*"([^"]+)""#
        return VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string: "https://sourceforge.net/projects/\(project)/best_release.json")!,
            mode: .responseBody,
            versionPattern: versionPattern,
            downloadURL: downloadURL,
            changelogURL: changelogURL,
            install: installKind.map { kind in
                VendorInstallSpec(
                    urlSource: .bodyTemplate(
                        "https://sourceforge.net/projects/\(project)/files{0}/download",
                        fields: [filenameCapture]),
                    kind: kind)
            },
            // SourceForge's edge answers 200 to a plain tool UA and 403 to the
            // browser-like default this probe otherwise sends (measured
            // 2026-08-16: same URL, same second, UA the only variable). Curl-based
            // spot checks never see this — only the production path does, which is
            // how `duo verify` caught all three of these at once.
            requestHeaders: ["User-Agent": "DuoUpdater/0.1"])
    }
}
