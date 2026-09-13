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
    /// the bundle id. Most recipes here target Stable, so this defaults to
    /// `.stable` — but a substantial minority do not, across most of
    /// `ReleaseChannel`'s cases (beta, canary, nightly, preview, dev, esr, rc and
    /// more), so set it explicitly when adding a channel-specific endpoint.
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

    /// Where to read the vendor's release ORDER, for a vendor whose build ids have
    /// none of their own — commit hashes. nil (every recipe but one) changes
    /// nothing. See `BuildLineage` for why `VersionComparator` cannot stand in.
    ///
    /// When set, the probe fetches the lineage after reading the version, and the
    /// remote it produces always carries it — the engine then asks the lineage
    /// instead of `VersionComparator` wherever it decides "is this newer". A
    /// lineage that cannot be fetched, matches nothing, or does not list the
    /// version just read FAILS the probe: a remote without one would silently fall
    /// back to the coin flip this field exists to replace.
    public let buildLineage: BuildLineageSpec?

    /// A document listing every release newest first, and how to read one
    /// release's build id out of it.
    public struct BuildLineageSpec: Sendable {
        public let url: URL
        /// Capture group 1 is one release's build id, written to yield EXACTLY the
        /// form the installed bundle reports: the lineage is compared by equality,
        /// never by prefix.
        public let entryPattern: String

        public init(url: URL, entryPattern: String) {
            self.url = url
            self.entryPattern = entryPattern
        }
    }

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

    /// Regex that recognises the vendor's own **error envelope** — a body served
    /// with a success status that carries no answer at all.
    ///
    /// Without this, such a body is indistinguishable from a vendor changing
    /// their schema: `versionPattern` matches nothing, and the probe reports
    /// `versionPatternNoMatch`, which means "a human must go fix this recipe" —
    /// a red Failed row on every affected Mac and a GitHub issue filed under a
    /// recipe that is perfectly fine. Declaring the shape turns that into
    /// `ProbeFailure.vendorErrorEnvelope`, which is infra: retried once at the
    /// fetch, retried again by `duo verify`, and reported only once it has
    /// persisted for `Baseline.infraWindow` (five days) rather than after two
    /// sweeps.
    ///
    /// **Only `.responseBody`, and only without `requestBody`.** The retry rides
    /// on `URLSession.versionFeedData`, which is wired for this on that mode
    /// alone and refuses to repeat a POST — so declaring it anywhere else would
    /// hand a recipe the lenient CLASSIFICATION without the retry that is the
    /// half the user feels. `transientBodyIsOnlyDeclaredWhereItCanBeHonoured`
    /// pins that from the registry.
    ///
    /// CapCut is the measured case and the only recipe that sets it (2026-09-01).
    /// Its settings endpoint answers **HTTP 200** with
    /// `{"data": {},"message": "ExecBizCode error: … reason=request timeout
    /// request_timeout=500ms real_time=501018us"}` — ByteDance's own internal RPC
    /// overrunning its 500 ms budget — roughly 390 bytes where the answer is
    /// ~436 KB. Measured at about 1 request in 48 over two 24-way bursts, and it
    /// bit the shipping app twice in two minutes on 2026-09-01.
    ///
    /// Two rules for anything added here, both learned from that one:
    ///
    /// 1. **Anchor it to the document, not to a phrase.** CapCut's pattern is
    ///    `^\s*\{\s*"data"\s*:\s*\{\s*\}` — a TOP-LEVEL `data` that is empty,
    ///    which is structurally "no settings were returned". The message text is
    ///    an internal stack trace and will read differently the next time; an
    ///    empty top-level object cannot mean anything else. (Checked against the
    ///    real 436 KB healthy body: zero occurrences of an empty `data` object
    ///    anywhere in it, so even unanchored it would not have collided — the
    ///    anchor is what keeps that true for the body they serve next year.)
    /// 2. **It must not be able to match a healthy answer.** This pattern wins
    ///    over `versionPatternNoMatch`, so one that over-matches converts a
    ///    genuinely broken recipe into "the vendor is having a bad day, retry
    ///    forever" — a real breakage that `duo verify` would then never file.
    ///    `CapCutProbeRecipeTests` pins both directions against captured bodies.
    public let transientBodyPattern: String?

    /// The body says, in the vendor's own words, that this track has no current
    /// build.
    ///
    /// Distinct from the pattern simply not matching, and the distinction is the
    /// whole point: a miss is "the recipe stopped working, a human should look",
    /// while this is "the vendor is between releases on this track, nobody has
    /// anything to fix". They arrive identically — no version — and only the
    /// vendor can tell them apart, so this asks the vendor rather than inferring.
    ///
    /// Reported as ``ProbeFailure/notApplicable(_:)``, which returns nil instead
    /// of throwing: no red row, no entry in the failed-check banner, no Retry
    /// button that could never have worked.
    ///
    /// Consulted **only** when the version pattern already failed to match. A
    /// track that is publishing cannot be talked into looking closed.
    public let trackClosedPattern: String?

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

    /// Which of the installed bundle's build identifiers `versionPattern` extracts,
    /// when `versionIsBuild` is set. `.bundle` (the default, and correct for every
    /// recipe but Mozilla's pre-release five) means `CFBundleVersion`.
    ///
    /// `.vendor` means the vendor keeps its own build id somewhere else in the
    /// bundle and publishes THAT — Firefox/Thunderbird's `application.ini`
    /// `BuildID`, which `aus5.mozilla.org` answers with verbatim. It has to be
    /// declared rather than guessed because both namespaces are bare numbers: a
    /// `BuildID` compared against a `CFBundleVersion` does not fail, it answers the
    /// same thing forever. See `InstalledApp.BuildNamespace`.
    public let buildNamespace: InstalledApp.BuildNamespace

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
    /// document" now means "start/end of one entry" instead. A minority of recipes
    /// anchor `versionPattern` that way, and none of them has adopted
    /// `entryStartPattern` — don't, without re-deriving the pattern against a
    /// single sliced entry first. That is a build failure rather than a convention:
    /// `EntryStartPatternRegistryClaims.noAnchoredVersionPatternHasAdoptedEntryStartPattern`
    /// walks the registry for the combination and names any recipe that has it.
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
        transientBodyPattern: String? = nil,
        trackClosedPattern: String? = nil,
        downloadURL: URL? = nil,
        changelogURL: URL? = nil,
        selectHighest: Bool = false,
        versionIsBuild: Bool = false,
        buildNamespace: InstalledApp.BuildNamespace = .bundle,
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
        installedVersionPattern: String? = nil,
        buildLineage: BuildLineageSpec? = nil
    ) {
        self.bundleID = bundleID
        self.channel = channel
        self.url = url
        self.identities = identities
        self.track = track
        self.variant = variant
        self.hostRequirement = hostRequirement
        self.installedVersionPattern = installedVersionPattern
        self.buildLineage = buildLineage
        self.mode = mode
        self.versionPattern = versionPattern
        self.transientBodyPattern = transientBodyPattern
        self.trackClosedPattern = trackClosedPattern
        self.downloadURL = downloadURL
        self.changelogURL = changelogURL
        self.selectHighest = selectHighest
        self.versionIsBuild = versionIsBuild
        self.buildNamespace = buildNamespace
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

    /// Whether `body` is this vendor's error envelope rather than an answer —
    /// see ``transientBodyPattern``.
    ///
    /// False for a recipe that declares no pattern (the whole registry but one),
    /// and false for a pattern that does not compile. That second `false` is the
    /// safe direction — an uncompilable pattern costs the recipe its transient
    /// handling and it goes back to reporting `versionPatternNoMatch`, which is
    /// today's behaviour — but it is silent, so
    /// `transientBodyPatternsInTheRegistryAreValidRegexes` is what catches the
    /// typo before it ships.
    func matchesTransientBody(_ body: String) -> Bool {
        guard let pattern = transientBodyPattern,
              let regex = try? NSRegularExpression(pattern: pattern)
        else { return false }
        return regex.firstMatch(
            in: body, options: [], range: NSRange(body.startIndex..., in: body)) != nil
    }

    /// Whether the vendor states this track has no current build.
    func matchesTrackClosed(_ body: String) -> Bool {
        guard let pattern = trackClosedPattern,
              let regex = try? NSRegularExpression(pattern: pattern)
        else { return false }
        return regex.firstMatch(
            in: body, options: [], range: NSRange(body.startIndex..., in: body)) != nil
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
    ///
    /// Registry recipes DO combine the two — WeChat's Sparkle appcast and
    /// Windscribe's prerelease ChangeLogs feeds — and they are the recipes that
    /// depend on the straddle guard below being SKIPPED under `selectHighest`:
    /// several `versionPattern` matches inside one `<item>` / one `"id"` block are
    /// the expected shape for them, not evidence the slice spans two releases.
    /// Those two apps are named because a test pins them
    /// (`EntryStartPatternRegistryClaims.onlyTheDocumentedRecipesCombineSelectHighestWithEntryStartPattern`),
    /// so a third one cannot appear without this paragraph being revisited.
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
            transientBodyPattern: transientBodyPattern, trackClosedPattern: trackClosedPattern,
            downloadURL: downloadURL, changelogURL: changelogURL, selectHighest: selectHighest,
            versionIsBuild: versionIsBuild, buildNamespace: buildNamespace,
            displayVersionPattern: displayVersionPattern,
            publishedAtPattern: publishedAtPattern,
            entryStartPattern: entryStartPattern ?? self.entryStartPattern,
            install: install, requestBody: requestBody, requestHeaders: requestHeaders,
            followRedirects: followRedirects, channel: channel, identities: identities,
            track: track, variant: variant, hostRequirement: hostRequirement,
            installedVersionPattern: installedVersionPattern, buildLineage: buildLineage)
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
/// An app stays OUT of this table until a vendor's stable, versioned link is
/// confirmed via the probe harness — the table started empty and has only ever
/// grown that way. Shipping an unverified recipe risks a
/// false "update available", which this source must never produce; leaving an app
/// out simply means it stays "unknown", which is the correct, honest default.
///
/// Every recipe in `Recipes/` (listed by `AppRecipeIndex`) was verified by probing the live endpoint and confirming
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
/// (`Recipes/com-google-android-studio.swift`) — Stable to developer.android.com/studio, Canary/Beta to the official
/// releases-list JSON (compared on the `build` field via `versionIsBuild`).
///
/// GitHub-released apps are handled by `GitHubReleasesSource`, not here.
///
/// Two more unfeasibles, observed 2026-08-30 and recorded to stop rediscovery:
/// - **Trae / Trae CN** (`com.trae.app`): the update manifest
///   (`api.trae.ai/icube/api/v1/native/version/trae/latest`) carries NO version
///   field — only CDN release-train numbers (`…/releases/stable/2.3.73738/…`)
///   baked into download URLs, while the installed bundle reports a different
///   namespace (`CFBundleShortVersionString 3.5.91` for train 2.3.73738).
///   Homebrew's cask livecheck grabs the train number too, but Homebrew never
///   compares it to the bundle. No public endpoint yields the app version, so
///   a probe would compare across namespaces — same class as Brave/Feishu.
/// - **Hermes (Nous Research desktop)**: the distributed artifact
///   (`Hermes-Setup.dmg`) is a 0.0.1 bootstrap stub
///   (`com.nousresearch.hermes.setup`) that downloads the real app elsewhere;
///   the real bundle id/version cannot be observed without running the
///   installer. The homepage carries the version (0.20.6, Homebrew's livecheck
///   scrapes it) but there is no registry key to hang it on until a real
///   install is observed.
public enum VendorProbeRegistry {

    /// Whether the recipe with this id orders its builds by a `BuildLineage` — the
    /// one fact `duo verify` needs about a finding's version before comparing it
    /// with an earlier sweep's, since on such a recipe the version is a hash
    /// `VersionComparator` cannot order.
    public static func ordersByLineage(recipeID: String) -> Bool {
        recipes.contains { $0.recipeID == recipeID && $0.buildLineage != nil }
    }

    /// The same question asked by app rather than by recipe — for a check keyed on
    /// the bundle (the changelog sweep) that has no probe recipe id to hand.
    public static func ordersByLineage(bundleID: String) -> Bool {
        recipes.contains { $0.bundleID == bundleID && $0.buildLineage != nil }
    }

    // TRAE is deliberately absent here. Its official manifest exposes only
    // the packaging line `2.3.61406`, while the exact dmg at that manifest URL
    // reports CFBundleShortVersionString/CFBundleVersion `3.5.81`. The embedded
    // product.json ties the two together (`tronBuildVersion` / `appVersion`),
    // but the network response never publishes `appVersion`; neither string can
    // safely be compared to the installed Info.plist. See the persisted audit.

    // Deliberately NOT covered — Android File Transfer
    // (`com.google.android.mtpviewer`). `…/mtp/current/AndroidFileTransfer.dmg`
    // does 302 to a versioned path, but the number there is `5071136` while the
    // shipped bundle reports `1.0.12` (build `1.0.507.1136`) — the redirect
    // squashes the build's last two segments together. Neither string can be
    // compared with the other, so a recipe would report a permanent update.
    // (Homebrew's cask uses 5071136 as its own bookkeeping version, which is
    // what makes this look workable from the outside.)
    public static let recipes: [VendorProbeRecipe] = AppRecipeIndex.all.flatMap(\.probes)

    /// The `"beta"` numbers a user on `channel` accepts, since the ladder means
    /// each level subsumes the more stable ones below it.
    ///
    /// A switch that refuses what it has not been taught, NOT a ternary with a
    /// catch-all. The catch-all is what this looked like first, and its else
    /// branch built `[0-2]` — the guinea-pig set — for every channel that is not
    /// beta, `.stable` included. Nothing would have caught that: the tests only
    /// ask for the two tracks the call site passes, and
    /// `RecipeSanity.crossChannelArtifact` returns early on a recipe with no
    /// install spec. The next edit that reaches it is an obvious one — putting
    /// stable on this endpoint too, or adding `.rc` — and it would have offered a
    /// guinea pig build to every stable user, in the one direction the channel
    /// gate exists to prevent.
    static func windscribeTrackSet(_ channel: ReleaseChannel) -> String? {
        switch channel {
        case .beta: return "[01]"           // release + beta
        case .guineaPig: return "[0-2]"     // release + beta + guinea pig
        default: return nil
        }
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
    static func workBuddyRecipe(
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
    static func sourceForgeMacRecipe(
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
