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

    /// Path, relative to the `.app` the download unpacks to, of a SECOND archive
    /// that holds the real payload — for a vendor whose download is an installer
    /// stub carrying the app inside itself.
    ///
    /// DoubaoIme is the case in hand: `DoubaoImeInstaller_v90703_release.zip`
    /// unpacks to `DoubaoImeInstaller.app`, a 190 MB stub whose
    /// `Contents/Resources` holds `DoubaoIme.zip` plus the `install.sh` it runs.
    /// Without this the installer would extract the stub, and the bundle-id gate
    /// would (correctly) refuse to swap `com.bytedance.inputmethod.doubaoime.installer`
    /// over `com.bytedance.inputmethod.doubaoime`.
    ///
    /// The unwrap is not a hole in the gates, it moves one of them: the nested
    /// archive lives under `Contents/Resources`, which the stub's own code
    /// signature seals, so `VendorInstaller` verifies the stub (signature + the
    /// installed app's Team — NOT its bundle id, which is a sibling by
    /// construction) before reading anything out of it. Every gate then runs again
    /// on the payload itself, bundle id included.
    public let nestedArchivePath: String?

    public init(
        urlSource: URLSource,
        kind: VendorInstallerKind,
        checksumPattern: String? = nil,
        requestHeaders: [String: String] = [:],
        nestedArchivePath: String? = nil
    ) {
        self.urlSource = urlSource
        self.kind = kind
        self.checksumPattern = checksumPattern
        self.requestHeaders = requestHeaders
        self.nestedArchivePath = nestedArchivePath
    }
}

/// The machine a recipe's build can actually run on — for a vendor that keeps two
/// release trains open because the newer one dropped hardware or OS versions the
/// older one still serves.
///
/// This is not the installer's safety net: `SignatureVerifier`'s architecture gate
/// already refuses a downloaded bundle this Mac cannot start. This is the
/// *detection* half. Without it a machine that can only run the old train is still
/// told the new train's version, reads as "update available" forever, and is handed
/// a one-click that can only fail — or, worse for an OS floor, succeed and leave an
/// app that won't launch.
///
/// It is also what upholds the precondition `VendorProbeSource.best(of:)` states
/// for a channel with several endpoints — *every endpoint listed for one channel
/// must serve a build this machine may legitimately install*. Gating the newer
/// endpoint is what lets the older one keep answering on the machines it is for,
/// instead of being silently out-ranked by a version they can't use.
///
/// Raycast is the case in hand (measured 2026-08-27): `x.raycast-releases.com`
/// serves v2, which requires macOS 26 and Apple silicon
/// (https://www.raycast.com/new — "macOS Tahoe and Apple Silicon required") and
/// ships an arm64-only dmg, while `releases.raycast.com` still serves the
/// universal v1 train. NEITHER endpoint states the requirement — both answer any
/// client with the same JSON regardless of the UA's OS and architecture — so it
/// has to be recorded here.
public struct VendorHostRequirement: Sendable, Equatable {

    /// Lowest macOS this build runs on, as a plain numeric version ("26.0"),
    /// compared exactly the way a Sparkle item's `sparkle:minimumSystemVersion` is.
    /// nil → no OS floor.
    public let minimumSystemVersion: String?

    /// The architectures this build ships. Empty → architecture-neutral.
    ///
    /// Deliberately a plain membership test, with no Rosetta allowance: the only
    /// direction that ever translated is Intel-on-Apple-silicon, and a recipe
    /// naming `.x86_64` alone would still be caught by `HostArch.canRunIntelBuilds`
    /// at install time. The direction this field exists for — an arm64-only build
    /// on an Intel Mac — has never been runnable at all.
    public let architectures: [HostArch]

    public init(minimumSystemVersion: String? = nil, architectures: [HostArch] = []) {
        self.minimumSystemVersion = minimumSystemVersion
        self.architectures = architectures
    }

    /// Whether a host meets this requirement. Takes the host as arguments rather
    /// than reading `HostArch.current` / `ProcessInfo` so the gate is testable off
    /// whatever machine the tests happen to run on.
    public func isSatisfied(byOS osVersion: String, arch: HostArch) -> Bool {
        if !architectures.isEmpty, !architectures.contains(arch) { return false }
        if let minOS = minimumSystemVersion, !minOS.isEmpty,
           VersionComparator.compare(osVersion, minOS) == .orderedAscending {
            return false
        }
        return true
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

    /// The machine this recipe's build runs on, when the vendor's own endpoint
    /// won't say. nil (the overwhelmingly common case) means "any Mac this app
    /// already runs on" and changes nothing. See `VendorHostRequirement`.
    public let hostRequirement: VendorHostRequirement?

    /// Restricts this recipe to an installed app whose `CFBundleShortVersionString`
    /// matches this pattern (searched, not required to anchor the whole string —
    /// callers write their own `^`/`$` where that matters). nil (the overwhelming
    /// common case) means "any installed version of this bundle id" and changes
    /// nothing.
    ///
    /// Exists for a vendor that keeps more than one MAJOR-VERSION generation
    /// under one shared bundle id, each independently and currently maintained,
    /// where crossing from one to another is a separate (often separately
    /// priced) product decision, not "the next version of what you have" —
    /// Carbon Copy Cloner is the case in hand: CCC 5/6/7 all report
    /// `com.bombich.ccc`, Bombich keeps shipping point releases to all three
    /// (`ccc-5.1.28.6213.zip`, `ccc-6.1.13.7699.zip`, `ccc-7.1.6.8368.zip`, all
    /// live 2026-08-29), and upgrading between majors needs a new license
    /// ("We do not sell CCC 4 or CCC 5 licenses. To use CCC 4 or 5, please
    /// purchase a CCC 6 license" — bombich.com/en/kb/ccc/6). Without this gate a
    /// CCC 5 install on Big Sur — which cannot even run CCC 7 (Ventura+) — would
    /// be told a "7.1.6" update exists, because the marketing string genuinely
    /// does sort higher; that comparison is real by numeral and wrong by
    /// product, the same shape of trap `VersionComparator`'s "never compare
    /// across namespaces" rule exists for. This is `hostRequirement`'s twin,
    /// gating on the INSTALLED APP's own version rather than on the Mac running
    /// it — see `matchesInstalled(version:)`.
    public let installedVersionPattern: String?

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

    /// Field labels deliberately kept OUT of `channelAnchorSurface`: the ones
    /// that LABEL a recipe rather than decide what text it reads.
    ///
    /// A `.recipeAnchor` proof asserts the recipe is still tied to its own
    /// channel by something structural. Letting it match these would make that
    /// assertion vacuous in the most obvious way possible: a `.beta` recipe
    /// carries the literal string "beta" in `channel`, so an anchor of `beta`
    /// would be satisfied by the very fact it is a beta recipe, forever,
    /// whatever happened to the endpoint. `bundleID`/`variant` are the same
    /// shape of tautology; `downloadURL`/`changelogURL` are where the user is
    /// SENT, not where the version is read; `hostRequirement` is about the
    /// machine, not the channel; `installedVersionPattern` is `hostRequirement`'s
    /// twin — about which already-installed generation this recipe applies to,
    /// not about the channel or where THIS recipe reads its own answer from.
    ///
    /// Everything else is in, including fields added after this list was
    /// written — see `channelAnchorSurface`.
    static let nonAnchorFields: Set<String> = [
        "bundleID", "channel", "variant", "downloadURL", "changelogURL", "hostRequirement",
        "installedVersionPattern",
    ]

    /// Everything this recipe says about WHERE it reads and WHAT it looks for —
    /// the text a `ChannelArtifactProof.recipeAnchor` is matched against.
    ///
    /// Derived by reflection, not by hand-listing fields, for the reason
    /// `localReads` above gives and then some. The hand-written version listed
    /// `url`, `versionPattern` and `install?.urlSource`; `entryStartPattern`
    /// arrived later and was not added, and neither would the next field be.
    /// That failure is the worst kind a guard has: it goes on passing while
    /// inspecting less, so nothing anywhere reads as broken. Deriving makes a
    /// new field part of the surface by construction, and
    /// `channelAnchorSurfaceCoversEveryRecipeField` makes adding one a decision
    /// somebody has to make out loud rather than one they make by omission.
    ///
    /// Joined with newlines because `.` does not cross a newline in
    /// `NSRegularExpression`'s default mode, and at least one live anchor spans
    /// a gap with `.*` (`"id":.*"rc"`). Per-field lines keep such a pattern from
    /// straddling two unrelated fields and matching something nobody meant.
    ///
    /// The WHOLE surface is no longer what a proof is matched against — a
    /// `.recipeAnchor` names the fields it relies on and is checked against each
    /// of them (see `channelAnchorFields` and issue #110). This stays as the
    /// union those field views are cut from, and as what the tests measure.
    public var channelAnchorSurface: String {
        channelAnchorFields.flatMap(\.lines).joined(separator: "\n")
    }

    /// The anchorable fields, in declaration order, each with the lines it
    /// contributes to `channelAnchorSurface`.
    ///
    /// Split per field because matching an anchor against the joined surface
    /// passes if ANY line matches, and a token that appears in two fields makes
    /// the guard survive either one drifting. WeChat DevTools RC is the live
    /// case: `"id": "rc"` sits in both `versionPattern` and the install
    /// `bodyPattern`, and the install half is the one that picks the artifact —
    /// so if that regex alone were rewritten, the version pattern would keep the
    /// proof green while the install fell back to whichever channel the vendor's
    /// `config.json` lists first (Stable). Issue #110.
    ///
    /// Still derived by reflection: naming a field in a proof is a claim about
    /// where the recipe's channel identity lives, but WHICH fields exist is not
    /// something a hand-written list should get to decide — that is the mistake
    /// `entryStartPattern` exposed. A proof may name any anchorable field,
    /// including one added after this was written;
    /// `everyRegisteredAnchorNamesRealFields` fails loudly on a name that is not
    /// one, so a typo or a rename cannot turn a proof into a silent no-op.
    public var channelAnchorFields: [(label: String, lines: [String])] {
        Mirror(reflecting: self).children.compactMap { child in
            guard let label = child.label,
                  !Self.nonAnchorFields.contains(label) else { return nil }
            return (label, Self.anchorLines(of: child.value))
        }
    }

    /// The text one named field contributes, or nil when this recipe has no
    /// ANCHORABLE field by that name — either no such field at all, or one that
    /// only labels the recipe (`nonAnchorFields`). Callers must treat nil as a
    /// failure, never as "nothing to check": a proof pinned to a field that
    /// isn't there is a proof that cannot fail.
    public func channelAnchorSurface(ofField label: String) -> String? {
        channelAnchorFields.first { $0.label == label }
            .map { $0.lines.joined(separator: "\n") }
    }

    /// One line per string a value contains, walking into optionals, arrays,
    /// enum payloads and nested structs.
    ///
    /// Not `String(describing:)` on the field, because that renders any string
    /// nested inside something else through its DEBUG description — quotes come
    /// back escaped (`Optional("{\"id\":")`) and an anchor written to match the
    /// vendor's actual text stops matching. Three of the five anchors registered
    /// today contain quotes or angle brackets, so this is not hypothetical: it
    /// is why the old hand-written surface reached into `install?.urlSource`
    /// with `String(describing:)` and quietly could not have matched a quoted
    /// marker there either. Yielding each string verbatim removes the trap
    /// rather than documenting it.
    private static func anchorLines(of value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let url = value as? URL { return [url.absoluteString] }
        let mirror = Mirror(reflecting: value)
        // No children: a leaf we can only describe (a Bool, an Int, a payloadless
        // enum case, an empty collection, `nil`).
        guard !mirror.children.isEmpty else { return [String(describing: value)] }
        return mirror.children.flatMap { anchorLines(of: $0.value) }
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

    /// Optional regex marking where each entry begins in a body that lists
    /// several releases — e.g. `\{"date":"` for a JSON feed whose items each
    /// start with a `date` key. When set, the source slices the body into
    /// entries at every match (one match's start to the next match's start,
    /// last entry running to the end of the body), keeps the entries where
    /// `versionPattern` matches, and picks the one whose extracted version
    /// compares highest (the same `VersionComparator` ordering
    /// `highestVersion`/`highestVersionedURL` use). `versionPattern`,
    /// `displayVersionPattern`, `publishedAtPattern`, and the install spec's
    /// `.bodyPattern`/`.bodyPatternRelative`/`.bodyTemplate` URL are then all
    /// resolved against that ONE winning entry, so they can never land on
    /// different releases — see `VendorProbeRecipe.highestVersionEntry`.
    ///
    /// This exists because a feed ordered by *publication date* rather than by
    /// *version* breaks every first-match pattern above at once whenever two
    /// release trains are open simultaneously (Android Studio: a newer feature
    /// version's Canary can be published before an older version's RC, so the
    /// RC — not the newer Canary — sits first in the feed). Flipping
    /// `selectHighest` alone does not fix this: it would pick the version by
    /// comparison while `displayVersionPattern` and the install URL stayed
    /// first-match, landing on three different releases' worth of data.
    ///
    /// Nil (the default) leaves every pattern reading the whole body,
    /// first-match, exactly as before this field existed. Also the fallback
    /// when the pattern matches fewer than two entries, or when no entry's
    /// `versionPattern` matches — better a possibly-stale first-match answer
    /// than no answer at all.
    ///
    /// Narrowing to one entry also narrows `checksumPattern` (fine — a miss
    /// there degrades loudly to `.checksumPatternNoMatch`) and the install
    /// spec's `.bodyPattern`/`.bodyPatternRelative`/`.bodyTemplate` URL sources
    /// (fine — that's the whole point). It is a TRAP for `.bodyPatternLast` and
    /// `.bodyPatternHighestVersioned`: with only one entry left to search, "last
    /// match" and "highest-versioned match" both collapse to plain first-match.
    /// `.bodyPatternHighestVersioned` exists SPECIFICALLY as the
    /// position-independent alternative to first-match (its own doc cites the
    /// Docker 4.86-before-4.87 wrong-install this primitive is a sibling fix
    /// for) — pairing it with `entryStartPattern` would quietly throw that
    /// protection away. Don't combine them.
    ///
    /// Also re-anchors `^`, `$`, `\A`, `\z` and lookbehind to entry boundaries
    /// rather than the whole body's — a pattern relying on "start/end of the
    /// document" now means "start/end of one entry" instead. Six recipes in
    /// this registry pin `versionPattern` with `^…$` today; none has adopted
    /// `entryStartPattern`, and this is why one shouldn't without re-deriving
    /// those patterns against a single sliced entry first.
    ///
    /// One more shape worth naming rather than discovering later: selection now
    /// searches the feed's entire history, not just its recent head, so a
    /// malformed or ancient build id that happens to out-rank everything
    /// current under `VersionComparator` would pin the probe on it permanently
    /// — a hazard first-match-over-a-recent-head never had, since a stale entry
    /// simply ages out of view. Concretely, in Android Studio's own feed
    /// (671 items, 2026-08-27): 42 of the 555 Canary/Beta/RC-labeled build ids
    /// are two-segment 2018-era values like `AI-173.4688006` (`VersionComparator`
    /// ranks `173` below `261`/`262`, so today none of them win — but a scheme
    /// that changed digit count could invert that), and 198 lack the `|`
    /// separator `displayVersionPattern` requires, so `display` would come back
    /// nil for those even where `version` still resolves.
    public let entryStartPattern: String?

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
        entryStartPattern: String? = nil,
        install: VendorInstallSpec? = nil,
        requestBody: RequestBody? = nil,
        requestHeaders: [String: String] = [:],
        followRedirects: Bool = true,
        channel: ReleaseChannel = .stable,
        identities: [ProbeIdentity] = [],
        track: RolloutTrack? = nil,
        variant: String? = nil,
        hostRequirement: VendorHostRequirement? = nil,
        installedVersionPattern: String? = nil
    ) {
        self.bundleID = bundleID
        self.channel = channel
        self.url = url
        self.identities = identities
        self.track = track
        self.variant = variant
        self.hostRequirement = hostRequirement
        self.installedVersionPattern = installedVersionPattern
        self.mode = mode
        self.versionPattern = versionPattern
        self.downloadURL = downloadURL
        self.changelogURL = changelogURL
        self.selectHighest = selectHighest
        self.versionIsBuild = versionIsBuild
        self.displayVersionPattern = displayVersionPattern
        self.publishedAtPattern = publishedAtPattern
        self.entryStartPattern = entryStartPattern
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

    /// The runtime behind `entryStartPattern`: slice `text` into entries at every
    /// match of `entryStartPattern` (one match's start to the next match's
    /// start, the last entry running to the end of `text`), keep the entries
    /// where `versionPattern` matches, and return the substring of whichever
    /// entry's extracted version compares highest.
    ///
    /// Nil when `entryStartPattern` matches fewer than two entries (nothing to
    /// disambiguate) or when no entry's `versionPattern` matches — the caller
    /// falls back to running its own extractor against the whole body, exactly
    /// as it did before `entryStartPattern` existed.
    /// `selectHighest` mirrors the recipe's own flag: when true, EACH entry is
    /// scored by its highest internal match (`highestVersion`) rather than its
    /// first (`extractVersion`) — the same choice `VendorProbeSource` makes for
    /// the whole body when there is no `entryStartPattern` at all. Without this,
    /// a `selectHighest` recipe that also set `entryStartPattern` would have its
    /// entries scored by first-match while the version it goes on to report
    /// (computed by the caller with the SAME flag) uses highest-match — two
    /// different readings of "highest" disagreeing on which entry even won.
    /// No registry recipe combines the two today.
    public static func highestVersionEntry(
        in text: String, entryStartPattern: String, versionPattern: String,
        selectHighest: Bool = false
    ) -> String? {
        guard let startRegex = try? NSRegularExpression(pattern: entryStartPattern)
        else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let starts = startRegex.matches(in: text, options: [], range: full)
            .map { $0.range.location }
        guard starts.count > 1 else { return nil }

        let extractor = selectHighest ? Self.highestVersion : Self.extractVersion
        var best: (entry: String, version: String)?
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : ns.length
            let entry = ns.substring(with: NSRange(location: start, length: end - start))
            guard let candidate = extractor(entry, versionPattern) else { continue }
            if best == nil || VersionComparator.isNewer(candidate, than: best!.version) {
                best = (entry, candidate)
            }
        }
        guard let winner = best else { return nil }

        // Defend the "one entry, one release" claim this primitive exists to
        // make. It holds only while `entryStartPattern` slices between items —
        // if a future feed ever nests the start marker INSIDE one item, entries
        // split mid-item and the "winning" slice could carry one release's
        // version alongside a different release's download URL, silently and
        // with nothing failing: strictly worse than the pre-#76 first-match bug
        // this primitive exists to fix, just relocated rather than gone. A
        // genuinely self-contained entry shows up as its own `versionPattern`
        // matching exactly once; more than that means the slice most likely
        // isn't one release, so decline rather than trust it (the caller falls
        // back to whole-body first-match). Skipped under `selectHighest`, where
        // several matches inside one entry are the expected, wanted shape — the
        // extractor above already picked the right one among them, same as it
        // would over an un-sliced body.
        if !selectHighest {
            guard let versionRegex = try? NSRegularExpression(pattern: versionPattern)
            else { return nil }
            let winnerNS = winner.entry as NSString
            let matchCount = versionRegex.numberOfMatches(
                in: winner.entry, options: [], range: NSRange(location: 0, length: winnerNS.length))
            guard matchCount == 1 else { return nil }
        }
        return winner.entry
    }

    /// A copy of this recipe with `entryStartPattern` replaced — every other
    /// field carried over unchanged via `copy(...)` below. Exists so a caller
    /// (an A/B test of this exact field, mainly) that wants to vary ONE field
    /// can't silently drop another by hand-copying the initializer's full
    /// argument list — which is exactly how a live-probe test comparing
    /// "with the fix" against "without" dropped `identities`, `track` and
    /// `variant` the first time this primitive shipped, three fields the two
    /// arms of that test then no longer actually differed on by construction.
    public func with(entryStartPattern: String?) -> Self {
        copy(entryStartPattern: entryStartPattern)
    }

    /// Same, for `url` — the other field a live-probe A/B test needs to vary
    /// (pointing the shipping recipe at a loopback stub instead of the real
    /// endpoint) without touching anything else.
    public func with(url: URL) -> Self {
        copy(url: url)
    }

    /// The single place that reconstructs a recipe from `self` plus overrides —
    /// so `with(entryStartPattern:)` and `with(url:)` can't drift out of sync
    /// with each other, or with the initializer, the way two independent
    /// hand-copies would.
    private func copy(url: URL? = nil, entryStartPattern: String?? = nil) -> Self {
        Self(
            bundleID: bundleID, url: url ?? self.url, mode: mode, versionPattern: versionPattern,
            downloadURL: downloadURL, changelogURL: changelogURL, selectHighest: selectHighest,
            versionIsBuild: versionIsBuild, displayVersionPattern: displayVersionPattern,
            publishedAtPattern: publishedAtPattern,
            entryStartPattern: entryStartPattern ?? self.entryStartPattern,
            install: install, requestBody: requestBody, requestHeaders: requestHeaders,
            followRedirects: followRedirects, channel: channel, identities: identities,
            track: track, variant: variant, hostRequirement: hostRequirement,
            installedVersionPattern: installedVersionPattern)
    }

    /// Whether this recipe's build can run on the described machine. A recipe with
    /// no `hostRequirement` runs anywhere — the default that keeps every existing
    /// recipe's behaviour identical.
    public func runs(onOS osVersion: String, arch: HostArch) -> Bool {
        hostRequirement?.isSatisfied(byOS: osVersion, arch: arch) ?? true
    }

    /// Whether this recipe applies to an already-installed copy reporting
    /// `installed` as its `CFBundleShortVersionString`. A recipe with no
    /// `installedVersionPattern` applies to any installed version — the default
    /// that keeps every existing recipe's behaviour identical. A recipe THAT SETS
    /// one fails closed on a missing/unreadable installed version or an invalid
    /// pattern (a recipe author's bug caught by its own tests, not something to
    /// paper over at call time) — better this recipe silently declines than
    /// silently applies to every generation it was written to exclude.
    public func matchesInstalled(version installed: String?) -> Bool {
        guard let pattern = installedVersionPattern else { return true }
        guard let installed, let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(installed.startIndex..., in: installed)
        return regex.firstMatch(in: installed, options: [], range: range) != nil
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

    /// Comet's stable download gateway — the endpoint the probe reads AND the one
    /// the installer fetches. Declared once because those two must never diverge:
    /// see the recipe's comment.
    static let cometStableGateway = URL(
        string: "https://www.perplexity.ai/rest/browser/download"
            + "?channel=stable&platform=mac_arm64")!

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
        //
        // Release notes: Microsoft renamed the PER-CHANNEL enterprise docs pages
        // from `microsoft-edge-relnotes-<channel>` to
        // `microsoft-edge-relnote-<channel>` (singular) and the old spellings now
        // 404 — see issue #107. Not a blanket rename, and worth knowing before
        // guessing at any other page in that section: the security notes are still
        // `microsoft-edge-relnotes-security`, plural.
        //
        // Dev gets NO `changelogURL` at all, and that is the measured answer
        // rather than a guess. `learn.microsoft.com/en-us/deployedge/toc.json`
        // (2026-08-28) carries eight `relnote*` paths — Beta, Stable, Mobile Beta,
        // Mobile Stable, three `-archive-` companions, and the security page — and
        // not one of them is Dev. Four plausible Dev spellings all 404
        // (`…relnote-dev-channel`, `…relnotes-dev-channel`, `…relnote-dev`,
        // `…relnote-archive-dev-channel`), and Learn's own search API returns Beta,
        // Security and the release schedule for "Edge Dev channel release notes".
        // Microsoft stopped publishing Dev channel notes; pointing the button at
        // Beta's or Stable's page would show a Dev user another train's changes,
        // which is worse than showing none (same call as Thunderbird Daily below).
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Stable".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoft.com/edge/download"),
            changelogURL: URL(
                string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnote-stable-channel"),
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/?linkid=2093504")!),
                kind: .pkg)),
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac.Beta",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Beta".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoftedgeinsider.com/download"),
            changelogURL: URL(
                string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnote-beta-channel"),
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
        // ONE-CLICK, restored 2026-08-28 (withdrawn 2026-08-16 — see above), and
        // the reason it is back is that the install now has the same SHAPE as the
        // vendor's own update rather than the shape of its installer.
        //
        // What the stub's `install.sh` does is `rm -rf` the whole `WeType.app` and
        // `mv` a fresh one in, then `chown -R root:staff` + `chmod -R 775`. What
        // `WeTypeUpdater.app` — the updater that ships INSIDE the bundle and runs
        // for every ordinary release — does instead is keep the outer directory
        // and rotate `Contents` through `.Contents.update` / `.Contents.old` (its
        // binary carries those exact paths, plus `will exchange Contents:
        // previous=`). The second one is the update path, and it is the one
        // `InPlaceSwap.rotateContents` reproduces: the registered `.app` path, its
        // inode, its ownership and its modes are all left alone.
        //
        // `zip_download_url` is the real payload, not the ~3 MB stub the marketing
        // page links: a notarized `WeType.app`, Team 88L2Q4487U, which the code
        // signature + Team + bundle-id gates check before anything moves. The
        // response also carries `zip_download_md5`; `checksumPattern` is SHA-512
        // base64, so it is deliberately NOT wired up rather than mis-declared.
        //
        // The withdrawal was about the user's dictionary and settings, which live
        // in `~/Library/Application Support/WeType/` and never in the bundle.
        // Those are snapshotted alongside the bundle rollback point and restored
        // with it — see `InputMethodDataBackup`, including what it does not cover
        // (a user who has turned rollback points off gets no snapshot either).
        VendorProbeRecipe(
            bundleID: "com.tencent.inputmethod.wetype",
            url: URL(string: "https://z.weixin.qq.com/web/mac/download?channel=InstallInfo")!,
            mode: .responseBody,
            versionPattern: #""zip_version"\s*:\s*"[0-9]+(?:\.[0-9]+){2}\.([0-9]+)""#,
            downloadURL: URL(string: "https://z.weixin.qq.com/"),
            changelogURL: URL(string: "https://z.weixin.qq.com/web/change-log/macos"),
            versionIsBuild: true,
            displayVersionPattern: #""zip_version"\s*:\s*"([0-9]+(?:\.[0-9]+){2})\.[0-9]+""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""zip_download_url"\s*:\s*"(https://[^"]+\.zip)""#),
                kind: .zip)),

        // 搜狗输入法 (SogouInput) — Sogou's input method, installed from
        // `shurufa.sogou.com` / `pinyin.sogou.com` into `/Library/Input Methods`.
        //
        // Reads the vendor's OWN update endpoint — the one `SogouServices` calls,
        // captured off the wire (2026-08-28):
        //
        //   GET macime.sogou.com/macversion.txt?h=<md5>&v=<installed>&r=1111&sv=27.0&s=0
        //
        // It is a CONDITIONAL endpoint: "given this client's version, what should
        // it upgrade to". Ask it as an up-to-date client and it answers with a
        // sentinel — `version=1.0.0.1`, below every real build, which is how it
        // tells the client to stay put. Ask it as an old one and it names the
        // current release with a payload URL and an md5:
        //
        //   version=6.24.1.11676
        //   update_pack_url=…/autosetup6.24.1.11676_V10003_20260715_223833.zip
        //   update_pack_md5=654bd06d7df44e2237e0c61fab08477b
        //
        // So the probe pins `v` at `0.0.0.1` — below anything the vendor can ever
        // ship, so the request can never drift into sentinel territory. It does
        // NOT stage: measured at `6.23.0.0`, `6.16.1.0`, `2.0.0.26481`,
        // `1.5.1.21442`, `1.0.0.2` and `0.0.0.1`, every one is answered with the
        // same newest build rather than an intermediate hop, which is the property
        // that makes a pinned-old-version probe mean "latest".
        //
        // THE VERSION IS THE BUNDLE'S OWN. `6.24.1.11676` is exactly
        // `CFBundleShortVersionString`, four segments included — unlike the
        // changelog page, which publishes three and would have needed the
        // installed side trimmed to compare at all. Same namespace, no derivation,
        // and respins that change only the fourth segment are visible.
        //
        // PARAMETERS. Only `sv` is actually required — omit it and the answer
        // collapses to the sentinel. `v` and `s` are sent anyway, because what
        // they do is worth pinning rather than leaving to a default: `v` absent or
        // unparseable is treated as ancient (the pin states the intent instead of
        // relying on that), and `s` is read as an integer where 0 means "check for
        // an update" — `s=1`, `s=2`, `s=3`, `s=-1` all select a branch that
        // sentinels unconditionally.
        //
        // `r` (the installed copy's distribution channel) is omitted: the server
        // ignores it — absent, `r=1111` and `r=9999` answer identically — and a
        // channel code lifted from one machine's install would be stating
        // something untrue about every other. `h`, the per-device hash the real
        // client sends, is omitted for a stronger reason: a probe of ours has no
        // business carrying a machine identifier to a vendor. The binary also
        // builds requests carrying `r0` and `cpu` (an architecture selector);
        // `cpu` is inert today — `arm64`, `x86_64` and `intel` answer identically
        // — but it is what would decide which architecture we are told about if
        // Sogou ever split them.
        //
        // WARNING: `sv` DOES gate by OS. The first version of this comment said it
        // did not, from five values that all sat inside one bucket. Swept finely
        // there are three answers:
        //
        //     sv < 10.10             sentinel
        //     sv 10.10 – 10.13       6.14.1.9298   (frozen since June 2023)
        //     sv 10.14 – 27.6        6.24.1.11676  ← current
        //     sv 27.61 and above     6.14.1.9298   again
        //
        // So the pinned `27.0` IS choosing a build for an OS, and that upper edge
        // has a consequence for the vendor's own users: a Sogou client on macOS 28
        // asks with `sv=28.x`, is handed a 2023 build below its own install, and
        // quietly stops updating. Pinning a constant is what keeps OUR answer
        // right for every host regardless — sending the machine's real OS would
        // break detection on exactly those Macs.
        //
        // The residual risk is narrow, and it is this recipe's one quiet failure:
        // if Sogou splits the 10.14–27.6 bucket and ships a newer build only above
        // it, the pinned request keeps answering 6.24.1.11676 and nothing fails.
        // Most boundary moves are loud instead — a pin landing in the legacy
        // bucket reports 6.14.1.9298, below every real install, which the sweep
        // flags as `remote is BEHIND the installed copy`. The check for the quiet
        // case is the changelog page: at the next release it advances and so must
        // this.
        //
        // The pattern requires `update_pack_url` to FOLLOW the version, so the
        // sentinel response cannot be read as one. Without that guard a sentinel
        // would be reported as `1.0.0.1` — which reads as a colossal downgrade and
        // would at least be loud, but refusing it outright is better than being
        // loud about a number we know is not a version.
        //
        // And the span between them is `[^\[]*?`, not `[\s\S]*?`, so it cannot
        // cross a `[` — which is to say it cannot leave the block it started in.
        // The response is `[product0]` … `[end]`, with a `pid=0` inside: a shape
        // that plainly anticipates more than one product, even though no request
        // tried here produced one. An unbounded span over a sentinel block
        // followed by a real one pairs the FIRST block's `version=1.0.0.1` with
        // the SECOND block's payload URL and reports `1.0.0.1` as the release —
        // measured on exactly that concatenation. Not being able to make the
        // server emit two blocks is not evidence that it never will.
        //
        // `pid=0` is required ahead of the version for the same reason, one step
        // further: block-scoping stops us pairing two blocks' fields, but not
        // reading the FIRST block when that block is some other product. That
        // `pid` identifies the product is UNVERIFIED — it is `0` in both responses
        // ever seen, and no request produced a second block — but the guard fails
        // in the safe direction either way: a response this does not recognise
        // resolves no version at all, which is loud, rather than quietly reporting
        // a number belonging to something else.
        //
        // `changelogURL` stays on the update-log page: it is the only place the
        // release notes exist, and the two agree (`6.24.1`, 2026-07-17, matching
        // this bundle's own build date).
        //
        // DETECTION ONLY, and here that is not conservatism. Its `install.sh` does
        // rotate `Contents` on the already-installed branch, like WeType's and
        // DoubaoIme's updaters — but that rotation is `rm -rf` then `mv`, not an
        // atomic exchange, and around it the script lays down two
        // `/Library/LaunchAgents` plists it then boots out, bootstraps and
        // kickstarts, re-registers a QuickLook generator (`qlmanage -r`), MIGRATES
        // `~/Library/Input Methods/Sogou` into
        // `~/Library/Application Support/Sogou/InputMethod`, and ends with
        // `killall -9 SogouInput` and `killall -KILL SystemUIServer` — force-kills
        // this app does not perform on anybody. A Contents rotation leaves every
        // one of those undone.
        //
        // (An earlier version of this comment said the installer *installs* a
        // per-user LaunchAgent. It does the opposite: both scripts only `bootout`
        // and `rm -rf` `~/Library/LaunchAgents/com.sogou.SogouTaskManager.plist`,
        // and no such file exists on a machine with Sogou installed.) The self-update payload
        // above is a narrower shape again (a double zip carrying
        // `Contents<version>.zip` plus `pre.sh`/`post.sh`/`switch.sh`, whose
        // switch script has its own migration branches), so a one-click here needs
        // a Sogou-specific path, not the generic archive install.
        VendorProbeRecipe(
            bundleID: "com.sogou.inputmethod.sogou",
            url: URL(string: "https://macime.sogou.com/macversion.txt?v=0.0.0.1&sv=27.0&s=0")!,
            mode: .responseBody,
            versionPattern: #"\npid=0\n(?:[^\[]*?\n)?version=([0-9]+(?:\.[0-9]+)+)[^\[]*?\nupdate_pack_url="#,
            downloadURL: URL(string: "https://shurufa.sogou.com/mac"),
            changelogURL: URL(string: "https://pinyin.sogou.com/mac/update_log.php")),

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
        // ONE-CLICK, and it takes one more step than any other recipe because the
        // artifact here is not the app. The endpoint hands over
        // `DoubaoImeInstaller_v<code>_release.zip`, a ~190 MB stub whose
        // `Contents/Resources` holds `DoubaoIme.zip` (170 MB) plus the `install.sh`
        // it runs — so `nestedArchivePath` unwraps one level, and the whole gate
        // stack (signature, Team, bundle id, architecture) then runs on the real
        // `DoubaoIme.app`. Without the unwrap the bundle-id gate would refuse
        // `com.bytedance.inputmethod.doubaoime.installer`, correctly, and the
        // one-click could never work.
        //
        // The unwrap is a gate MOVED, not skipped: `Contents/Resources` is sealed
        // by the stub's own code signature (Team 96L78H6LMH, the same Team as the
        // installed app), and `VendorInstaller` verifies the stub before reading
        // the payload out of it.
        //
        // The install itself rotates `Contents` inside the registered
        // `DoubaoIme.app`, which is what DoubaoIme's own updater does
        // (`Contents_update` / `Contents_backup`), while `install.sh` is the
        // first-install path that removes the whole bundle. See
        // `InPlaceSwap.usesContentsRotation`. That script also ends with
        // `chown -R root:staff` + `chmod -R 775` — recursively — which is why the
        // swap carries the group-write bit all the way down and not just two
        // levels: their updater has to be able to delete the Contents it displaced.
        VendorProbeRecipe(
            bundleID: "com.bytedance.inputmethod.doubaoime",
            url: URL(string: "https://ime.doubao.com/api/v1/app/download_url?platform=macos")!,
            mode: .responseBody,
            versionPattern: #"DoubaoImeInstaller_v([0-9]+)_release\.zip"#,
            downloadURL: URL(string: "https://shurufa.doubao.com/"),
            versionIsBuild: true,
            displayVersionPattern: #""version_name"\s*:\s*"[Vv]?([0-9]+(?:\.[0-9]+)+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://[^"]+/DoubaoImeInstaller_v[0-9]+_release\.zip)""#),
                kind: .zip,
                nestedArchivePath: "Contents/Resources/DoubaoIme.zip")),

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

        // Grok Bot — xAI's product, but built and signed by Anysphere and riding
        // Cursor's release infrastructure, which is why it sits next to Cursor
        // rather than under x.ai: `com.anysphere.sand`, Team DCNK4UB866,
        // notarized, arm64-only, updates from `api2.cursor.sh`.
        //
        // The app is `sand` on that API — not `grok-bot`, not `grokbot`. The
        // endpoint says so itself: any other name 404s with "Invalid app name -
        // can only download stable for cursor or sand" (measured 2026-08-29).
        //
        // Single channel, and that is the vendor's position rather than an
        // assumption. The bundle's `appNameForTrack` maps three tracks
        // (stable → `sand`, nightly → `sand-nightly`, dogfood → `sand-dogfood`),
        // but the client coerces nightly back to stable and hides dogfood behind
        // an internal unlock, and the server 404s both of those app names for
        // every channel path. Only stable is reachable from a shipped build.
        //
        // Two other endpoints on the same API were rejected, both deliberately:
        //
        //   • The URL x.ai/bot's own download button uses,
        //     `/updates/download/stable/darwin-arm64/grok-bot-<token>`, 302s
        //     straight to the same dmg but publishes no version anywhere — it
        //     could only be probed by reading a filename.
        //   • `/updates/api/update/darwin-arm64/sand/<installed>/stable`, which
        //     the Homebrew cask's livecheck reads, is the app's own Squirrel feed
        //     and is CONDITIONAL: it answers `{"url":…,"name":"0.30.0"}` when a
        //     newer build exists and **204 with an empty body** when the caller is
        //     already current (measured 2026-08-29 at 0.0.0 and at 0.30.0). An
        //     empty body is also what a broken endpoint looks like, so probing it
        //     would mean teaching the sweep to read silence as good news.
        //
        // `/updates/api/download/…` answers unconditionally with the version as a
        // JSON field, which is why it is the one here. The version pattern is
        // quote-bounded on both sides, so the segment count is not the boundary
        // (the Zotero rule).
        //
        // One-click: same-Team as the installed copy, and the install pattern is
        // pinned to this app's own path prefix because `downloads.cursor.com`
        // also serves Cursor's own builds (`/production/`) and the x64/universal
        // variants of this one. Two prefixes, because the vendor publishes the
        // same artifact under both: the API answers `/grokbot/…`, while the
        // Homebrew cask's url template builds `/sand/…` — measured 2026-08-29,
        // both 200 with `application/x-apple-diskimage`. If it ever moves to a
        // third the pattern stops matching and the one-click quietly goes away,
        // which is the direction this should fail.
        // `.dmg` and not `.pkg`: Electron with Squirrel.framework, and everything
        // it ships lives inside the bundle (`Contents/Frameworks`,
        // `Contents/Helpers`) — no daemon, no launch agent, nothing under
        // /Library (checked 2026-08-29).
        //
        // No `changelogURL`, and not an oversight: xAI publishes no release notes
        // for this desktop app. The only "changelog" x.ai links is
        // `x.ai/api/changelog`, which is the developer console's, on an unrelated
        // subject and version scheme (checked 2026-08-29).
        VendorProbeRecipe(
            bundleID: "com.anysphere.sand",
            url: URL(string: "https://api2.cursor.sh/updates/api/download/stable/darwin-arm64/sand")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://x.ai/bot"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""downloadUrl"\s*:\s*"(https://downloads\.cursor\.com/(?:grokbot|sand)/stable/darwin-arm64/[^"]+\.dmg)""#),
                kind: .dmg)),

        // Raycast keeps TWO trains open, and which one a Mac belongs to is decided
        // by the machine, not by a user preference — so both are stable-channel
        // recipes separated by `hostRequirement`, not by `channel`.
        //
        //   v1 (this recipe): `releases.raycast.com`, universal, still shipping
        //      (1.104.25 on 2026-08-18). This is the train for every Mac that
        //      cannot run v2.
        //   v2 (below): `x.raycast-releases.com`, arm64-only, macOS 26+.
        //
        // Neither endpoint gates: both answer any client the same way regardless
        // of the UA's OS/architecture (measured 2026-08-27 across Intel/Sequoia/
        // browser agents), which is precisely why the split is recorded in the
        // recipes. `best(of:)` then takes the higher version among whichever
        // recipes this Mac is eligible for — v2 on Apple silicon + Tahoe, v1
        // everywhere else.

        // Raycast v1 — official "latest release" endpoint; `version` is first.
        // Carries an explicit `variant` for the same reason v2 does: a duplicated
        // (bundleID, channel) group must declare every member deliberately. Its
        // verify baseline entry was renamed with it (`…:stable` → `…:stable:v1`)
        // rather than left to start over.
        // One-click: the same JSON's `downloadURL` is the dmg (a
        // worker.raycast-releases.com proxy URL wrapping a presigned R2 object;
        // resolved fresh from each probe so its signed expiry is never stale).
        VendorProbeRecipe(
            bundleID: "com.raycast.macos",
            url: URL(string: "https://releases.raycast.com/releases/latest?build=universal")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.raycast.com/"),
            // /changelog now serves the V2 notes; the v1 archive moved to
            // /changelog/macos ("Raycast - macOS V1 Changelog"). This is the page
            // a v1 user's notes actually live on, so it is the one linked here.
            changelogURL: URL(string: "https://www.raycast.com/changelog/macos"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""downloadURL"\s*:\s*"(https://[^"]+)""#),
                kind: .dmg),
            variant: "v1"),

        // Raycast v2 — the endpoint the v2 app's own updater calls. Requirements
        // are macOS Tahoe + Apple silicon (https://www.raycast.com/new), and the
        // macOS half of `builds` carries exactly one entry, `macos/arm64`; hence
        // the `hostRequirement`. On a Mac that fails it this recipe is dropped
        // before the merge and the v1 recipe above answers instead.
        //
        // `version` is DELIBERATELY absent from the query. The endpoint is a
        // "should I update?" call, not a "what is latest?" one: given the caller's
        // version it answers **204 No Content** when that version is already
        // current (which is what a packet capture of the running app shows, and
        // what would make this probe fail exactly when it should say "up to
        // date"). Omitting the parameter returns 200 + the newest release
        // unconditionally. Passing a v1-shaped 3-segment version is not an option
        // either — the parameter validates as 4 segments and 400s below that.
        //
        // Shape: {"id":…,"version":"2.0.6.0","title":…,"changelog":…,
        //   "commit_sha":…,"created_at":"2026-08-25T07:34:17.976Z","updated_at":…,
        //   "builds":[{…,"url":…}],"download_url":"https://x-r2.…arm64.dmg",
        //   "checksum":"<md5>"}
        // `version` is the marketing string the installed bundle reports verbatim
        // (2.0.6.0 == CFBundleShortVersionString, verified on this machine), so no
        // `versionIsBuild`. The install URL is the top-level `download_url` — a
        // plain, unsigned R2 object, unlike v1's presigned link — and the `.dmg`
        // suffix in the pattern keeps it off the Windows `.msix` builds listed in
        // `builds`. `checksum` is an MD5 hex digest, which `checksumPattern`
        // (SHA-512, base64) cannot consume, so it is left unused; Team SY64MV22J9
        // gates the swap.
        VendorProbeRecipe(
            bundleID: "com.raycast.macos",
            url: URL(string: "https://x.raycast-releases.com/releases/latest?platform=macos&architecture=arm64")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.raycast.com/"),
            changelogURL: URL(string: "https://www.raycast.com/changelog"),
            publishedAtPattern: #""created_at"\s*:\s*"([0-9T:.\-]+Z?)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""download_url"\s*:\s*"(https://[^"]+\.dmg)""#),
                kind: .dmg),
            variant: "v2",
            hostRequirement: VendorHostRequirement(
                minimumSystemVersion: "26.0", architectures: [.arm64])),

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
        //
        // If a nightly-channel variant of this recipe is ever added: no `install:`
        // — nightly is ad-hoc signed, no Team ID (docs/app-audits/org-videolan-vlc.md, #95).
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
        //  See `InstalledApp.prefersVendorProbeOverToolbox`.)
        //
        // NOT newest-first (see issue #76): the feed is ordered by PUBLICATION
        // DATE, not by version. With two feature trains open at once, a newer
        // train's Canary can publish AFTER an older train's RC — 2026-08-27 had
        // `2026.1.4 RC 2` at item [0] and `2026.2.1 Canary 2`, the actually-newer
        // build, at item [1] — so plain first-match on the channel set landed on
        // the older train's RC. `entryStartPattern` slices the feed into its
        // `{"date":…}` items and makes `versionPattern`/`displayVersionPattern`/
        // the install URL all resolve against the ONE entry whose build compares
        // highest, instead of three separate first-matches over the whole feed
        // that could each land on a different entry (flipping `selectHighest` on
        // `versionPattern` alone would have done exactly that — see its doc).
        // dmg patterns mirror each channel set. Suppression is conditional, not a
        // property of this recipe: `VendorProbeSource` sets `allowInstall` from
        // `InstalledApp.prefersVendorProbeOverToolbox`, which is true only for a
        // Toolbox-MANAGED Canary/Beta — that copy stays detection-only and updates
        // through Toolbox. A HAND-INSTALLED Canary/Beta (`isToolboxManaged ==
        // false`) gets `allowInstall = true` and IS offered this one-click, which is
        // why the dmg patterns below must stay correct and in lockstep with the
        // version set, not merely decorative. Team EQHXZ8M8AV.
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
            // Each item starts with its own `"date"` key — see `entryStartPattern`.
            entryStartPattern: #"\{"date":""#,
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
            // Each item starts with its own `"date"` key — see `entryStartPattern`.
            entryStartPattern: #"\{"date":""#,
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
        // mounted app. com.electron.wispr-flow, Team C9VQZ78H85, notarized; no
        // SUFeedURL.
        //
        // ONE-CLICK via `.versionTemplate`, and the choice is forced rather than
        // preferred. The feed's 26 entries each carry their own `url`, but the
        // version is printed BEFORE the url inside every entry, and
        // `.bodyPatternHighestVersioned` requires capture group 1 to be the url and
        // group 2 the version — an order a single left-to-right regex cannot
        // produce here. The remaining body options are both ordering bets on an
        // ascending feed. `.versionTemplate` sidesteps the question: the string
        // that was compared is the string that gets downloaded.
        //
        // An earlier note here said the feed was architecture-specific and that a
        // one-click risked a cross-architecture swap. The endpoint is arm64's
        // (`/darwin/arm64/`) — it is the *probe* URL that already pins the
        // architecture, so there was never a choice to make. This app is arm64-only
        // (`App/project.yml`), so no host can ask for the Intel train.
        //
        // THE TEMPLATE DELIBERATELY DOES NOT USE THE FEED'S OWN `url`. Every entry
        // in this stable feed — all 26 — points at a `wispr-flow-beta/…` path.
        // Following it works (the artifact there is a normal notarized stable
        // build; 1.6.721 downloaded and extracted 2026-08-29:
        // `com.electron.wispr-flow`, CFBundleShortVersionString 1.6.721,
        // `Developer ID Application: Wispr AI INC (C9VQZ78H85)`, spctl "accepted /
        // Notarized Developer ID", stapled), but it makes every nightly `duo
        // verify` raise "stable recipe resolved what looks like a PRE-RELEASE
        // artifact" — a standing false positive on the one sweep whose job is to
        // be believed, and one `duo reconcile` would file as an issue.
        //
        // The same object is served from the stable path this recipe already
        // probes, `wispr-flow/darwin/arm64/`: verified 2026-08-29 by fetching both
        // and comparing — identical size (331,807,594 B) and identical SHA-256
        // (0217292d…d6a31), so the `-beta` bucket is an alias, not another build.
        // Templating the stable path is therefore the honest URL rather than a
        // suppressed warning.
        //
        // No checksum: the feed publishes none for any entry — the signature and
        // Team gates are the integrity check.
        VendorProbeRecipe(
            bundleID: "com.electron.wispr-flow",
            url: URL(string: "https://dl.wisprflow.com/wispr-flow/darwin/arm64/RELEASES.json")!,
            mode: .responseBody,
            versionPattern: #"\"currentRelease\"\s*:\s*\"([0-9]+(?:\.[0-9]+)+)\""#,
            downloadURL: URL(string: "https://wisprflow.ai/downloads"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://dl.wisprflow.com/wispr-flow/darwin/arm64/"
                    + "Wispr%20Flow-darwin-arm64-{version}.zip"),
                kind: .zip)),

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
        // redirects disabled. ai.perplexity.comet, Team 7S8W4W365S, notarized;
        // Keystone updater, no Sparkle feed.
        //
        // ONE-CLICK via `.fixed` ON THE GATEWAY ITSELF — deliberately not on the
        // signed URL the probe just resolved, and deliberately not `.redirect`.
        //
        // `.redirect` is out because it HEADs, and this vendor's HEAD answers
        // `Location: https://www.example.com?status=ok` (measured 2026-08-29; GET
        // on the same URL returns the artifact).
        //
        // Templating the resolved signed URL would "work" and then rot: every
        // install URL is resolved at CHECK time and stored on the row until the
        // user clicks, while this signature carries `X-Amz-Expires=3600`. A row
        // checked more than an hour before the click — the default on any
        // frequency slower than hourly — would 403. Handing the download the
        // gateway instead moves the redirect to download time, where `Downloader`
        // GETs and follows it like a browser, so the signature is always minutes
        // old. That is also why the ephemeral URL never has to be re-resolved:
        // nothing durable ever holds one.
        //
        // ONE CONSTANT for both halves, not two copies of the same string. The
        // probe and the download MUST be the same endpoint — that is the entire
        // design — and two literals drift silently in the one direction every gate
        // would wave through: retarget the probe to `channel=beta` and the install
        // still fetches stable, both Perplexity-signed builds of the same bundle
        // id, so the user is offered a beta and handed a stable.
        //
        // No checksum, because the gateway publishes none — so unlike Msty there
        // is nothing here that notices when the build fetched is not the build
        // compared. The gateway always serves current: a row checked at
        // 151.0.7922.247 and clicked after 152.x ships installs 152.x and records
        // 151.0.7922.247 until the next check corrects it. That is bookkeeping
        // drift, not a broken app, and it is the same property every `.redirect`
        // recipe already has; it is written down because the version and the
        // artifact come from one document at PROBE time and from two moments at
        // install time.
        //
        // Verified 2026-08-29 by fetching
        // the gateway with redirects followed — 313,170,645 B, and the dmg mounts
        // as "Comet Installer" carrying a real 710 MB `Comet.app` (not a
        // downloader stub like 1Password's): `ai.perplexity.comet` 151.0.7922.247,
        // `Developer ID Application: Perplexity AI Inc. (7S8W4W365S)`, spctl
        // "accepted / Notarized Developer ID", universal (x86_64 + arm64).
        VendorProbeRecipe(
            bundleID: "ai.perplexity.comet",
            url: Self.cometStableGateway,
            mode: .redirectFilename,
            versionPattern: #"/([0-9]+(?:\.[0-9]+)+)/comet_latest\.dmg"#,
            downloadURL: URL(string: "https://www.perplexity.ai/comet"),
            install: VendorInstallSpec(urlSource: .fixed(Self.cometStableGateway), kind: .dmg),
            followRedirects: false),

        // Devin Desktop (formerly Windsurf) — official stable update JSON. The
        // `windsurfVersion` field is the app's own marketing/build version;
        // `productVersion` is the upstream VS Code base and must never be parsed.
        // com.exafunction.windsurf, Team 83Z2LHX6XW, notarized.
        //
        // ONE-CLICK via `.bodyPattern`: the same response carries the finished
        // installer link (`"url": "…/Devin-darwin-arm64-<version>.dmg"`), so the
        // url and the version come out of one document — nothing to template and
        // nothing to order. The pattern requires the `.dmg` suffix so it cannot
        // drift onto some other absolute URL if the vendor adds a field.
        //
        // An earlier note here called detection "architecture-neutral" and omitted
        // one-click on that basis. It is not: the probe URL is
        // `/api/update/darwin-arm64-dmg/…` and the response's own `displayName` is
        // "macOS for Apple Silicon (.dmg)". The endpoint already picks the
        // architecture; there is no second choice for an install spec to make, and
        // this app is arm64-only anyway (`App/project.yml`).
        //
        // No checksum: the response's `sha256hash` is SHA-256 hex, and
        // `checksumPattern` verifies base64 SHA-512. Wiring the wrong digest would
        // fail every install; the signature and Team gates carry the integrity.
        //
        // Verified 2026-08-29 on the real artifact this pattern selects (3.8.20):
        // mounted, `com.exafunction.windsurf`, `Developer ID Application:
        // EXAFUNCTION, INC. (83Z2LHX6XW)`, spctl "accepted / Notarized Developer
        // ID", stapled, `lipo -archs` = arm64.
        VendorProbeRecipe(
            bundleID: "com.exafunction.windsurf",
            url: URL(string: "https://windsurf-stable.codeium.com/api/update/darwin-arm64-dmg/stable/latest")!,
            mode: .responseBody,
            versionPattern: #"\"windsurfVersion\"\s*:\s*\"([0-9]+(?:\.[0-9]+)+)\""#,
            downloadURL: URL(string: "https://devin.ai/desktop"),
            changelogURL: URL(string: "https://windsurf.com/editor/releases/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"\"url\"\s*:\s*\"(https://[^\"]+\.dmg)\""#),
                kind: .dmg)),

        // AionUi — official electron-builder arm64 manifest. `version` matches the
        // mounted app exactly. com.aionui.app, Team 52JQX2HUSC, notarized.
        //
        // ONE-CLICK via `.versionTemplate`, and NOT via `.bodyPatternRelative`,
        // which is what an electron-builder manifest normally invites. The
        // manifest's `path`/`url` entries are bare filenames, but they do NOT
        // resolve against the manifest's own directory: measured 2026-08-29,
        // `…/releases/AionUi-2.1.61-mac-arm64.zip` answers 403 AccessDenied while
        // `…/releases/2.1.61/AionUi-2.1.61-mac-arm64.zip` answers 200. The real
        // layout inserts the version as a directory, so the relative case would
        // have produced a link that never downloads.
        //
        // The manifest this probe reads is the arm64 one; Intel has a separate
        // manifest and artifact that no host of ours can ask for (arm64-only, see
        // `App/project.yml`), so the template pins arm64 the way the rest of the
        // registry does rather than waiting for host-architecture selection.
        //
        // The checksum comes from the manifest's TOP-LEVEL `sha512`, anchored at
        // column 0 so it cannot match the indented per-file digests under `files:`
        // — those list the dmg as well, and the first of them is only the zip's by
        // accident of ordering. The top-level digest is by definition the one for
        // `path:`, which is the zip this template builds. Verified 2026-08-29:
        // `openssl dgst -sha512 -binary` of the downloaded zip reproduces the
        // manifest value exactly. Extracted: `com.aionui.app`, 2.1.61, `Developer
        // ID Application: AionUi Inc. (52JQX2HUSC)`, spctl "accepted / Notarized
        // Developer ID", stapled, `lipo -archs` = arm64.
        VendorProbeRecipe(
            bundleID: "com.aionui.app",
            url: URL(string: "https://static.aionui.com/releases/latest-arm64-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*v?([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://www.aionui.com/"),
            changelogURL: URL(string: "https://github.com/iOfficeAI/AionUi/releases"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://static.aionui.com/releases/{version}/"
                    + "AionUi-{version}-mac-arm64.zip"),
                kind: .zip,
                checksumPattern: #"(?m)^sha512:\s*(\S+)\s*$"#)),

        // Msty Studio — official electron-builder manifest lists both x64 and
        // arm64 assets and reports the same version as Info.plist. MstyStudio,
        // Team S6CF5A8MX9, notarized.
        //
        // ONE-CLICK via `.fixed`: this vendor's filenames carry no version
        // (`MstyStudio_arm64.zip`), so the artifact URL is a constant and there is
        // nothing to template. The manifest that names the version sits in the
        // same directory, so the two always describe one release.
        //
        // THE CHECKSUM PATTERN IS ANCHORED ON THE arm64 FILENAME, and that anchor
        // is the whole reason this recipe was blocked. `checksumPattern` is a
        // separate first-match over the body, and this manifest lists four
        // artifacts — `MstyStudio_x64.zip` FIRST, then arm64, then both dmgs — so
        // the obvious `^\s+sha512:` would hand the x64 digest to an arm64
        // download and fail every install. Requiring `url: MstyStudio_arm64.zip`
        // immediately before the digest makes the pairing structural rather than
        // positional: measured 2026-08-29, the naive pattern yields `2Ix1WRcS…`
        // (x64) and this one `aNSie9nH…` (arm64), and the downloaded
        // `MstyStudio_arm64.zip` hashes to exactly the latter.
        //
        // The checksum earns its place twice over here. Because the URL is a
        // "latest" path while the digest belongs to the version the probe
        // compared, a release published between the check and the click fails the
        // checksum instead of silently installing a version nobody compared —
        // loud, and cleared by re-checking. Without it this recipe could report
        // one version and install another.
        //
        // That second job is BEST-EFFORT, and the limit belongs here rather than
        // in a reader's assumption: a checksum is optional at install time
        // (`VendorInstaller` gates it behind `if let expected`), so if this
        // pattern ever stops matching — the vendor reorders the keys inside an
        // entry, or renames the asset — the install proceeds unverified and the
        // "latest" URL is once again free to be a version nobody compared. Only
        // the nightly sweep notices, through `checksumPatternNoMatch`, after the
        // fact. Making it fatal instead was considered and refused: a vendor
        // reformat would turn "installed a slightly newer build" into "one-click
        // is dead", which is the worse of the two failures.
        //
        // Verified 2026-08-29 on the artifact this spec selects: 248,234,928 B,
        // extracts to `MstyStudio.app` 2.9.8, `Developer ID Application: Ashok
        // Gelal (S6CF5A8MX9)`, spctl "accepted / Notarized Developer ID",
        // `lipo -archs` = arm64.
        VendorProbeRecipe(
            bundleID: "MstyStudio",
            url: URL(string: "https://next-assets.msty.studio/app/latest/mac/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*v?([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://msty.ai/"),
            changelogURL: URL(string: "https://msty.ai/resources/changelog/studio/"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://next-assets.msty.studio/app/latest/mac/"
                        + "MstyStudio_arm64.zip")!),
                kind: .zip,
                checksumPattern: #"url:\s*MstyStudio_arm64\.zip\s*\n\s*sha512:\s*(\S+)"#)),

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
            // `termius.com/release-notes` 404s (checked 2026-08-27). The live
            // page is on the docs host; `termius.com/changelog` redirects here,
            // so point at the destination rather than depend on the redirect.
            changelogURL: URL(string: "https://docs.termius.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://autoupdate.termius.com/mac-arm64/Termius.dmg")!),
                kind: .dmg)),

        // Termius Beta — a genuinely independent bundle id from stable's
        // `com.termius-dmg.mac` (issue #91), so no cross-channel risk and
        // `ReleaseChannel.detect()` needs no new rule: `CFBundleName`/
        // `CFBundleDisplayName` is "Termius Beta", which its existing
        // standalone-word `channelWord` step already resolves to `.beta`.
        //
        // Same electron-builder feed shape as stable, on the SAME
        // autoupdate.termius.com host stable already probes, just under the
        // mac-beta-universal path — found by reading the vendor's own Homebrew
        // cask (`Casks/t/termius.rb`), whose `livecheck` block points
        // electron_builder-strategy readers at
        // `https://autoupdate.termius.com/mac/latest-mac.yml` (stable's
        // un-suffixed, Intel-only sibling of the arm64 feed above) — that is
        // what led here, since the app's own bundled `app-update.yml` names an
        // `acl: private` S3 bucket that a plain GET can't read (403, verified).
        //
        // Verified 2026-08-27 by downloading and mounting the real dmg:
        // com.termius-beta.mac, 9.43.1, Team 6KN952WR85, Notarized Developer
        // ID, not sandboxed — same Team as stable, so `VendorInstaller`'s Team
        // gate holds. Unlike the arm64-only stable recipe above, this feed's
        // dmg is confirmed UNIVERSAL (`lipo -info` on the downloaded artifact:
        // x86_64 arm64), so one recipe correctly serves every Mac with no
        // `hostRequirement` needed.
        //
        // checksumPattern is safe here — unlike Signal Beta, whose CDN staples
        // the dmg AFTER electron-builder computed the feed's sha512 (see the
        // comment on Signal's recipe above), Termius Beta's declared
        // `sha512` for "Termius Beta.dmg" was independently verified
        // 2026-08-27 to equal `shasum -a 512 | base64` of the downloaded file,
        // byte for byte.
        //
        // No changelogURL: `https://termius.com/release-notes` (stable's own
        // changelogURL, above) 404s as of 2026-08-27 and no replacement page
        // exists in the vendor's sitemap — flagged separately, not fixed here.
        VendorProbeRecipe(
            bundleID: "com.termius-beta.mac",
            url: URL(string: "https://autoupdate.termius.com/mac-beta-universal/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://termius.com/beta-program"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://autoupdate.termius.com/mac-beta-universal/Termius%20Beta.dmg")!),
                kind: .dmg,
                checksumPattern: #"Termius Beta\.dmg\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#),
            channel: .beta),

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

        // MARK: - 2026-08-27 WorkBuddy (Tencent)

        // WorkBuddy ships as TWO separate apps, not two channels of one. Tencent
        // runs an international site and a China site, each with its own bundle
        // id, its own app name, its own update host and its own release train:
        //
        //   com.workbuddy.workbuddy-ai  "WorkBuddy AI.app"  www.workbuddy.ai  5.4.2
        //   com.workbuddy.workbuddy     "WorkBuddy.app"     www.workbuddy.cn  5.3.14
        //
        // Both are Electron, both signed by Team FN2V63AD2J (Tencent Technology
        // (Shanghai) Company Limited), and the two builds carry byte-identical
        // updater code — so the ONLY thing that routes an install to its own train
        // is the bundle id, which is exactly the key a recipe is looked up by.
        // Nothing here is a `channel`: both trains are stable, and neither app can
        // ever be handed the other's artifact.
        //
        // The endpoint is the one the app's own `AbstractUpdateService` calls:
        // `<base>/v2/update?platform=workbuddy-{os}-{arch}&version=<installed>`,
        // where `<base>` is the product's API endpoint and defaults to
        // `copilot.tencent.com` (which answers identically to www.workbuddy.cn).
        // No auth: the `x-user-id` / `x-tenant-id` parameters the app appends are
        // optional and we send neither.
        //
        // TRAP, and the reason `version=0.0.0` is pinned into the URL: this is a
        // "should I update?" service, not a "what is the latest?" one. Passing the
        // version you already run returns **204 No Content** (measured 2026-08-27:
        // 5.3.14 → 204 on the CN host, 5.4.2 → 204 on the intl host), which would
        // make the probe go dark precisely when it should say "up to date". An
        // impossibly old version is what turns it into a latest-version query.
        //
        // TRAP, version scheme: the endpoint reports a FOUR-segment string
        // ("5.4.2.36857725") whose last segment is a build counter that appears
        // NOWHERE in the installed bundle — both `CFBundleShortVersionString` and
        // `CFBundleVersion` are the bare "5.4.2". Comparing the raw field would
        // read 36857725 > (nothing) forever, the permanent phantom update
        // `versionIsBuild` exists to prevent — but `versionIsBuild` is the wrong
        // fix here, since the build counter is not the app's CFBundleVersion
        // either. So capture group 1 takes only the first three segments and the
        // fourth is matched-and-discarded. Consequence to accept knowingly: a
        // vendor respin that bumps ONLY the build counter is invisible to us.
        // The optional fourth segment keeps the pattern matching if the vendor
        // ever drops back to a plain three-part version.
        //
        // Architecture: the endpoint serves both Macs and currently answers the
        // same version to each, but the `url` it hands back is arch-specific
        // (`/darwin-arm64/…` vs `/darwin-x64/…`). One recipe reading the arm64
        // endpoint would therefore offer an Intel Mac a zip it cannot run. Hence
        // one recipe per architecture, split by `hostRequirement` rather than by
        // channel (the Raycast v1/v2 shape) so exactly one is eligible on any
        // given Mac, and the install pattern is additionally pinned to its own
        // `darwin-<arch>` path so a recipe cannot resolve the other arch's
        // artifact even if the endpoint were to start ignoring the query.
        //
        // Sites: the two recipes are one helper apart, and BOTH CDN paths are
        // `/workbuddy/saas/darwin-<arch>/`, so the path alone does not say which
        // site an artifact came from. Each recipe therefore pins its own download
        // host as well. Without that, a later edit that swaps a host — or a vendor
        // that points one site's `/v2/update` at the other site's CDN — would have
        // one-click quietly replace a WorkBuddy AI install with the China build,
        // and nothing downstream could see it: same vendor, same Team, a real
        // notarized bundle, so the signature gate passes, and `ChannelProofRegistry`
        // does not apply because both recipes are `.stable`. Pinned, the same
        // situation degrades loudly instead (`installURLUnresolved`, which the
        // nightly `duo verify` sweep reports).
        //
        // One-click: the JSON's `url` is a plain, unsigned object on Tencent COS
        // (intl: `codebuddy-1328495429.cos.accelerate.myqcloud.com`; CN:
        // `download.codebuddy.cn`). The `sha256hash` field alongside it is a
        // SHA-256 hex digest, which `checksumPattern` (SHA-512, base64) cannot
        // consume, so it is left unused and Team FN2V63AD2J gates the swap.
        // Verified 2026-08-27 against both vendor DMGs at the same paths: the
        // `.dmg` sibling of each `.zip` matches the published installer byte
        // count, and both bundles are Developer ID signed under FN2V63AD2J.
        //
        // Changelog: each site's page is the one the app itself links (the build
        // branches on `isOverseas()`); the intl page ran behind its own train at
        // the time of writing (newest entry 5.2.7 against a 5.4.2 release) while
        // the CN page was current.
        workBuddyRecipe(
            bundleID: "com.workbuddy.workbuddy-ai", host: "www.workbuddy.ai",
            assetHost: "codebuddy-1328495429.cos.accelerate.myqcloud.com", arch: .arm64,
            downloadURL: URL(string: "https://www.workbuddy.ai/")!,
            changelogURL: URL(string: "https://www.workbuddy.ai/docs/workbuddy/Changelog")!),
        workBuddyRecipe(
            bundleID: "com.workbuddy.workbuddy-ai", host: "www.workbuddy.ai",
            assetHost: "codebuddy-1328495429.cos.accelerate.myqcloud.com", arch: .x86_64,
            downloadURL: URL(string: "https://www.workbuddy.ai/")!,
            changelogURL: URL(string: "https://www.workbuddy.ai/docs/workbuddy/Changelog")!),
        workBuddyRecipe(
            bundleID: "com.workbuddy.workbuddy", host: "www.workbuddy.cn",
            assetHost: "download.codebuddy.cn", arch: .arm64,
            downloadURL: URL(string: "https://www.workbuddy.cn/")!,
            changelogURL: URL(string: "https://www.codebuddy.cn/docs/workbuddy/Changelog")!),
        workBuddyRecipe(
            bundleID: "com.workbuddy.workbuddy", host: "www.workbuddy.cn",
            assetHost: "download.codebuddy.cn", arch: .x86_64,
            downloadURL: URL(string: "https://www.workbuddy.cn/")!,
            changelogURL: URL(string: "https://www.codebuddy.cn/docs/workbuddy/Changelog")!),

        // Canva — an Electron shell (`NSPrincipalClass` AtomApplication,
        // Squirrel.framework) that self-updates through electron-updater. The feed
        // is not a guess: the bundle's own `Contents/Resources/app-update.yml` names
        // `provider: generic` at `https://desktop-release.canva.com`, and the
        // Homebrew cask's `livecheck` reads that host's `latest-mac.yml` with
        // `strategy :electron_builder`. The cask itself is `auto_updates true`, so
        // `HomebrewCaskSource` declines it by design — and it was a release behind
        // (1.123.1 against 1.124.0) when this was written. No `SUFeedURL`, no GitHub
        // repo, and the iTunes lookup for this bundle id returns 0 results, so the
        // probe is the only surface that answers at all.
        //
        // The two sides compare like-for-like: the feed's `version` is `1.124.0` and
        // the shipped bundle's `CFBundleShortVersionString` is `1.124.0`. Its
        // `CFBundleVersion` is an unrelated `3597652.392500792` that appears nowhere
        // in the feed, which is why this is NOT `versionIsBuild`.
        //
        // Every pattern here ends at a run of digits and dots, and that is the
        // load-bearing detail. `beta-mac.yml` exists on the same host and answers
        // 200, but it is abandoned — `1.98.0-beta`, released 2024-11-12, against a
        // stable 1.124.0 from 2026-08-25 — so no beta recipe is registered and no
        // beta bundle id exists to carry one. The version pattern's trailing
        // `\s*$` is what makes that safe in the other direction too: publish a
        // `-beta` into the STABLE feed and the pattern matches NOTHING, so the app
        // degrades to "unknown" rather than capturing `1.98.0`, reporting a
        // prerelease as stable, and reading as a permanent downgrade against an
        // installed 1.124.0. The artifact pattern is pinned the same way, so an
        // install can never resolve `Canva-1.98.0-beta-universal.dmg`.
        //
        // One-click: the dmg holds `Canva.app` and nothing else — no pkg, no
        // LaunchDaemon, no helper outside the bundle — so the bundle swap is the
        // whole update. (The cask's `zap` names a
        // `com.canva.availability-check-agent` LaunchAgent, the one thing that could
        // have argued for `.pkg`; it is in neither the dmg nor a machine that has
        // run Canva, so whatever writes it, the installer does not.) Verified
        // 2026-08-27 on the real `Canva-1.124.0-universal.dmg`:
        // com.canva.CanvaDesktop, 1.124.0, Team 5HD2ARTBFS, `spctl` "Notarized
        // Developer ID". Unlike Signal, whose feed hash predates its own stapling,
        // Canva's published base64 sha512 matches the served bytes exactly, so the
        // checksum gate is armed on top of the mandatory Team-ID one.
        //
        // The download host needs no `requestHeaders`, and that is measured rather
        // than assumed — it is the failure class that resolves fine and then dies at
        // download time, which is why AweSun carries a Referer and SourceForge a
        // deliberately non-browser UA. `desktop-release.canva.com` answers the
        // downloader's own `DuoUpdater/0.1` with 206 and honours a mid-file Range,
        // so both the plain fetch and the resume path work unadorned.
        //
        // No `changelogURL`, deliberately: Canva publishes no desktop release notes.
        // The changelogs on canva.dev belong to the Apps SDK and Connect APIs and
        // describe a different product, and www.canva.com answers a Cloudflare
        // interactive challenge, so nothing there could be confirmed to be a notes
        // page. `downloadURL` therefore points at the plain download page, which
        // does answer (200), rather than at the yml.
        VendorProbeRecipe(
            bundleID: "com.canva.CanvaDesktop",
            url: URL(string: "https://desktop-release.canva.com/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://www.canva.com/download/"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Canva-[0-9][0-9.]*-universal\.dmg)"#,
                    base: URL(string: "https://desktop-release.canva.com/")!),
                kind: .dmg,
                checksumPattern:
                    #"Canva-[0-9][0-9.]*-universal\.dmg\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#)),

        // MARK: - 2026-08-27 CapCut (ByteDance)

        // CapCut has no appcast. It embeds Sparkle.framework — and `MacUpdater`
        // inside `libVECreator.dylib` does drive `SUAppcastItem` — but the bundle
        // carries NO `SUFeedURL`, and the decision of *what* to install is made
        // before Sparkle sees it: `UpdateController` reads a block of
        // `update_reminder.*` keys out of ByteDance's Settings SDK blob and
        // synthesizes the item from them. There is no iTunes entry, no GitHub
        // repo, and the vendor's own download page hands out a 3.6 MB
        // `CapCut-Downloader.app` stub rather than a versioned artifact, so this
        // endpoint is the only surface that answers at all.
        //
        // The endpoint is the Settings SDK's own, reconstructed from the shipped
        // binaries rather than guessed: `libSettings.dylib`'s `SettingsRequest.cpp`
        // spells the query (`?device_platform=&channel=&aid=&version_code=…`),
        // `libVECreator.dylib` carries the app id (`359289`), and CapCut's
        // `~/Movies/CapCut/User Data/Config/channel` carries the channel token
        // (`tea_channel=capcutpc_0`). It needs no device id, no install id and no
        // mssdk signature — a plain anonymous GET answers.
        //
        // Two-witness check on the answer, because a per-device rollout endpoint is
        // exactly where an anonymous probe could quietly get a different world than
        // the app does: the `lastest_*` fields in this anonymous response are
        // byte-identical to the ones in the copy CapCut itself cached for this
        // machine (`~/Movies/CapCut/User Data/MMKV/settings_json`, 2026-08-27).
        // What does NOT agree is `update_version`/`update_url` — the vendor's
        // per-device PICK, which was the stable 9.3.0 dmg in CapCut's own cache and
        // the beta 9.4.0-beta4 dmg in the anonymous response. So these recipes read
        // the track fields and never the pick; see `CapCutChannel` for what that
        // divergence means for a user.
        //
        // TRAP, `version_code`: it is required (dropping it, or sending a value the
        // vendor can't parse, removes `update_reminder` from the response entirely)
        // AND it selects a rollout bucket. Measured 2026-08-27, all other
        // parameters held fixed:
        //     0.0.1 · 8.0.0 · 9.0.0 · 9.3.0 · 9.4.0 · 9.5.0 · 9.9 · 9.99 → beta 9.4.0-beta4
        //     1.0.0 · 2.0.0 · 5.9.0                                      → beta 9.3.5-beta1
        //     9 · 10.0.0 · 99.9.9 · 9.999.999 · (absent) · "x"           → no update_reminder
        // The stable field was 9.3.0 for every value that answered at all, so only
        // the beta recipe is exposed to this. `9.99` is pinned for both because it
        // sits above every 9.x build the vendor has published — so it stays in the
        // newest bucket rather than ageing into the legacy one, which is the only
        // failure here that would be SILENT. Falling out of the window instead
        // (when CapCut reaches 10.x, or if the vendor narrows the range) removes
        // the key and the pattern matches nothing, which `duo verify` reports.
        // Same "pin an impossible version to turn a should-I-update service into a
        // what-is-latest one" move as WorkBuddy's `version=0.0.0` above, aimed the
        // other way because CapCut's buckets run the other way.
        //
        // What pinning `version_code` COSTS, stated because it is not obvious:
        // CapCut has a working binary-patch path (`UpdatingModel::startRunUpdateDiffPatch`,
        // an `update.delta` alongside `update.dmg`, per-release `cfg.diff_url` /
        // `cfg.diff_md5`, and gray keys `diff_update.enable` /
        // `enable_fallback_try` / `fallback_try_count` / `package_version_mapping`).
        // That last key is the tell: patches are keyed FROM a version TO a version.
        // `9.99` is not a version anyone runs, so a request carrying it can never
        // match a patch mapping — this recipe is structurally cut off from the
        // delta route, not merely unlucky.
        //
        // Note what that evidence IS: `cfg.diff_url=%s` / `cfg.diff_md5=%s` are LOG
        // FORMAT STRINGS in `updatecontroller.cpp` — CapCut printing its own
        // `ReminderUpdateCfg` fields — not fields seen in a response. They prove
        // the client can apply a patch, not that the server sends one.
        //
        // It costs nothing today, and this is checked in a way that does not depend
        // on guessing the schema (probed 2026-08-27 at `version_code` 9.2.0, 9.3.0,
        // 9.3.5 and 9.99): the settings object is FLAT — zero of its top-level keys
        // contain a dot, so the binary's `diff_update.enable` means a top-level
        // `diff_update` object — and that key is absent; a brute-force scan of the
        // whole raw body finds no diff/delta/patch key that concerns app updates
        // (the hits are draft sizes, material templates, network dispatch); and
        // there is no `.delta`/`.patch`/`.diff` URL in the body at all. The vendor
        // ships everyone the full package right now.
        //
        // (`update_reminder` was never the place to look, which is worth recording
        // because the first version of this comment said it was: not one of the
        // `update_reminder.*` keys registered in the binary carries a diff, patch
        // or delta. `diff_update` is where it would live.)
        //
        // Worth knowing for the day it does: the patch is almost certainly a
        // SPARKLE binary delta, i.e. the exact format `DeltaApplier` already
        // applies. CapCut embeds stock Sparkle 2.7.0 (build 2044) and its
        // `Autoupdate` carries the whole applier — `BinaryDelta`,
        // `SUBinaryDeltaUnarchiver`, `SUBinaryDeltaCommon.m`, `/usr/bin/bspatch`,
        // `sparkle:deltaFrom`, and Sparkle's "patch version too old" message — and
        // `libVECreator` implements Sparkle's own `installerDidFailToApplyDeltaUpdate`
        // callback and builds updates through
        // `initWithAppcastItem:secondaryAppcastItem:…`, where `secondaryAppcastItem`
        // IS Sparkle's delta slot. (Inference, not proof: no `.delta` is served, so
        // none has been examined.)
        //
        // So consuming it would be plumbing, not new machinery: what is missing is
        // a way to take a patch URL from a JSON field instead of from an appcast's
        // `<sparkle:deltas>`, which is all `VendorAppcastDeltas` knows how to read.
        // The real blocker is the pinned `version_code` above — a from→to mapping
        // cannot match a version nobody runs — and un-pinning it needs a way to put
        // the installed version on the wire, which no recipe field offers today.
        //
        // Two components, not three, is also load-bearing: `RecipeSanity` complains
        // when an extracted version appears verbatim in the request URL (the tell
        // for a pattern that matched the query instead of the body). `9.3.0` would
        // trip that the moment stable is 9.3.0 — which it is today. CapCut versions
        // are always three-segment, so a two-segment `version_code` can never
        // collide with an answer.
        //
        // TRAP, `channel`: `capcutpc_beta` is a REAL CapCut channel token and is
        // the wrong thing to send here — the endpoint returns no `update_reminder`
        // at all for it (measured). `capcutpc_0` is what a stable install sends and
        // what returns BOTH tracks, so both recipes send it. The channel a recipe
        // serves is decided by which `lastest_*` key it reads, not by this
        // parameter.
        //
        // Version scheme: the `lastest_*_version` integers are nibble-packed
        // (590592 = 0x090300 = 9.3.0), which no regex can decode, so the version is
        // read out of the artifact FILENAME instead — `CapCut_9_3_0_4490_…` — with
        // one capture group per segment. `extractVersion` joins multiple groups
        // with ".", which is what turns the vendor's underscores into the string
        // the bundle reports. The `_4490_` build counter is matched and discarded.
        //
        // TRAP, and the reason the two recipes disagree about `versionIsBuild`:
        // **the two tracks put their version in DIFFERENT Info.plist fields**, and
        // they are swapped relative to each other. Both dmgs were downloaded and
        // mounted on 2026-08-27 rather than reasoned about:
        //
        //   CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg
        //       CFBundleShortVersionString  9.3.0
        //       CFBundleVersion             9.3.0
        //   CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg
        //       CFBundleShortVersionString  9.3.4531      ← "9.3" + the build counter
        //       CFBundleVersion             9.4.0-beta4   ← what the filename says
        //
        // So the filename version equals the beta bundle's BUILD field, not its
        // marketing one. With `versionIsBuild: false` the engine would compare
        // `9.4.0-beta4` against a beta install's marketing `9.3.4531` — 4 > 3 —
        // and every beta user would be told to install the build they are already
        // running, forever. `versionIsBuild: true` on the beta recipe routes it
        // into `RemoteVersion.version` so it lands against `CFBundleVersion`, where
        // an up-to-date beta compares EQUAL. Stable needs no such thing (both of
        // its fields are the same string) and must not have it: mixing the two
        // within one channel is what the guard in `channelProofsCoverEveryChannelRecipe`
        // forbids, and across channels they are compared against different
        // installed fields anyway.
        //
        // A consequence worth stating: for a beta install, `ReleaseChannel.detect()`
        // sees only `9.3.4531` — its `-betaN` rule never fires — so the ONLY thing
        // that can classify a beta bundle as beta is `CapCutChannel`. That is why
        // its no-recorded-preference fallback reads the build's own channel token
        // rather than deferring to detect().
        //
        // The channel token in each filename (`capcutpc_0` vs `capcutpc_beta`) is
        // inside the pattern, not around it, so neither recipe can read the other
        // track's artifact even if the vendor reordered the JSON — and the beta
        // pattern is additionally pinned to `lastest_url` so it cannot drift onto
        // `lastest_sync_url`, a THIRD `capcutpc_beta` artifact in the same object
        // (9.3.5-beta1, build 4468 — an older build than the 4531 on `lastest_url`,
        // so taking it would be a silent downgrade of the beta track).
        //
        // Only the beta pattern's third segment tolerates a `-betaN` suffix.
        // Stable's ends at digits, on the Canva precedent: a prerelease wrongly
        // published under `lastest_stable_url` then matches NOTHING and degrades to
        // unknown, instead of being reported as a stable release.
        //
        // One-click: enabled on BOTH tracks, and every gate was checked against the
        // real artifacts rather than assumed (2026-08-27, both dmgs downloaded and
        // mounted). Each dmg holds `CapCut.app` and an `/Applications` symlink and
        // nothing else — no pkg, no `LaunchDaemons`/`LaunchAgents`/
        // `PrivilegedHelperTools`, and this machine has no CapCut launch item
        // anywhere — so the bundle swap IS the whole update. The Homebrew cask
        // agrees independently: `artifacts` is `{"app": ["CapCut.app"]}` and its
        // `uninstall` is a bare `quit`, its `zap` only user data. Both bundles are
        // Developer ID signed by Team `22MMUN2RN5` (BYTEDANCE PTE. LTD.) and
        // `spctl -t install` reports "Notarized Developer ID" — the same Team the
        // installed copy carries, which is `VendorInstaller`'s mandatory gate.
        //
        // The cask is also a second witness for the STABLE url itself: it points at
        // the byte-identical `…CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg` this
        // recipe resolves out of the settings blob.
        //
        // No `checksumPattern`: the vendor publishes `lastest_stable_url_md5` /
        // `lastest_url_md5`, and `checksumPattern` consumes a base64 SHA-512. An
        // MD5 cannot be fed to it, so the Team-ID gate is the guard here.
        //
        // Cost to know about: each install is a ~1.24 GB download. The registry's
        // live signature-gate test deliberately runs on an allow-list of small
        // artifacts, so adding this does not put a gigabyte into `make test`.
        //
        // `hostRequirement` is Apple silicon, and that is measured, not assumed:
        // `lipo -archs` on the shipped build reports `arm64` and nothing else — on
        // the launcher, on `libVECreator.dylib`, and on `CapCut Helper.app` — so
        // the one dmg the vendor publishes cannot start on an Intel Mac. The
        // vendor's own schema has `lastest_stable_cpu_architecture` /
        // `lastest_cpu_architecture` keys (they are in the binary's string pool)
        // but leaves them absent from the response, i.e. it is serving one
        // artifact to everyone. Without the gate, an Intel Mac holding an older
        // CapCut would be told about a version forever and handed a one-click that
        // `SignatureVerifier`'s arch check can only refuse. Whether an Intel train
        // ever existed is NOT established here — if one turns up, this is the line
        // to revisit, and the shape to copy is Raycast's two-endpoint split.
        //
        // `downloadURL` (the manual fallback) points at the vendor's desktop page
        // for both tracks. That page only ever hands out the stable downloader
        // stub, which used to make it an active hazard for a beta user; with
        // one-click resolving each track's own artifact, the manual link is now the
        // fallback rather than the path, and the alternative (`nil`) would put a
        // ~400 KB internal settings blob behind the user-facing link.
        //
        // A Mac App Store copy of CapCut shares this bundle id — and is a
        // completely different train: `itunes.apple.com/lookup` for
        // `com.lemon.lvoverseas` returns adamId 1500855883 at version **19.2.0**
        // against this Developer ID build's 9.3.0. Nothing here can reach it:
        // `VendorProbeSource.latestVersion(for:)` declines every `isMASApp`
        // install, and `MacAppStoreSource` declines every non-store one, so the
        // separation rests entirely on `_MASReceipt`. Were either gate to go, the
        // two version schemes would produce a permanent phantom in one direction
        // and a store-entitlement-destroying swap in the other.
        //
        // No `changelogURL`: `update_reminder` does carry release notes, but the
        // same generic sentence for all three tracks ("Fixed some known issues…"),
        // and capcut.com publishes no desktop release-notes page (/release-notes,
        // /whats-new and /support/release-notes all 502, 2026-08-27). The honest
        // "no release notes" state beats an unrelated page.
        capCutRecipe(
            channel: .stable, urlKey: "lastest_stable_url",
            packageToken: "capcutpc_0", patchSegment: #"[0-9]+"#,
            versionIsBuild: false),
        capCutRecipe(
            channel: .beta, urlKey: "lastest_url",
            packageToken: "capcutpc_beta", patchSegment: #"[0-9]+(?:-beta[0-9]+)?"#,
            versionIsBuild: true),

        // 百度网盘 (Baidu Netdisk) — reads the endpoint the vendor's own download
        // page is built from: `pan.baidu.com/disk/cmsdata?do=client` answers a small
        // JSON with one object per product line (`android`, `guanjia` = the Windows
        // client, `linux`, `mac`, `tv`, `genflow-pro-pc-mac`, …), each carrying that
        // line's version, its architecture URLs and a publish stamp. It answers
        // anonymously — no cookie, no Referer, the browser-like default UA is fine
        // (measured 2026-08-29).
        //
        // Nothing standard can cover this app. It ships `Squirrel.framework` and an
        // electron-updater `Contents/Resources/app-update.yml` naming
        // `https://netdisk-pc.cdn.bcebos.com/update/`, but that feed is DEAD:
        // `latest-mac.yml`, `latest-mac-arm64.yml` and the directory itself all 404.
        // The updater that actually runs is `libkernel.dylib`'s
        // `http://update.pan.baidu.com/autoupdate`, which answers 200 with a
        // ZERO-BYTE body to every request we can form — its parameters are not in
        // the clear, and it is plain HTTP besides. There is no Sparkle appcast, and
        // the Homebrew cask cannot apply (this copy was installed by hand, and the
        // brew provenance gate only adopts what brew installed).
        //
        // ANCHORING — the body carries several `…_arm64.dmg` URLs and only one is
        // this app. `MACguanjia` (the Netdisk Mac client) sits beside
        // `MACGenFlowPro` (库库GenFlow, a different Baidu product on the same CDN),
        // and the netdisk entry itself publishes x64 / arm64 / universal side by
        // side. So both patterns pin the product path AND the architecture: a bare
        // `_arm64\.dmg` matches `KukuAI_1.3.6_arm64.dmg` FIRST in the real body.
        //
        // The version pattern uses a BACKREFERENCE so the directory version and the
        // filename version have to agree — the version this reports is then, by
        // construction, the version of the file the install spec downloads. A
        // mismatch degrades to "unknown", which is the safe direction.
        //
        // One-click verified 2026-08-29 by hashing the artifact this recipe
        // resolves: `…/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_arm64.dmg` is MD5
        // `23bfa249b059597234bfd396bf631300` — the CDN's own ETag, and the same
        // bytes as the downloaded image, whose `BaiduNetdisk_mac.app` is bundle id
        // `com.baidu.BaiduNetdisk-mac`, Team `738UU3Y57V` (the installed copy's
        // team), `lipo -archs` arm64, and `spctl -a -t install` "Notarized
        // Developer ID". The install source must stay `.bodyPattern`: that CDN
        // answers **405 Method Not Allowed** to HEAD, so a `.redirect` source could
        // not resolve it at all.
        //
        // FROZEN-MARKETING GRANULARITY, stated rather than assumed: the feed
        // exposes only a marketing version (`8.7.9`) while the bundle also carries a
        // build (`CFBundleVersion` 473) the feed never mentions. `VersionComparator`
        // ties on marketing, finds no remote build, and answers "not newer" — so a
        // build-only respin is invisible here, never a phantom update. Baidu's mac
        // line does move its marketing version (the same body has the Windows client
        // at 8.7.9.102 and linux at 8.7.0), so this is a granularity limit, not a
        // dead discriminator.
        //
        // No `publishedAtPattern`: `publish` is `"2026-08-28 14:39:00"` —
        // space-separated and zone-less, a shape `ReleaseDate` does not parse, so
        // the pattern would silently yield nothing. It is Asia/Shanghai (that stamp
        // is two minutes before the artifact's own `Last-Modified: Fri, 28 Aug 2026
        // 06:41:09 GMT`), exactly the assumption `ReleaseDate`'s zone-less branch
        // warns about — reading it as UTC would place every Baidu release eight
        // hours early in the timeline.
        //
        // `changelogURL` is the vendor's own 版本更新 page, which has a Mac版 tab.
        // Note the page is a JS shell — its eight `<section>`s ship EMPTY and are
        // filled from `/disk/cmsdata?platform=mac&…`, so it is only good as the
        // human-facing fallback; the parsed notes come from a `ChangelogRecipe`
        // reading that same endpoint (see `ChangelogRecipeRegistry`). The
        // `feature_tips` field on THIS response is empty for `mac` and is not it.
        VendorProbeRecipe(
            bundleID: "com.baidu.BaiduNetdisk-mac",
            url: URL(string: "https://pan.baidu.com/disk/cmsdata?do=client")!,
            mode: .responseBody,
            versionPattern:
                #"/MACguanjia/([0-9]+(?:\.[0-9]+)+)/BaiduNetdisk_mac_\1_arm64\.dmg"#,
            // The probe URL is a JSON API, so it must not be what a "download page"
            // link opens; pan.baidu.com/download is the product's own page.
            downloadURL: URL(string: "https://pan.baidu.com/download"),
            changelogURL: URL(string: "https://pan.baidu.com/disk/version"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://pkg-ant\.baidu\.com/issue/netdisk/MACguanjia/[0-9][^"]*/BaiduNetdisk_mac_[0-9][^"]*_arm64\.dmg)"#),
                kind: .dmg)),

        // QQ音乐 (QQMusic Mac) — Tencent ships no Sparkle appcast and no public
        // version API; the client updates itself in-app. The one machine-readable
        // surface is the download page's own data file,
        // `y.qq.com/download/download.js`, a JSONP document
        // (`MusicJsonCallback({"data":[…]})`) with ONE OBJECT PER PLATFORM —
        // Windows, Mac, iPhone, Android, TV, 车载, HarmonyOS, and two sibling
        // Tencent products (腾讯视频 / QQ影音 / 电脑管家). The Homebrew cask is
        // `auto_updates`, so it is not a source here.
        //
        // The `y.qq.com/download/index.html` page carries NO notes of its own: it
        // is a JS shell that fetches this same file client-side (measured
        // 2026-08-29 — the served HTML does not contain any release-note string).
        // So the notes come from a `ChangelogRecipe` over this same URL, and
        // `changelogURL` points at that page only as the human-facing fallback.
        //
        // URL: every query parameter the site sends
        // (`cv`/`ct`/`format`/`platform`/`g_tk`/`jsonpCallback`/…) is INERT —
        // measured 2026-08-29, the bare path, the site's full query, and a minimal
        // query all return byte-identical bodies with identical `Last-Modified`
        // and `Cache-Control: max-age=600`, and the callback name is always
        // `MusicJsonCallback` regardless of `jsonpCallback`. So the bare path is
        // registered: fewer tokens to go stale, same answer.
        //
        // ANCHORING — the body holds TWO `"Ftype":2,"Ftitle":"Mac"` objects. `ID:2`
        // is the live client (11.8.1, 2026-08-03); `ID:15` is a 2020-era legacy
        // record still parked in the table (7.0.0, "QQ音乐Mac7.0全新改版", link
        // `QQMusicMac_Mgr.dmg`). Both patterns therefore key on the VERSIONED Mac
        // dmg filename `QQMusicMac<ver>Build<nn>.dmg` rather than on `Ftitle`, an
        // `ID`, or a `Fversion` label: the legacy entry's link has no version in it
        // (`QQMusicMac_Mgr`), so `QQMusicMac[0-9]` excludes it structurally, and
        // the Windows/Android/iOS links carry different filename stems. One match
        // each in the live body.
        //
        // FROZEN-MARKETING GRANULARITY, stated rather than assumed: the `Build01`
        // in the filename is the vendor's respin ordinal for that marketing
        // version, NOT the app's `CFBundleVersion` (the installed 11.8.1 reports
        // build `73276`). Comparing it as a build would be a cross-namespace
        // comparison, so this stays a marketing-only recipe (`versionIsBuild`
        // false): a same-marketing respin (11.8.1 Build01 → Build02) is invisible
        // here, never a phantom update. Tencent does move the marketing version
        // (the same body has Windows at 22.5.2 and iPhone at 20.7.5), so this is a
        // granularity limit, not a dead discriminator.
        //
        // No `publishedAtPattern`: the date lives inside `Fdesc` as
        // `发布时间：2026-08-03` — a bare calendar day with no time and no zone,
        // which `ReleaseDate` does not parse, so a pattern here would be a silent
        // no-op. (It is also the FIRST-match trap: the Windows object precedes Mac
        // in the body, so an unanchored date pattern would stamp the Mac release
        // with Windows' date.) The ChangelogRecipe shows the day verbatim, which
        // is display-only and where a zone-less day belongs.
        //
        // One-click verified 2026-08-29 by resolving and opening the artifact this
        // recipe builds: `Flink1` 302s to
        // `dldir.y.qq.com/…/QQMusicMac11.8.1Build01.dmg?sign=…` (the `sign` is
        // minted per request by the redirect; the one in the body is the redirect's
        // own token, read fresh from the live body at apply time). The 97 MB image
        // holds `QQMusic.app` AND NOTHING ELSE — no pkg, no daemon, no
        // LaunchAgents/LaunchDaemons/PrivilegedHelperTools sibling on this machine
        // — which is what makes `.dmg` (bundle swap only) the correct kind rather
        // than `.pkg`. Bundle id `com.tencent.QQMusicMac`, `CFBundleShortVersionString`
        // 11.8.1 / `CFBundleVersion` 73276 (identical to the installed copy), Team
        // `FN2V63AD2J` (Tencent Technology (Shanghai) Company Limited — the
        // installed copy's team, which the VendorInstaller signature gate enforces),
        // `spctl -a -t install` "Notarized Developer ID", `lipo -archs` x86_64 arm64.
        VendorProbeRecipe(
            bundleID: "com.tencent.QQMusicMac",
            url: URL(string: "https://y.qq.com/download/download.js")!,
            mode: .responseBody,
            versionPattern: #"QQMusicMac([0-9]+(?:\.[0-9]+)+)Build[0-9]+\.dmg"#,
            // The probe URL is a JSONP data file, so it must not be what a
            // "download page" link opens; y.qq.com/download is the product's page.
            downloadURL: URL(string: "https://y.qq.com/download/index.html"),
            changelogURL: URL(string: "https://y.qq.com/download/index.html"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://c\.y\.qq\.com/cgi-bin/file_redirect\.fcg\?[^"]*QQMusicMac[0-9][^"]*Build[0-9]+\.dmg[^"]*)"#),
                kind: .dmg)),

        // MARK: - 2026-08-29 TimeMachineEditor

        // TimeMachineEditor has no Sparkle feed (confirmed: the vendor's own pkg,
        // downloaded and expanded 2026-08-29, carries no `SUFeedURL` in its app's
        // Info.plist and no `Sparkle.framework`), no MAS listing, no GitHub repo —
        // the vendor's own tiny site is the only surface. Its Homebrew cask
        // (`timemachineeditor`) is `auto_updates: true`, which makes
        // `HomebrewCaskSource` skip it, so this probe is the only source that can
        // ever answer for this bundle id.
        //
        // No JSON/version API exists — the homepage IS the release note: a single
        // download link whose visible text carries the version
        // (`<a href="…/TimeMachineEditor.pkg">TimeMachineEditor 5.2.2</a> (2023,
        // February 16) …`, fetched 2026-08-29). This is exactly the endpoint
        // Homebrew's own `livecheck` block resolves against (`url :homepage`,
        // regex `href=.*TimeMachineEditor\s*v?(\d+(?:\.\d+)+)`), independently
        // confirming it's the vendor's intended version surface, not a guess. The
        // pattern here is anchored to the literal href AND the `</a>` boundary so
        // it cannot drift onto the nearby "macOS 10.13" floor mentioned in the same
        // sentence.
        //
        // Verified against the real artifact, not just the page text: the pkg was
        // downloaded and expanded 2026-08-29.
        // `PackageInfo` reads `CFBundleShortVersionString="5.2.2"
        // CFBundleVersion="219" CFBundleIdentifier="com.tclementdev.timemachineeditor.application"`
        // — the probed "5.2.2" matches the MARKETING field exactly, so no
        // `versionIsBuild`. Signed "Developer ID Installer: Thomas CLEMENT
        // (68GTH78H6S)", notarized.
        //
        // kind MUST be `.pkg`, not `.dmg`/`.zip`: the payload installs siblings
        // outside the `.app` — `/Library/LaunchDaemons/
        // com.tclementdev.timemachineeditor.scheduler.plist`, a scheduler binary
        // and `tmectl` CLI under `/Library/TimeMachineEditor/`, plus a
        // `com.tclementdev.timemachineeditor.upgrader` pre/postinstall script that
        // manages the daemon across upgrades. A bundle-only unpack would leave the
        // new `.app` next to a stale daemon with nothing to notice. The download
        // URL itself is a static, unversioned filename that always serves the
        // current release, so `.fixed` needs no pattern.
        //
        // Single channel: the vendor ships no beta/nightly, so there is nothing to
        // gate — `channel` stays the default `.stable`.
        //
        // Delta/binary patch: not checked for — this is not a Sparkle app (no
        // `SUFeedURL`, no `Sparkle.framework` in the bundle) and the download is a
        // ~1MB pkg with no companion `.delta`/`.patch` artifact anywhere on the
        // page, so there is nothing here to consume.
        VendorProbeRecipe(
            bundleID: "com.tclementdev.timemachineeditor.application",
            url: URL(string: "https://tclementdev.com/timemachineeditor/")!,
            mode: .responseBody,
            versionPattern:
                #"<a href="https://tclementdev\.com/timemachineeditor/TimeMachineEditor\.pkg">TimeMachineEditor\s+([0-9]+(?:\.[0-9]+)+)</a>"#,
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://tclementdev.com/timemachineeditor/TimeMachineEditor.pkg")!),
                kind: .pkg)),

        // Little Snitch (Objective Development) — application-firewall / Network
        // Extension. No Sparkle feed: `SUFeedURL` is absent from both a real
        // mounted 6.4.1 (stable) and 6.5-nightly-(7301) bundle (2026-08-29). The
        // app updates itself through a bespoke component (`Little Snitch Software
        // Update.app`) that talks to a dynamic endpoint
        // (`sw-update.obdev.at/update-feeds/software-update.php`) whose request
        // shape isn't known — a plain GET answers "Malformed Request", and
        // learning the real query params needs packet capture of the running
        // client, not attempted here. The Homebrew cask (`little-snitch`) is
        // `auto_updates: true` (`brew info --cask little-snitch`), so
        // `HomebrewCaskSource` deliberately skips it — this recipe is what keeps
        // the app off `.unknown`.
        //
        // obdev separately publishes a STATIC per-major-version fallback feed at
        // `sw-update.obdev.at/update-feeds/littlesnitch6.plist` — the exact URL
        // Homebrew's own `little-snitch` cask uses in its `livecheck` block
        // (`Casks/l/little-snitch.rb`), so this is a vendor endpoint a third
        // party (Homebrew) already depends on for the same purpose, not a guess.
        // It's an XML plist ARRAY with one entry per release lifecycle
        // (`nightly`, `final`); `final` is what this recipe reads.
        //
        // VERSION SCHEME, verified against the real mounted stable bundle
        // (2026-08-29): the feed's `final` entry's `BundleVersion` ("7212") is
        // byte-identical to the installed `CFBundleVersion`, and its
        // `BundleShortVersionString` ("6.4.1") matches `CFBundleShortVersionString`
        // too — so a plain marketing compare would also work for THIS entry, but
        // `versionIsBuild` is used anyway to share one comparison basis with the
        // nightly recipe below, where the feed's short-version field does NOT
        // match the installed bundle.
        //
        // `entryStartPattern` slices the two-entry array so `final`'s fields can
        // never be read out of the `nightly` entry (or vice versa) regardless of
        // which the feed happens to list first.
        //
        // No `install`: the feed states `InstallationMechanism: ReplaceBundle`
        // (a full `.app` swap, which is what `VendorInstaller` does too), but
        // Little Snitch ships a Network Extension
        // (`at.obdev.littlesnitch.networkextension.systemextension`, under
        // `Contents/Library/SystemExtensions/`) and a privileged daemon rooted at
        // `/Library/Little Snitch/`. Whether a bare `.app` swap re-activates the
        // extension as cleanly as the vendor's own updater does is NOT verified
        // on a real machine here — detection only until that's confirmed
        // end-to-end. Team `MLZF7K7B5R`.
        VendorProbeRecipe(
            bundleID: "at.obdev.littlesnitch",
            url: URL(string: "https://sw-update.obdev.at/update-feeds/littlesnitch6.plist")!,
            mode: .responseBody,
            versionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>final</string>[\s\S]*?<key>BundleVersion</key>\s*<string>(\d+)</string>"#,
            downloadURL: URL(string: "https://obdev.at/littlesnitch/download.html"),
            changelogURL: URL(string: "https://obdev.at/products/littlesnitch/releasenotes6.html"),
            versionIsBuild: true,
            displayVersionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>final</string>[\s\S]*?<key>BundleShortVersionString</key>\s*<string>([^<]+)</string>"#,
            entryStartPattern: #"<key>ReleaseLifecycle</key>\s*<string>"#),

        // Little Snitch, NIGHTLY channel — same bundle id, no separate cask
        // `auto_updates` quirk to work around (the nightly cask is ALSO
        // `auto_updates: true`), and no in-app preference toggle: the stable
        // 6.4.1 bundle carries zero "nightly" strings anywhere (grepped the
        // whole mounted `.app`, 2026-08-29). A Nightly install is a completely
        // separate download (`little-snitch@nightly` cask, which
        // `conflicts_with` the stable cask) that happens to keep the SAME bundle
        // id — confirmed both from the nightly cask's own `uninstall quit:
        // "at.obdev.littlesnitch"` line and directly, by mounting the
        // 6.5-nightly-(7301) dmg and reading its Info.plist.
        //
        // CHANNEL SIGNAL: unlike every other same-bundle-id app in this
        // registry, Object Development bakes the channel word straight into the
        // installed `CFBundleShortVersionString` itself — "6.5 nightly (7301)",
        // confirmed against the real mounted nightly bundle (not just the feed).
        // Diffing the two Info.plists shows ONLY `CFBundleShortVersionString`
        // and `CFBundleVersion` differ; the bundle id, name and everything else
        // are identical. `ReleaseChannel.detect()` needed a new step for this
        // (see step "0.7" there): the shape is `"<num> nightly (<build>)"` —
        // space-separated with a parenthesized build suffix — not the dash-tail
        // shape (`versionTailPattern`) step 4 already recognizes, so without the
        // new rule this install would silently read as `.stable`.
        //
        // FEED-VS-BUNDLE TRAP (exactly the shape this registry's notes warn
        // about elsewhere): the feed's `BundleShortVersionString` for the
        // `nightly` entry is plain "6.5" — it STRIPS the " nightly (7301)"
        // suffix the real installed bundle carries. Never trust that field for
        // channel detection. `versionIsBuild` sidesteps it entirely by comparing
        // `BundleVersion` "7301", which DOES match the installed
        // `CFBundleVersion` byte-for-byte.
        //
        // Same static feed as stable, `nightly` lifecycle entry. No `install`,
        // same reasoning as the stable recipe above — and this channel is
        // explicitly the least-tested of the two by the vendor's own process.
        // No `changelogURL`: obdev's public release-notes page
        // (`releasenotes6.html`, used above) covers stable only — it has no
        // mention of "nightly" anywhere (checked 2026-08-29) — and the per-build
        // notes endpoint the feed points at
        // (`releasenotes-legacy-swu.php?version=<build>`) is pinned to whichever
        // build this comment was written against, which would go stale the next
        // nightly ships. Leaving this nil renders the normal "no release notes"
        // state rather than a URL that quietly stops matching the version on
        // screen.
        VendorProbeRecipe(
            bundleID: "at.obdev.littlesnitch",
            url: URL(string: "https://sw-update.obdev.at/update-feeds/littlesnitch6.plist")!,
            mode: .responseBody,
            versionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>nightly</string>[\s\S]*?<key>BundleVersion</key>\s*<string>(\d+)</string>"#,
            downloadURL: URL(string: "https://obdev.at/littlesnitch/download-nightly.html"),
            versionIsBuild: true,
            displayVersionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>nightly</string>[\s\S]*?<key>BundleShortVersionString</key>\s*<string>([^<]+)</string>"#,
            entryStartPattern: #"<key>ReleaseLifecycle</key>\s*<string>"#,
            channel: .nightly),

        // Carbon Copy Cloner — THREE independently maintained major-version
        // generations (5, 6, 7) all report the SAME bundle id `com.bombich.ccc`,
        // confirmed 2026-08-29 by downloading and expanding all three real zips:
        // `com.bombich.ccc` 5.1.28/6213, `com.bombich.ccc` 6.1.13/7699,
        // `com.bombich.ccc` 7.1.6/8368 — same Team `L4F2DED5Q7`. Bombich still
        // ships point releases to all three (bombich.com/download lists
        // `?v=ccc5`/`?v=ccc6`/`?v=ccc7` as live download links alongside
        // `?v=latest`, which is a permanent alias for whichever is newest —
        // currently ccc7) and crossing generations is a PAID upgrade, not a free
        // update: "We do not sell CCC 4 or CCC 5 licenses. To use CCC 4 or 5,
        // please purchase a CCC 6 license" (bombich.com/en/kb/ccc/6). CCC 7 also
        // requires Ventura+ (bombich.com/download's own compatibility table),
        // which a CCC 5 install on High Sierra–Big Sur or a CCC 6 install on
        // Catalina–Monterey cannot run at all.
        //
        // Each generation therefore gets its own recipe, gated with
        // `installedVersionPattern` so `VendorProbeSource` only offers a
        // same-generation point release — never routes a CCC 5/6 install through
        // `?v=latest`'s CCC 7 answer just because "7.1.6" sorts numerically
        // above "5.1.28"/"6.1.13". Without this gate every CCC 5/6 install in
        // this registry would have been a phantom cross-generation "update"
        // forever, silently, the same shape of bug `VersionComparator`'s
        // "never compare across namespaces" rule exists to prevent — just one
        // this registry had not modeled before because no other vendor here
        // keeps multiple ACTIVELY maintained generations under one bundle id.
        //
        // stable (CCC 7) — the app DOES ship a Sparkle
        // `SUFeedURL` (`https://api.bombich.com/updates/ccc`, confirmed reading
        // the real Info.plist inside the vendor's own download), so it is not the
        // "no Sparkle at all" case it first looks like. But that feed answers
        // every request we tried — plain GET, several User-Agents including a
        // Sparkle-shaped one, an `appVersion` query param, and the same
        // `URLSession`/UA `SparkleAppcastSource` itself sends — with HTTP 200 and
        // a ZERO-BYTE body (verified 2026-08-29, five variants, all `Content-Length: 0`).
        // `SparkleAppcastSource` would parse that into an empty item list and
        // report "no update" forever: a silent dead source, not a missing one.
        // Homebrew's cask carries `auto_updates: true`, so `HomebrewCaskSource`
        // correctly refuses it too — there is no standard source left to answer.
        //
        // The endpoint that DOES work is the one the cask's own `livecheck` block
        // already relies on: `download_ccc.php?v=latest` 302s (through a second
        // hop at `api.bombich.com/download/ccc?v=latest`) to a versioned filename
        // on the CDN — `ccc-7.1.6.8368.zip` — confirmed with a plain HEAD request
        // via `URLSession` (the exact request `.redirectFilename` issues), which
        // follows both hops and lands on the CDN URL without downloading the 27 MB
        // body. `7.1.6` matches the installed app's `CFBundleShortVersionString`
        // exactly (`8368` matches `CFBundleVersion`), and CCC bumps its marketing
        // version on every release (7.0 → 7.0.4 → 7.1 → … → 7.1.6, roughly
        // quarterly per `https://bombich.com/software/updates/ccc7_rn.html`) — not
        // a frozen-marketing app — so the default marketing-only comparison
        // (`versionIsBuild: false`) is correct, no build-number routing needed.
        // The filename's marketing segment is 2 OR 3 dot-groups depending on era
        // (`ccc-7.1.1234.zip` for a bare `7.1` release vs `ccc-7.1.6.8368.zip`),
        // which is exactly why the cask's own `livecheck` comment calls out a
        // "variable number of parts" — the pattern below accepts both, always
        // taking everything before the trailing 3+ digit build segment.
        //
        // No `install`: this is detection-only. CCC installs a privileged helper
        // (`com.bombich.ccchelper`), a LaunchDaemon and an XPC service alongside
        // the `.app`, so an in-place bundle swap is a materially bigger claim than
        // the zip-swap one-clicks already in this registry; adding it is a
        // separate decision.
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=latest")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=latest"),
            changelogURL: URL(string: "https://bombich.com/software/updates/ccc7_rn.html"),
            variant: "ccc7",
            installedVersionPattern: #"^7\."#),

        // beta (CCC 7) — same bundle id, opted into from
        // CCC's own Settings → Software Update → "Inform me of beta releases".
        // The blocker recorded on 2026-08-29 (needs the user's own packet
        // capture — `?v=beta` redirects to the plain download page, and
        // `?v=latest-beta` just resolves to the stable zip) turned out to be a
        // wrong guess at the query param spelling, not a real auth wall:
        // `?v=latestbeta` (no hyphen) 302s through the same two-hop chain as
        // stable to a genuine beta artifact —
        // `ccc-7.1.7-b7.8389.zip` — confirmed 2026-08-29 by downloading and
        // expanding the real zip: `CFBundleShortVersionString="7.1.7-b7"
        // CFBundleVersion="8389" CFBundleIdentifier="com.bombich.ccc"`, Team
        // `L4F2DED5Q7`, notarized. Marketing matches the probed capture group
        // exactly, so `versionIsBuild` stays the default `false`, same as
        // stable.
        //
        // CHANNEL SIGNAL: `CFBundleShortVersionString` carries a short `-b<N>`
        // suffix ("7.1.7-b7") that `ReleaseChannel.detect()` needed a new
        // bundle-id-scoped rule for (step 0.8) — it is neither the Mozilla
        // `b<N>` shape (requires exactly one dot, no dash) nor the full-word
        // `-beta<N>` shape (GitHub Desktop's), so without that rule this would
        // silently read as `.stable`.
        //
        // No `changelogURL` beyond what's already public: the same
        // `ccc7_rn_beta.html` page the stable investigation already found
        // (lists "CCC 7.1.7-b7 (pre-release)") is reused here directly rather
        // than re-verified as a separate discovery.
        //
        // No `install`, same reasoning as stable — the privileged-helper
        // footprint applies equally to both channels. `installedVersionPattern`
        // scopes this to CCC 7 for the same reason stable's does — there is no
        // evidence CCC 5/6 currently ship a beta at all (`?v=beta`/`?v=latestbeta`
        // only ever answered with a CCC 7 artifact, 2026-08-29), so this is
        // scoped to what was actually observed, not assumed to generalize.
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=latestbeta")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-([0-9]+(?:\.[0-9]+)+-b[0-9]+)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=latestbeta"),
            changelogURL: URL(string: "https://bombich.com/software/updates/ccc7_rn_beta.html"),
            channel: .beta,
            installedVersionPattern: #"^7\."#),

        // stable (CCC 6) — DOES carry a Sparkle `SUFeedURL`
        // (`https://update.bombich.com/software/updates/ccc.php`, read from the
        // mounted 6.1.13 bundle) — a DIFFERENT literal URL than CCC 7's
        // (`api.bombich.com/updates/ccc`), so this is not simply "same feed,
        // different app". But it 301s → 302s straight into that exact CCC 7
        // feed URL and returns the identical HTTP 200 + zero-byte body (verified
        // 2026-08-29 following the full redirect chain) — so Bombich's whole
        // Sparkle update backend is dead across all three generations, not a
        // CCC-7-specific outage, and `SparkleAppcastSource` is a dead end here
        // too. No MAS listing, no GitHub repo. Same `download_ccc.php` endpoint
        // as detection, `v=ccc6`
        // instead of `latest`/`latestbeta` — confirmed 2026-08-29 with a plain
        // HEAD request: two-hop redirect to `ccc-6.1.13.7699.zip`, matching the
        // mounted bundle's `CFBundleShortVersionString`/`CFBundleVersion`
        // exactly. Same filename shape as CCC 7 (`ccc-<marketing>.<build>.zip`),
        // so the same pattern applies unchanged.
        //
        // `installedVersionPattern` pins this to CCC 6 — without it this recipe
        // and CCC 7's would both match a CCC 6 install (nothing else
        // distinguishes them structurally) and `VendorProbeSource.best(of:)`
        // would report whichever answered a higher version, which is CCC 7's,
        // recreating the exact bug this whole three-recipe split exists to fix.
        //
        // `variant` is required here too, separately from that: three recipes
        // share (bundleID, channel) = (`com.bombich.ccc`, `.stable`), and
        // `channelProofsCoverEveryChannelRecipe` requires every recipe in such a
        // group to carry a distinct `variant` — otherwise they'd collide onto
        // one `recipeID` and share a verify baseline / issue history despite
        // being three different endpoints.
        //
        // changelogURL: CCC 6's own release-notes page (distinct from CCC 7's
        // `ccc7_rn.html`) — verified 200 with real per-version content
        // 2026-08-29, titled "CCC 6 Release Notes".
        //
        // No `install`: same privileged-helper footprint as CCC 7 (confirmed by
        // the same category of components in the mounted 6.1.13 app), so
        // detection-only for the same reason.
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc6")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc6"),
            changelogURL: URL(string: "https://bombich.com/en/kb/ccc/6/release-notes"),
            variant: "ccc6",
            installedVersionPattern: #"^6\."#),

        // stable (CCC 5) — same reasoning as CCC 6 above, one generation older.
        // `v=ccc5` confirmed 2026-08-29: two-hop redirect to
        // `ccc-5.1.28.6213.zip`, matching the mounted bundle's
        // `CFBundleShortVersionString`/`CFBundleVersion` exactly (Team
        // `L4F2DED5Q7`, same as 6 and 7). Same filename shape, same pattern.
        // `installedVersionPattern` pins this to CCC 5 for the identical reason
        // CCC 6's does. changelogURL is CCC 5's own release-notes page, verified
        // 200 2026-08-29. No `install`, same reasoning as the other two.
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc5")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc5"),
            changelogURL: URL(string: "https://bombich.com/en/kb/ccc/5/release-notes"),
            variant: "ccc5",
            installedVersionPattern: #"^5\."#),
    ]

    /// One CapCut track: the `update_reminder` key that names its artifact, plus
    /// the token that artifact's filename carries.
    ///
    /// Those two thread through both patterns, which is the point of building them
    /// here instead of writing them out twice. The version and the installer must
    /// come from the SAME key — `update_reminder` holds four CapCut dmg URLs under
    /// four keys, two of which name the same file today — and a hand-written pair
    /// is exactly how one of them ends up reading `lastest_url` while the other
    /// reads `lastest_sync_url`, resolving a version and an installer from two
    /// different releases with nothing downstream able to see it.
    ///
    /// The endpoint is built once for the same reason: two copies could drift onto
    /// different `version_code` rollout buckets.
    private static func capCutRecipe(
        channel: ReleaseChannel,
        urlKey: String,
        packageToken: String,
        patchSegment: String,
        versionIsBuild: Bool
    ) -> VendorProbeRecipe {
        let host = #"https://sf16-web-tos-buz\.capcutstatic\.com"#
        return VendorProbeRecipe(
            bundleID: CapCutChannel.bundleID,
            url: URL(string: "https://editor-api.capcutapi.com/service/settings/v3/"
                     + "?aid=359289&device_platform=mac&channel=capcutpc_0&version_code=9.99")!,
            mode: .responseBody,
            versionPattern:
                #""\#(urlKey)"\s*:\s*"[^"]*/CapCut_([0-9]+)_([0-9]+)_(\#(patchSegment))_[0-9]+_\#(packageToken)_creatortool\.dmg""#,
            downloadURL: URL(string: "https://www.capcut.com/tools/desktop-video-editor"),
            versionIsBuild: versionIsBuild,
            install: VendorInstallSpec(
                // Host pinned rather than `[^"]+`: the channel token and the host
                // are the only things in a resolved URL that say what this file is.
                urlSource: .bodyPattern(
                    #""\#(urlKey)"\s*:\s*"(\#(host)/[^"]*_\#(packageToken)_creatortool\.dmg)""#),
                kind: .dmg),
            channel: channel,
            hostRequirement: VendorHostRequirement(architectures: [.arm64]))
    }

    /// One WorkBuddy recipe: a site — which decides the bundle id, the update
    /// host and the changelog at once — crossed with a macOS architecture.
    ///
    /// The `slug` threads through three places that must agree: the `platform`
    /// the endpoint is asked about, the `darwin-<arch>` path the install URL is
    /// pinned to, and the `variant` that keeps the two same-channel recipes'
    /// `recipeID`s (and so their verify baselines) apart. Building all three from
    /// one value is what stops an arm64 recipe from ever quoting an x64 artifact.
    ///
    /// `assetHost` is the other half of that: the two sites' artifact PATHS are
    /// identical, so the host is the only thing in a resolved URL that says which
    /// site it came from, and it is pinned rather than matched with `[^"]+`.
    private static func workBuddyRecipe(
        bundleID: String,
        host: String,
        assetHost: String,
        arch: HostArch,
        downloadURL: URL,
        changelogURL: URL
    ) -> VendorProbeRecipe {
        let slug = arch == .arm64 ? "arm64" : "x64"
        let assetHostPattern = assetHost.replacingOccurrences(of: ".", with: #"\."#)
        return VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string:
                "https://\(host)/v2/update?platform=workbuddy-darwin-\(slug)&version=0.0.0")!,
            mode: .responseBody,
            versionPattern: #""productVersion"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)(?:\.[0-9]+)?""#,
            downloadURL: downloadURL,
            changelogURL: changelogURL,
            publishedAtPattern: #""timestamp"\s*:\s*([0-9]{9,})"#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://\#(assetHostPattern)/workbuddy/saas/darwin-\#(slug)/WorkBuddy-darwin-\#(slug)-[^"]+\.zip)""#),
                kind: .zip),
            variant: slug,
            hostRequirement: VendorHostRequirement(architectures: [arch]))
    }

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
