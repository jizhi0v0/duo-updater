import Foundation

/// Which release a rule may offer once the list has been fetched.
///
/// `.newest` is the historic behaviour and what every rule but one uses: walk
/// newest-first and take the first release the patterns accept.
///
/// `.installedMajorLineOrNewestStable` exists for a vendor whose prereleases are
/// not a parallel TRAIN but a stage every release passes through. UTM is the
/// measured case: of its 131 releases, 78 carry `prerelease: true`, and each
/// minor line ships previews first and then GRADUATES at a higher patch number
/// (`v4.7.0…v4.7.3` are "(Beta)", `v4.7.4`/`v4.7.5` are not). Two consequences
/// follow, and they pull in opposite directions:
///
///   * Offering such an install "the newest prerelease" strands it the moment
///     its own line graduates — measured across the real history, that happened
///     **14 times**, the worst window running 2024-11-27 → 2025-07-09 with four
///     stable releases published into the silence.
///   * Offering it "the newest release of any kind" walks a `v4.7.3` install
///     onto a `v5.0.5` preview of a line that has not shipped at all, when the
///     answer it wants is its own line's `v4.7.5`.
///
/// So the candidate is `max(newest release in the installed version's major
/// line, newest stable release)`. Both halves are load-bearing: the first is
/// what carries a preview install to its own graduation, the second is what
/// keeps an install on a long-abandoned line from being pinned there forever.
///
/// **Major, not minor** — a deliberate choice, and the two differ only in a
/// shape UTM has never produced. Replaying all 131 releases: a preview line only
/// ever opens after the previous one graduated, so "newest in major 4" and
/// "newest in 4.7" have never disagreed. They would if a `v4.8.0 (Beta)` opened
/// while a `v4.7.3 (Beta)` install was still out there: major carries that
/// install onto the new preview line, minor holds it at `v4.7.5`. Major is
/// chosen because a preview install that has not moved to the newer preview line
/// is the case that goes stale — the "newest stable" half already guarantees it
/// can never be worse off than a stable install. `ceilingPrefersTheNewerPreviewLineWithinTheMajor`
/// pins this so it stays a decision rather than an accident.
public enum GitHubCandidateScope: String, Sendable, Equatable {
    case newest
    case installedMajorLineOrNewestStable
}

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
    /// `per_page` for the list fetch. Read by `usePrereleases` rules on every
    /// check — and, less obviously, by a `usePrereleases == false` rule too:
    /// `resolve()` falls back to the LIST endpoint when the newest release
    /// carries no macOS asset, and that fallback then applies `stableOnly`, so
    /// the effective walk-back window is (this page size − prereleases on the
    /// page) against `maxReleasesWithoutMacOSAsset`. Shrinking it on a stable
    /// rule therefore narrows a safety margin whose failure mode is a confident
    /// "up to date" on a stale version. It is not ignored anywhere.
    ///
    /// Defaults to 20, the size every rule used before this field existed.
    /// GitHub's `body` (release notes prose) is dead weight here — the version
    /// probe never reads it — and on six installed `usePrereleases` repos it was
    /// measured at 3.0%–47.4% of each response's JSON (re-measured 2026-09-05; an
    /// earlier note said 6%–51%, and the lower bound was out by a factor of two). Two separate figures, and an
    /// earlier version of this comment wrongly presented one as a subset of the
    /// other: **421 KB** is what those six cost per scan round as counted in the
    /// request log, **481 KB** is the sum of their six responses fetched once
    /// each at `per_page=20` (2026-09-04, real responses, **gzipped
    /// wire bytes** — the same unit the request log counts. Re-measure with
    /// `curl --compressed`; identity bytes run 4-10x larger and reading these
    /// as identity would look like a regression that isn't there).
    /// Shrinking the page cuts that dead weight, but ONLY as far as the specific
    /// rule's tag pattern has been measured to need: too small and the release
    /// this rule is looking for scrolls off the page, which reads as "no update"
    /// rather than as an error.
    ///
    /// ⚠️ **Running out of page is not dangerous, and a previous version of this
    /// comment said it was.** It claimed the walk past assetless releases
    /// (`maxReleasesWithoutMacOSAsset`) had to fit inside the page or the early
    /// stop would read as a confident "up to date", and every size was inflated
    /// by 5 on that basis. Both halves were wrong:
    ///
    /// - The guard's `break` and simply exhausting the page **land on the same
    ///   exit** — `recordMiss` plus `Resolution(remote: nil)`, which surfaces as
    ///   `.unknown` and a health miss, not as "up to date". Read the tail of
    ///   `resolve()`: there is one `if !skippedForMissingAsset.isEmpty` and both
    ///   paths reach it.
    /// - The arithmetic didn't hold either. `skippedForMissingAsset` only counts
    ///   releases the version pattern ACCEPTS, so reaching 5 of them takes about
    ///   `1 + 5 × gap` entries, not `gap + 5`. At Bitwarden's gap of 7 that is 36.
    ///
    /// And the direction is backwards: releases come newest-first, so a smaller
    /// page can only fail to find something, while a LARGER one is the side that
    /// can hand back an older release as "the latest" — which is the risk
    /// `maxReleasesWithoutMacOSAsset` exists to bound in the first place. The
    /// sizes are back to the measured tag depth; the inflation cost 33.8 KB a
    /// round (17% of the saving) for a hazard that isn't there. Set this only after walking the rule's own
    /// history (`versionPattern`, and for `.installedMajorLineOrNewestStable`,
    /// the ceiling logic in `lineAnchoredCeiling` — its depth requirement is NOT
    /// "first match" and must be measured separately) — see the per-rule
    /// comments in `GitHubReleaseRegistry.rules` for what was measured and when.
    public let listPageSize: Int
    /// Regex applied to a release's `tag_name`; capture group 1 is the version
    /// (e.g. strip a leading `v`, or a `.stable_00` suffix).
    public let versionPattern: String

    /// How to choose among the releases this rule fetched. `.newest` for every
    /// rule but UTM beta — see `GitHubCandidateScope` for why that one differs
    /// and what it measured.
    public let candidateScope: GitHubCandidateScope

    /// Whether a `usePrereleases` rule with `.newest` scope first asks for a
    /// page of ONE release and only pays for its full `listPageSize` page when
    /// that one release cannot answer (wrong tag shape, draft, no macOS asset).
    /// The list endpoint cannot be revalidated cheaply — it sends no
    /// `Last-Modified` and its `ETag` churns with download counters, see
    /// `GitHubConditionalCache` — so the newest release is the whole page
    /// almost every round, and a page of one is 3-18 KB where the full page is
    /// 17-75 KB (five installed repos, gzipped, 2026-09-05). Ignored for stable
    /// rules (they read `/releases/latest`, already one release) and for
    /// `.installedMajorLineOrNewestStable` (its answer is a window, not the
    /// newest row). Set false for a rule whose newest release is usually NOT
    /// the one it wants — Bitwarden's monorepo interleaves web, CLI and browser
    /// releases ahead of the desktop tag — since the probe then only adds a
    /// request. Defaults to true.
    public let probesNewestFirst: Bool

    /// Prefix that turns the installed marketing version into its exact GitHub
    /// tag (`"v"` + `5.0.5` → `v5.0.5`). Non-nil only when stable and prerelease
    /// builds share every local identity signal. The source looks up that exact
    /// release and uses GitHub's `prerelease` bit to decide which rule the
    /// installed copy belongs to. A missing or unmatched release claims no
    /// channel and falls back to the stable rule — the copy loses its badge,
    /// not its row.
    ///
    /// At most one rule per bundle id may set this — `atMostOneDiscoverableRulePerBundleID`
    /// enforces it, because at runtime a second one has no principled tiebreak.
    public let installedTagPrefix: String?

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
        listPageSize: Int = 20,
        versionPattern: String = #"v?([0-9]+(?:\.[0-9]+)+)"#,
        candidateScope: GitHubCandidateScope = .newest,
        installedTagPrefix: String? = nil,
        installAssetPattern: String? = nil,
        installerKind: VendorInstallerKind? = nil,
        channel: ReleaseChannel = .stable,
        probesNewestFirst: Bool = true
    ) {
        self.bundleID = bundleID
        self.channel = channel
        self.probesNewestFirst = probesNewestFirst
        self.owner = owner
        self.repo = repo
        self.usePrereleases = usePrereleases
        self.listPageSize = listPageSize
        self.versionPattern = versionPattern
        self.candidateScope = candidateScope
        self.installedTagPrefix = installedTagPrefix
        self.installAssetPattern = installAssetPattern
        self.installerKind = installerKind
    }

    /// Field labels deliberately kept OUT of `channelAnchorSurface` — the ones
    /// that LABEL a rule rather than decide what it reads or accepts.
    ///
    /// Same reasoning as `VendorProbeRecipe.nonAnchorFields`, and the same trap:
    /// a `.beta` rule carries the literal string "beta" in `channel`, so an
    /// anchor of `beta` would be satisfied by the mere fact it is a beta rule,
    /// forever, whatever happened upstream. `bundleID` is the same shape of
    /// tautology. Everything else is in, including fields added after this list
    /// was written — see `channelAnchorSurface`. `listPageSize` joins them for a
    /// different reason: it's a request-shaping knob (how many rows to page
    /// through), not part of which repo/tag/asset the rule accepts, so an
    /// anchor could never legitimately be pinned to its digits.
    /// `probesNewestFirst` is the same kind of knob: it changes how many rows
    /// the first request asks for, never which release or asset is accepted.
    static let nonAnchorFields: Set<String> = ["bundleID", "channel", "listPageSize", "probesNewestFirst"]

    /// Everything this rule says about WHICH repository it reads and WHICH
    /// releases and assets it will accept — the text a
    /// `ChannelArtifactProof.recipeAnchor` is matched against.
    ///
    /// Derived by reflection rather than hand-listed, for the reason the vendor
    /// side learned the hard way: a hand-written surface goes on passing while
    /// inspecting less, so nothing anywhere reads as broken the day a new field
    /// arrives and nobody adds it. `channelAnchorSurfaceCoversEveryGitHubRuleField`
    /// makes adding one a decision somebody states out loud.
    ///
    /// One line per STRING the rule holds — a field contributes as many lines as
    /// it has strings — so an anchor written with `.*` cannot straddle two
    /// unrelated values and match something nobody meant.
    ///
    /// As on the vendor side, this whole-surface join is no longer what a proof is
    /// matched against: a `.recipeAnchor` names the fields it relies on and is
    /// checked against each, via `channelAnchorSurface(ofField:)` below (issue
    /// #110). This stays as the union those field views are cut from, and as what
    /// the tests measure. Most `githubProofs` entries are provable from the
    /// resolved URL; the ones that are not carry a `.recipeAnchor` and are checked
    /// through the per-field half below, so that a rule needing an anchor cannot
    /// silently get the weaker any-field behaviour. (This comment said "no
    /// `githubProofs` entry is an anchor today" long after two of them were.)
    public var channelAnchorSurface: String {
        channelAnchorFields.flatMap(\.lines).joined(separator: "\n")
    }

    /// The anchorable fields, in declaration order, each with the lines it
    /// contributes. See `VendorProbeRecipe.channelAnchorFields` for why a proof
    /// is matched per field rather than against the join.
    public var channelAnchorFields: [(label: String, lines: [String])] {
        Mirror(reflecting: self).children.compactMap { child in
            guard let label = child.label,
                  !Self.nonAnchorFields.contains(label) else { return nil }
            return (label, Self.anchorLines(of: child.value))
        }
    }

    /// The text one named field contributes, or nil when this rule has no
    /// ANCHORABLE field by that name. Callers must treat nil as a failure: a
    /// proof pinned to a field that isn't there is a proof that cannot fail.
    public func channelAnchorSurface(ofField label: String) -> String? {
        channelAnchorFields.first { $0.label == label }
            .map { $0.lines.joined(separator: "\n") }
    }

    /// One line per string a value contains, walking into optionals and enum
    /// payloads. Never `String(describing:)` on a field that holds a string: it
    /// renders nested strings through their DEBUG description, so quotes come
    /// back escaped and an anchor written to match the real text stops matching.
    private static func anchorLines(of value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let url = value as? URL { return [url.absoluteString] }
        let mirror = Mirror(reflecting: value)
        guard !mirror.children.isEmpty else { return [String(describing: value)] }
        return mirror.children.flatMap { anchorLines(of: $0.value) }
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

        // 1. An asset explicitly built for this Mac's architecture.
        if let native = newest(among: matches, where: {
            arch.isMarked(inAssetName: $0.name)
                && !(arch == .arm64 ? HostArch.x86_64 : .arm64).isMarked(inAssetName: $0.name)
        }) { return (native.url, native.size) }

        // 2. An arch-neutral asset (a universal build, or a name with no arch
        //    marker at all) — safe for either machine. A filename that explicitly
        //    names both architectures is another spelling of universal.
        if let neutral = newest(among: matches, where: {
            arch.isMarked(inAssetName: $0.name)
                == (arch == .arm64 ? HostArch.x86_64 : .arm64).isMarked(inAssetName: $0.name)
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
        return newest(among: matches, where: { _ in true }).map { ($0.url, $0.size) }
    }

    /// The asset whose own filename ranks highest under `VersionComparator`,
    /// among those in `assets` that satisfy `predicate`. Nil when none does.
    ///
    /// Exists because "first in the list" is not "newest". A respun release keeps
    /// BOTH artifacts under the one tag — KeePassXC 2.7.11 ships
    /// `KeePassXC-2.7.11-arm64.dmg` alongside the respin
    /// `KeePassXC-2.7.11-1-arm64.dmg` — and GitHub returns assets alphabetically,
    /// which happens to put the respin first for `-1` and would put it LAST from
    /// `-2` on. Picking by position therefore installs the superseded artifact as
    /// soon as a vendor respins twice, silently: the version reported is the
    /// release's and is correct, only the file is wrong, so nothing fails and
    /// nothing warns. Same defect as the vendor-probe feed ordering fixed in #76
    /// (`VendorProbeRecipe.highestVersionedURL`), in a different source — the
    /// remedy is the same one: score each candidate by what it declares about
    /// itself and take the maximum.
    ///
    /// Comparing the WHOLE filename is what makes this safe without inventing a
    /// per-vendor respin grammar. `VersionComparator` splits a name into runs of
    /// digits and non-digits and compares run by run, so
    /// `KeePassXC-2.7.11-1-arm64.dmg` and `KeePassXC-2.7.11-arm64.dmg` agree
    /// through `2.7.11` and then weigh `1` against `arm`, where a number outranks
    /// text and the respin wins; `-2-` against `-1-` is a numeric comparison, not
    /// an alphabetical one, so a tenth respin would beat a ninth too.
    ///
    /// Nothing moves unless a name genuinely ranks higher: a single candidate is
    /// returned as-is (which is every rule in the registry on an ordinary
    /// release), and equal-ranking names keep the first-listed one, so this is
    /// the old behaviour everywhere the old behaviour was already unambiguous.
    private static func newest(
        among assets: [(name: String, url: URL, size: Int64?)],
        where predicate: ((name: String, url: URL, size: Int64?)) -> Bool
    ) -> (name: String, url: URL, size: Int64?)? {
        var best: (name: String, url: URL, size: Int64?)?
        for asset in assets where predicate(asset) {
            guard let current = best else { best = asset; continue }
            if VersionComparator.isNewer(asset.name, than: current.name) { best = asset }
        }
        return best
    }

    /// Does this release carry *any* asset this rule would install?
    ///
    /// Deliberately a plain pattern match, NOT `installableAsset`. That selector
    /// can answer nil for an architecture reason — everything matched is built
    /// for the other arch and this Mac can't run it — and using it as the gate
    /// would make an Intel Mac walk past a release that genuinely ships the
    /// macOS build, then report an older version as the newest one. The two
    /// questions are separate: *does this release exist for macOS* (here) and
    /// *which file do we hand the installer* (there).
    static func carriesInstallableAsset(
        from assets: [(name: String, url: URL, size: Int64?)], matching pattern: String
    ) -> Bool {
        assets.contains { $0.name.range(of: pattern, options: .regularExpression) != nil }
    }

    /// True when this release ships a macOS asset matching `pattern`, but every
    /// such asset targets an architecture this host cannot run — as opposed to
    /// shipping no macOS asset at all. The two need different handling: no
    /// asset is a genuine recipe problem (the vendor renamed or dropped the
    /// macOS artifact), worth counting against recipe health and worth walking
    /// back from. An architecture-only miss is not a recipe problem — the
    /// vendor did ship a macOS build, this Mac just can't launch it (an
    /// Intel-only build on an Apple-silicon Mac once Rosetta stops covering
    /// apps from macOS 28, or an arm64-only build on an Intel Mac, which has
    /// never been runnable) — so it should read as "nothing to offer" rather
    /// than flag the recipe as broken.
    static func isArchIncompatibleOnly(
        assets: [(name: String, url: URL, size: Int64?)],
        matching pattern: String,
        preferring arch: HostArch,
        allowingIntelTranslation canRunIntel: Bool
    ) -> Bool {
        carriesInstallableAsset(from: assets, matching: pattern)
            && installableAsset(
                from: assets, matching: pattern,
                preferring: arch, allowingIntelTranslation: canRunIntel) == nil
    }

    var slug: String { "\(owner)/\(repo)" }
}

public extension GitHubReleaseRule {
    /// Stable sweep key for this rule — the id the baseline files it under.
    ///
    /// Public and defined once because two callers need to agree on it: the
    /// sweep, which writes rows under this key, and `Baseline.prune`, which
    /// decides a row is orphaned when no rule produces its key. A second,
    /// separately-maintained spelling of this string would make the prune delete
    /// live rows the first time the two drifted.
    var recipeID: String { "github:\(slug):\(channel.rawValue)" }
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
    /// applying).
    enum GitHubError: LocalizedError {
        case badStatus(Int)
        /// The budget-exhausted subset of 403/429 — see `statusError(_:rateLimitRemaining:)`
        /// for which 403s qualify. Split out because the OTHER 403s (a repo gone
        /// private, deleted, or renamed away; a token whose scopes don't cover it)
        /// are not waiting-out-the-hour problems: reported as the rate limit they
        /// drove a banner telling the user to add a token, which is advice that
        /// cannot work, on a row that will still be broken in an hour.
        case rateLimited(Int)

        /// The status either case carries, so a caller that only needs the code
        /// doesn't have to know which one it got.
        var statusCode: Int {
            switch self {
            case .badStatus(let code), .rateLimited(let code): return code
            }
        }

        var errorDescription: String? {
            switch self {
            case .rateLimited:
                // The phrase "rate limit" is the contract `UpdateStatus.isRateLimitError`
                // matches on to drive the rate-limit UI nudges — keep it in the string,
                // and keep it OUT of the other case's.
                return "GitHub rate limit reached — retry shortly"
            case .badStatus(403):
                return "GitHub returned 403 (forbidden) — repo private, removed, or token lacks scope"
            case .badStatus(let code):
                return "GitHub returned HTTP \(code)"
            }
        }
    }

    /// Which error a non-2xx status becomes.
    ///
    /// 429 is always the limit. A 403 is the limit only when the response says the
    /// budget is gone: `X-RateLimit-Remaining: 0`, or no such header at all —
    /// GitHub omits it on rejections that never reached the API, and "no evidence"
    /// must not silently become "not rate limited", which is the one case where the
    /// nudge is the whole explanation. A 403 arriving with budget left is an access
    /// problem and says so.
    static func statusError(_ code: Int, rateLimitRemaining: String?) -> GitHubError {
        guard code == 403 else { return code == 429 ? .rateLimited(code) : .badStatus(code) }
        guard let remaining = rateLimitRemaining, let left = Int(remaining) else {
            return .rateLimited(code)
        }
        return left <= 0 ? .rateLimited(code) : .badStatus(code)
    }

    /// Keyed by bundle id → the rules for that id, one per release channel.
    /// Most apps have a single (stable) rule; channels that share a bundle id
    /// list several and are disambiguated by the installed app's detected channel.
    private let rules: [String: [GitHubReleaseRule]]
    private let session: URLSession
    private let token: String?
    /// Where a proven channel is remembered between checks. nil means "prove it
    /// every time and persist nothing" — the default, so a test that doesn't
    /// inject one cannot write into the user's real file. `SourceStack` passes
    /// the shared instance, and passes the SAME instance to `UpdateChecker` so a
    /// failed check can still read what an earlier one proved.
    private let channelStore: ResolvedChannelStore?
    /// Where a validator (`Last-Modified` / `ETag` + raw body) for
    /// `/releases/latest` and `/releases?per_page=<listPageSize>` is remembered
    /// so `fetchReleases` can revalidate itself — `If-Modified-Since` alone
    /// wherever the response had a `Last-Modified` — instead of relying on
    /// `URLCache`, whose `If-None-Match` GitHub answers with a full 200 as soon
    /// as a download counter moves. See `GitHubConditionalCache`'s doc comment
    /// for the measurement.
    /// nil (the default) means "always fetch unconditionally, persist
    /// nothing" — same convention as `channelStore`, so the many tests that
    /// construct a source directly cannot accidentally write into the real
    /// file. `SourceStack.make` and `duo verify`'s GitHub sweep wire in
    /// `GitHubConditionalCache.shared`.
    private let validatorCache: GitHubConditionalCache?

    public init(
        rules: [GitHubReleaseRule] = GitHubReleaseRegistry.rules,
        token: String? = nil,
        session: URLSession = .updates,
        channelStore: ResolvedChannelStore? = nil,
        validatorCache: GitHubConditionalCache? = nil
    ) {
        self.rules = Dictionary(grouping: rules, by: { $0.bundleID })
        self.token = token
        self.session = session
        self.channelStore = channelStore
        self.validatorCache = validatorCache
    }

    /// The `/releases/latest` and `/releases?per_page=<listPageSize>` URLs
    /// every rule in this instance's registry could ask for — i.e. exactly the
    /// endpoints `GitHubConditionalCache.prune(keeping:)` is allowed to keep.
    /// Two per rule regardless of which one that rule actually uses
    /// (`usePrereleases` picks one for `resolve`, but `channelDiscoveryProbe`
    /// always fetches the list endpoint for a discoverable rule, so both must
    /// survive pruning for every rule to avoid punishing the diagnostic path
    /// for a cache miss on every single sweep).
    ///
    /// The list URL must be built with the rule's own `listPageSize`, byte for
    /// byte the way `fetchReleases` builds it: a first draft hard-coded
    /// `per_page=20` here after `listPageSize` had made it per-rule, so every
    /// rule with a smaller page had its list entry stored and then pruned on
    /// the very same fetch — a cache that could never hit, with no error
    /// anywhere. `validNonTagEndpointsFollowEachRulesListPageSize` pins it.
    ///
    /// Deliberately excludes `/releases/tags/<tag>` — see `GitHubConditionalCache`'s
    /// doc comment for why that endpoint is not cached at all. This is the set
    /// `prune(keeping:)` is called with, so it doubles as a second, independent
    /// backstop: even if `fetchReleases`'s own `tag == nil` gate were ever
    /// mistakenly dropped, a tag entry that slipped into the store would still
    /// be deleted the next time any rule's endpoint is fetched, because it can
    /// never appear in this set. `internal` (not `private`) so
    /// `GitHubConditionalCacheTests` can assert on it directly.
    var validNonTagEndpoints: Set<String> {
        var out = Set<String>()
        for rule in rules.values.flatMap({ $0 }) {
            out.insert(Self.latestEndpoint(rule))
            out.insert(Self.listEndpoint(rule, pageSize: rule.listPageSize))
            // The probe page is a third endpoint with its own validator; a rule
            // that never probes never fetches it, so it must not be kept either
            // (a stale one-row body would sit on disk forever).
            if Self.probesNewestFirst(rule) {
                out.insert(Self.listEndpoint(rule, pageSize: Self.newestProbePageSize))
            }
        }
        return out
    }

    /// The one place both URL shapes are spelled out. `fetchReleases` requests
    /// exactly these strings and `validNonTagEndpoints` prunes against exactly
    /// these strings; the two used to be written twice and drifted (see that
    /// property's doc comment).
    static func latestEndpoint(_ rule: GitHubReleaseRule) -> String {
        "https://api.github.com/repos/\(rule.slug)/releases/latest"
    }
    static func listEndpoint(_ rule: GitHubReleaseRule, pageSize: Int) -> String {
        "https://api.github.com/repos/\(rule.slug)/releases?per_page=\(pageSize)"
    }

    /// One row. The newest release IS the answer for a `.newest` prerelease
    /// rule on every round that does not land between a platform-partial
    /// release and the next real one, so one row is the page that pays for
    /// itself; anything larger just moves the fallback threshold.
    static let newestProbePageSize = 1

    /// Whether `resolve` may open with a one-row page for this rule at all —
    /// the static half of the decision. The dynamic half (has the full page
    /// been fetched once, so the release history is seeded) lives in
    /// `newestProbeSize(for:)`.
    static func probesNewestFirst(_ rule: GitHubReleaseRule) -> Bool {
        rule.usePrereleases && rule.candidateScope == .newest && rule.probesNewestFirst
    }

    /// The page size `resolve` opens with, or nil to fetch the rule's full page
    /// straight away.
    ///
    /// The full page is fetched at least once before any probing, because it
    /// is also the release HISTORY: `resolve` back-fills the timeline from
    /// every release on the page, and the timeline records a version at first
    /// sighting and keeps it (`ReleaseTimelineStore.record`), so one full page
    /// seeds the history and one-row pages afterwards lose nothing already
    /// recorded. "Fetched at least once" is read off the validator store — a
    /// memo for the full-page endpoint under the current credential — which
    /// is the only durable record of that. With no store wired in (tests, and
    /// a source constructed directly) there is nothing to seed, so probing
    /// starts immediately.
    ///
    /// What a one-row page does forgo, by design: a release that lands
    /// BETWEEN two rounds and is no longer the newest by the next one never
    /// reaches the timeline. At a five-minute interval that needs two releases
    /// in five minutes; at the six-hour default it is likelier. The version
    /// shown is unaffected — the newest release is on both pages.
    private func newestProbeSize(for rule: GitHubReleaseRule) async -> Int? {
        guard Self.probesNewestFirst(rule) else { return nil }
        if let validatorCache {
            let seeded = await validatorCache.validator(
                for: Self.listEndpoint(rule, pageSize: rule.listPageSize),
                authFingerprint: GitHubConditionalCache.authFingerprint(token)) != nil
            guard seeded else { return nil }
        }
        return Self.newestProbePageSize
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // Toolbox-managed apps update through Toolbox — never offer a GitHub
        // artifact over a Toolbox install (no cross-channel mixing).
        guard !app.isToolboxManaged else { return nil }
        // Same reasoning, different owner: a Mac App Store copy updates through
        // the store, and the GitHub build of the same app is a *different
        // distribution* that happens to share a bundle id — Developer ID signed,
        // unsandboxed, no receipt. Swapping one in would break the store's update
        // path and the app's own entitlements, and the version numbers don't even
        // have to line up (the store review lag routinely puts them a release
        // apart). LocalSend ships both, which is how this surfaced.
        //
        // The gate has to live here rather than in source ordering: the App Store
        // source going first only wins while it answers, and it misses often
        // enough (region-locked storefront, a lookup that 404s) that "GitHub as
        // the accidental fallback" is a real state, not a hypothetical one.
        guard !app.isMASApp else {
            Log.source.info(
                "GitHub skip \(app.bundleID ?? "?", privacy: .public): App Store copy, the store owns its updates")
            return nil
        }
        guard let bundleID = app.bundleID, let candidates = rules[bundleID] else {
            return nil  // no rule for this app — not applicable
        }
        // Channel gate: pick the rule whose channel matches the installed app's,
        // and refuse if none does. When channels share a bundle id, this selects
        // the right endpoint; when only a stable rule exists, a detected
        // nightly/beta install finds no match and is skipped rather than offered
        // a cross-channel build.
        guard let detectedRule = candidates.first(where: { $0.channel == app.releaseChannel }) else {
            Log.source.info(
                "GitHub skip \(bundleID, privacy: .public): no rule for app channel \(app.releaseChannel.rawValue, privacy: .public)")
            return nil
        }
        let rule: GitHubReleaseRule
        if detectedRule.channel == .stable, !app.channelIsAuthoritative,
           candidates.contains(where: { $0.channel != .stable && $0.installedTagPrefix != nil }) {
            guard let discovered = try await ruleFromInstalledRelease(
                for: app, candidates: candidates)
            else { return nil }
            rule = discovered
        } else {
            rule = detectedRule
        }
        // A rule exists: let a fetch failure throw, so the checker turns it into
        // a retryable `.error` row rather than swallowing it into a nil that's
        // indistinguishable from "no source for this app".
        return try await resolve(rule, anchoredTo: app.shortVersion).remote
    }

    /// Resolve an otherwise-undetectable channel from the exact release that
    /// produced the installed version. UTM is the motivating case: Stable and
    /// Beta have one bundle id, one app name, plain numeric versions, and the
    /// same `UTM.dmg` asset name. The package cannot name its train, but the
    /// exact GitHub release for tag `v<installed version>` does.
    ///
    /// Note what this decides and what it does NOT. It decides which RULE the
    /// installed copy belongs to — i.e. the identity of the copy on disk. It does
    /// not decide which release that rule may then offer; a preview install is
    /// not thereby confined to previews (`GitHubCandidateScope` covers that, and
    /// explains why confining it was wrong).
    ///
    /// If the exact tag disappears, is a draft, or the response no longer carries
    /// the release-state fields at all, this claims NO channel and answers on the
    /// stable rule — losing the copy its badge, not its row (see the long note at
    /// the fallback itself for why the row matters) — and forgets any stored
    /// proof, so a channel cannot outlive the evidence for it. It never
    /// manufactures a channel from a nearby release.
    private func ruleFromInstalledRelease(
        for app: InstalledApp, candidates: [GitHubReleaseRule]
    ) async throws -> GitHubReleaseRule? {
        let discoverable = candidates.filter {
            $0.channel != .stable && $0.installedTagPrefix != nil
        }
        // A second discoverable rule has no principled tiebreak, and returning nil
        // here would take the STABLE users of this bundle id down with it — the
        // whole app would vanish from the list on the strength of someone adding
        // a rule. `atMostOneDiscoverableRulePerBundleID` fails the build for this,
        // so the runtime path only has to degrade honestly.
        guard discoverable.count == 1, let rule = discoverable.first,
              let prefix = rule.installedTagPrefix
        else {
            // Reachable only via the registry invariant being broken. Note this
            // returns the locally detected rule, which for every caller of this
            // function is the stable one — no path out of here is nil.
            Log.source.error(
                "GitHub \(app.bundleID ?? "?", privacy: .public): \(discoverable.count, privacy: .public) discoverable rules, expected exactly 1 — falling back to the locally detected channel")
            return candidates.first { $0.channel == app.releaseChannel }
        }

        // Not proving a channel must cost the app its BADGE, not its row. An
        // unprovable copy still has a perfectly good answer available — the newest
        // stable release, which is what every install got before this mechanism
        // existed — and returning nil instead drops GitHub as a source entirely:
        // UTM has no Sparkle feed and its casks only answer when brew installed
        // them, so the row falls all the way through to `.unknown` and silently
        // stops offering the update it could have had.
        //
        // This is not hypothetical. `v3.1.3` and `v3.0.4` do not exist upstream
        // (they were re-cut as `v3.1.3-2` / `v3.0.4-2`), and the tags before
        // `v2.1.0` — `v2.0b7`, `v1.0-rc6`, `v0.2-fakesign` — cannot form a tag
        // this rule accepts at all. Every one of those installs would have gone
        // dark.
        //
        // Offering stable to a copy that might be a preview is safe in this
        // direction: it can only ever be the newest stable release, so a preview
        // install newer than it resolves as lagging (`laggingRemoteVersion`),
        // never as a downgrade to install.
        let stableFallback = candidates.first { $0.channel == .stable }

        guard let installed = app.shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !installed.isEmpty,
              // Validate BEFORE spending a request. A hand-built or renamed copy
              // whose version can never form a tag this rule would accept would
              // otherwise cost one guaranteed 404 on every single check.
              VendorProbeRecipe.extractVersion(from: prefix + installed, pattern: rule.versionPattern)
                == installed
        else {
            Log.source.info(
                "GitHub \(app.bundleID ?? "?", privacy: .public): installed version cannot form a tag for this rule — answering on the stable rule rather than dropping the row")
            return stableFallback
        }

        // A proof is about one copy at one version, so a stored one is as good as
        // a fresh lookup until that copy changes — and skipping the lookup is what
        // keeps the steady-state cost at one request per check.
        if let remembered = await channelStore?.channel(for: app) {
            return candidates.first { $0.channel == remembered }
                ?? candidates.first { $0.channel == app.releaseChannel }
        }

        let tag = prefix + installed
        // nil here is any of: the 404 `fetchReleases` translates for an exact-tag
        // lookup, an unbuildable URL, a non-HTTP response, or a 200 whose body did
        // not decode to a release. They differ in cause and not in consequence —
        // none of them proves a channel — and a status worth retrying (403, 5xx)
        // never reaches this line: it throws.
        guard let release = try await fetchReleases(rule, list: false, tag: tag)?.first,
              // An explicit `false` and a response that stopped carrying the field
              // are different answers; only the first one means "stable".
              release.hasExplicitReleaseState,
              !release.isDraft
        else {
            Log.source.info(
                "GitHub \(app.bundleID ?? "?", privacy: .public): exact installed release \(tag, privacy: .public) could not prove a channel — answering on the stable rule rather than dropping the row")
            await channelStore?.forget(app)
            return stableFallback
        }

        let proven: ReleaseChannel = release.isPrerelease ? rule.channel : .stable
        Log.source.info(
            "GitHub \(app.bundleID ?? "?", privacy: .public): installed tag \(tag, privacy: .public) proves \(proven.rawValue, privacy: .public)")
        await channelStore?.record(proven, for: app)
        return candidates.first { $0.channel == proven }
    }

    /// Run one rule and report everything that happened — the counterpart to
    /// `VendorProbeSource.probeDiagnostic`, so an automated sweep can judge
    /// GitHub rules by the same taxonomy as vendor recipes.
    ///
    /// Kept on the source, not in the sweeping tool, so it shares this type's
    /// endpoint construction, token handling and cache policy. The "body sample"
    /// is the tag list — for a GitHub rule the tags *are* the surface a version
    /// pattern is written against, and they're what you need to repair one.
    /// - anchoredTo: stands in for the installed copy for a line-anchored rule.
    ///   `duo verify` passes the version of the copy on the sweeping machine when
    ///   there is one; otherwise this falls back to the newest tag, and the
    ///   ceiling is then trivially that tag — i.e. **the sweep does not exercise
    ///   the line-anchoring algorithm**, and is not meant to. What it exercises
    ///   is the live contract the algorithm depends on: that the exact-tag
    ///   endpoint still answers and still carries the release-state fields. The
    ///   algorithm itself is pinned by `lineAnchoredCeiling`'s unit tests, which
    ///   can put an install anywhere in the history instead of only at the top.
    public func resolveDiagnostic(
        _ rule: GitHubReleaseRule, anchoredTo installedVersion: String? = nil
    ) async -> ProbeOutcome {
        await resolveDiagnostic(
            rule, anchoredTo: installedVersion, preferring: .current,
            allowingIntelTranslation: HostArch.canRunIntelBuilds)
    }

    /// Re-walk the channel-discovery mechanism the way a real install does:
    /// take the newest release this rule would consider, ask for it by exact tag,
    /// and require the answer to still carry the fields the decision reads.
    ///
    /// Deliberately anchored to a tag taken from the LIVE list rather than to a
    /// version written down here: a constant would keep passing after the vendor
    /// moved on, which is the failure this probe exists to prevent.
    /// Deliberately `throws` rather than catching: a 403 from the shared rate
    /// limit or a dropped connection is not a broken recipe, and swallowing it
    /// into `channelDiscoveryBroken` would file an issue against UTM every time
    /// the hour's budget ran out. Let those reach `resolveDiagnostic`'s existing
    /// mapping, which already sorts a status code into infra vs recipe. What this
    /// returns is only the failures that ARE about this mechanism.
    ///
    /// `list` is the page this probe fetched, handed back so `resolveDiagnostic`
    /// can give it to `resolve` instead of asking GitHub for the identical URL a
    /// second time. Returned rather than cached because the page is only reusable
    /// for a rule that reads the list endpoint at all (`usePrereleases`), and that
    /// condition belongs to the caller.
    func channelDiscoveryProbe(
        _ rule: GitHubReleaseRule
    ) async throws -> (
        failure: ProbeFailure?, provenVersion: String?, tags: [String], list: [Release]
    ) {
        guard let prefix = rule.installedTagPrefix else { return (nil, nil, [], []) }
        guard let list = try await fetchReleases(rule, list: true) else {
            return (.channelDiscoveryBroken("could not fetch the releases list"), nil, [], [])
        }
        let tags = list.map(\.tag)
        guard let newest = list.first(where: { release in
            !release.isDraft
                && VendorProbeRecipe.extractVersion(
                    from: release.tag, pattern: rule.versionPattern) != nil
        }),
        let version = VendorProbeRecipe.extractVersion(
            from: newest.tag, pattern: rule.versionPattern)
        else {
            return (.channelDiscoveryBroken(
                "no release tag matched the version pattern, so no exact tag can be built"),
                nil, tags, list)
        }

        let tag = prefix + version
        guard let exact = try await fetchReleases(rule, list: false, tag: tag)?.first else {
            // `fetchReleases` turns a 404 on an exact-tag lookup into nil — the
            // one status that really does mean "this mechanism cannot classify
            // an install on this version".
            return (.channelDiscoveryBroken(
                "exact-tag lookup for \(tag) returned nothing — an install on this version could not be classified"),
                nil, tags, list)
        }
        guard exact.hasExplicitReleaseState else {
            return (.channelDiscoveryBroken(
                "\(tag) no longer carries both `prerelease` and `draft`; channel identification reads those fields"),
                nil, tags, list)
        }
        guard VendorProbeRecipe.extractVersion(
            from: exact.tag, pattern: rule.versionPattern) == version
        else {
            return (.channelDiscoveryBroken(
                "\(tag) resolved to a different tag (\(exact.tag))"), nil, tags, list)
        }
        return (nil, version, tags, list)
    }

    /// Host parameters are injectable for the architecture-only diagnostic
    /// regression tests; production callers use `resolveDiagnostic(_:)` above.
    func resolveDiagnostic(
        _ rule: GitHubReleaseRule,
        anchoredTo installedVersion: String? = nil,
        preferring hostArch: HostArch,
        allowingIntelTranslation canRunIntel: Bool
    ) async -> ProbeOutcome {
        let started = DispatchTime.now()
        func elapsed() -> Int {
            Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
        }
        func outcome(
            remote: RemoteVersion?, failure: ProbeFailure?, tags: [String] = [], status: Int? = nil
        ) -> ProbeOutcome {
            ProbeOutcome(
                recipeID: rule.recipeID,
                bundleID: rule.bundleID, channel: rule.channel,
                remote: remote, failure: failure, httpStatus: status,
                bodySample: tags.isEmpty ? nil : tags.joined(separator: "\n"),
                elapsedMs: elapsed())
        }

        do {
            // A rule that identifies installs by exact tag is TWO mechanisms, and
            // only one of them is on the path `resolve` walks. Left alone, a dead
            // `/releases/tags/…` endpoint would keep this diagnostic green while
            // every real install of the app dropped out of the user's list — the
            // sweep would be measuring an algorithm nobody runs. So probe it here,
            // and let the anchor for the line-anchored resolve below come out of
            // the same lookup rather than from a hand-maintained constant.
            var anchor = installedVersion
            var discovered: [Release]?
            if rule.installedTagPrefix != nil {
                let discovery = try await channelDiscoveryProbe(rule)
                if let failure = discovery.failure {
                    return outcome(remote: nil, failure: failure, tags: discovery.tags)
                }
                anchor = anchor ?? discovery.provenVersion
                // The probe just fetched the rule's full list page, and for a rule
                // that takes its releases from the list endpoint that is the very
                // page `resolve` is about to ask for — same URL, same page size.
                // Hand it over instead of buying it twice: a conditional GET can't
                // save the second one, because the list's `ETag` moves whenever an
                // asset's download counter does. A rule WITHOUT `usePrereleases`
                // reads `/releases/latest` instead — a different endpoint with a
                // different answer — so it must still fetch its own.
                if rule.usePrereleases { discovered = discovery.list }
            }
            let resolved = try await resolve(
                rule, anchoredTo: anchor, preferring: hostArch,
                allowingIntelTranslation: canRunIntel, reusingListPage: discovered)
            if let remote = resolved.remote {
                return outcome(remote: remote, failure: nil, tags: resolved.tags)
            }
            if resolved.archIncompatible {
                return outcome(
                    remote: nil,
                    failure: .notApplicable(
                        "the latest matching release only ships an asset this host cannot run"),
                    tags: resolved.tags)
            }
            // Fetched fine, no tag matched — the shape a tag-format change makes.
            return outcome(
                remote: nil,
                failure: .versionPatternNoMatch(
                    sampleBytes: resolved.tags.joined(separator: "\n").utf8.count),
                tags: resolved.tags)
        } catch let status as GitHubError {
            // Both cases, not just `badStatus`: a rate limit is infrastructure, and
            // the sweep sorts infra from broken recipes by the status code alone.
            return outcome(
                remote: nil, failure: .httpStatus(status.statusCode),
                status: status.statusCode)
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
    /// How many version-matching releases may lack the rule's macOS asset before
    /// we stop walking and call it a broken recipe instead of a quiet answer.
    ///
    /// Generous enough for a project that cuts several mobile-only point releases
    /// in a row, tight enough that a renamed artifact can't silently pin us to a
    /// year-old version.
    static let maxReleasesWithoutMacOSAsset = 5

    /// One GitHub Releases fetch, decoded. nil means the endpoint URL was
    /// unbuildable, the response wasn't HTTP, or an exact-tag discovery got a
    /// 404; other bad statuses throw so the row surfaces a retryable error rather
    /// than a dead "unknown".
    ///
    /// For the two non-tag endpoints (`/releases/latest`, `/releases?per_page=N`),
    /// sends a conditional GET when `validatorCache` holds a validator for this
    /// exact endpoint + credential pair — `If-Modified-Since` alone when the
    /// stored response had a `Last-Modified`, `If-None-Match` only otherwise
    /// (`Validator.conditionalHeaders`) — and re-parses the STORED RAW BODY on
    /// a 304 — never a remembered conclusion, so a rule's `versionPattern` /
    /// `installAssetPattern` edit takes effect on the very next check even if
    /// the release hasn't moved. See `GitHubConditionalCache`'s doc comment
    /// for why `URLCache` alone doesn't revalidate these endpoints, and for why
    /// the tag lookup (`tag != nil`) never participates.
    private func fetchReleases(
        _ rule: GitHubReleaseRule, list: Bool, tag: String? = nil, pageSize: Int? = nil
    ) async throws -> [Release]? {
        let endpoint: String
        if let tag {
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/")
            guard let escaped = tag.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return nil
            }
            endpoint = "https://api.github.com/repos/\(rule.slug)/releases/tags/\(escaped)"
        } else {
            endpoint = list
                ? Self.listEndpoint(rule, pageSize: pageSize ?? rule.listPageSize)
                : Self.latestEndpoint(rule)
        }
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        // Authenticated requests get 5000/hour instead of 60/hour per IP.
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        // Conditional-GET layer. `cachedValidator` stays nil (and no
        // conditional header is sent) for the tag lookup, when no cache is
        // wired in, and on a plain cache miss — every one of those falls
        // straight through to an ordinary unconditional fetch below.
        let authFingerprint = GitHubConditionalCache.authFingerprint(token)
        var cachedValidator: GitHubConditionalCache.Validator?
        if tag == nil, let validatorCache {
            cachedValidator = await validatorCache.validator(
                for: endpoint, authFingerprint: authFingerprint)
            if let cachedValidator {
                for (name, value) in cachedValidator.conditionalHeaders {
                    request.setValue(value, forHTTPHeaderField: name)
                }
                // We are the validator now. Left on `versionFeedCachePolicy`
                // (`.reloadRevalidatingCacheData`), `URLCache` would add its own
                // `If-None-Match` from the copy it holds of the last 200 — and
                // one stale `ETag` on the wire is enough for GitHub to ignore
                // the `If-Modified-Since` next to it (RFC 7232 §6, measured; see
                // `GitHubConditionalCache`). Ignoring the local cache for this
                // one request keeps the header set exactly what
                // `conditionalHeaders` says it is.
                request.cachePolicy = .reloadIgnoringLocalCacheData
            }
        }

        Log.source.debug("GitHub GET \(endpoint, privacy: .public) (auth=\(self.token != nil, privacy: .public), conditional=\(cachedValidator != nil, privacy: .public))")
        let (data, response) = try await session.versionFeedData(
            for: request, label: "GitHub \(rule.slug)")
        guard let http = response as? HTTPURLResponse else { return nil }

        if http.statusCode == 304 {
            if let cachedValidator {
                let decoded = Self.releases(from: cachedValidator.body, list: list)
                Log.source.debug("GitHub \(rule.slug, privacy: .public): 304, served \(decoded.count, privacy: .public) release(s) from the conditional cache")
                GitHubEndpointAudit.record(
                    requestedSlug: rule.slug, requestedURL: url, response: http,
                    firstReleaseHTMLURL: decoded.first?.htmlURL, sentToken: token != nil)
                return decoded
            }
            // We only ever send a validator when `cachedValidator` is
            // non-nil, so this should be unreachable — GitHub has no validator
            // to compare against otherwise. But the rule that MUST hold
            // regardless of why it happened is: a 304 with nothing to serve it
            // from is a cache MISS, never "no update" and never an error — so
            // re-ask unconditionally rather than guess.
            Log.source.error("GitHub \(rule.slug, privacy: .public): 304 with no cached validator to serve — retrying unconditionally")
            return try await fetchReleasesUnconditionally(
                rule: rule, url: url, endpoint: endpoint, list: list, tag: tag,
                baseRequest: request, authFingerprint: authFingerprint)
        }

        let decoded = try handleSettledResponse(
            http, data: data, rule: rule, url: url, list: list, tag: tag)
        await remember(http, body: data, endpoint: endpoint, tag: tag, authFingerprint: authFingerprint)
        return decoded
    }

    /// Cache-miss fallback for the "304 but nothing to serve it from" case —
    /// see the comment at its one call site. Re-sends `baseRequest` with every
    /// conditional header removed, so the response can only be a real 2xx or a
    /// real error status, then runs it through the same settle-and-persist
    /// logic the primary path uses.
    private func fetchReleasesUnconditionally(
        rule: GitHubReleaseRule, url: URL, endpoint: String, list: Bool, tag: String?,
        baseRequest: URLRequest, authFingerprint: String
    ) async throws -> [Release]? {
        var request = baseRequest
        for name in GitHubConditionalCache.Validator.headerNames {
            request.setValue(nil, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.versionFeedData(
            for: request, label: "GitHub \(rule.slug) (conditional-cache-miss retry)")
        guard let http = response as? HTTPURLResponse else { return nil }
        let decoded = try handleSettledResponse(
            http, data: data, rule: rule, url: url, list: list, tag: tag)
        await remember(http, body: data, endpoint: endpoint, tag: tag, authFingerprint: authFingerprint)
        return decoded
    }

    /// Persist a settled 2xx's validators + raw body for a non-tag endpoint.
    /// Both `Last-Modified` and `ETag` are stored when present; which one goes
    /// on the next request is `Validator.conditionalHeaders`' decision, not
    /// this one's. One function for both fetch paths so they cannot drift on
    /// what gets remembered.
    private func remember(
        _ http: HTTPURLResponse, body: Data, endpoint: String, tag: String?, authFingerprint: String
    ) async {
        guard tag == nil, let validatorCache, (200..<300).contains(http.statusCode) else { return }
        await validatorCache.store(
            endpoint: endpoint, authFingerprint: authFingerprint,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            body: body)
        // Registry-scoped, not per-request: cheap (a Set filter over at most
        // a couple hundred entries) and keeps a retired rule's entry from
        // outliving the rule by years. See `validNonTagEndpoints`. The write
        // to disk is the store's business (`scheduleFlush`), not this
        // function's — flushing here once per 2xx rewrote a multi-megabyte
        // file several times a round.
        await validatorCache.prune(keeping: validNonTagEndpoints)
    }

    /// Interpret a non-304 HTTP response: decode a 2xx (walking releases in
    /// document order — GitHub returns newest first — is the caller's job, not
    /// this one), translate a 404 exact-tag miss into `nil`, and audit + throw
    /// everything else. Shared by the primary fetch and the conditional-cache-miss
    /// retry so the two can't drift on what counts as success.
    private func handleSettledResponse(
        _ http: HTTPURLResponse, data: Data, rule: GitHubReleaseRule, url: URL,
        list: Bool, tag: String?
    ) throws -> [Release]? {
        guard (200..<300).contains(http.statusCode) else {
            let budget = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            let remaining = budget ?? "?"
            Log.source.error("GitHub \(rule.slug, privacy: .public): HTTP \(http.statusCode, privacy: .public) (ratelimit-remaining=\(remaining, privacy: .public))")
            // Record the failure too, and record it BEFORE throwing. A 403 is the
            // loudest form of the very problem this audit exists to explain — the
            // anonymous budget running out under a rule that lost its token to a
            // rename redirect — so skipping the bad-status path would leave the
            // sweep silent exactly when it matters most. There is no body to name
            // the canonical repo from, but the final URL and the rate-limit ceiling
            // are both on this response.
            GitHubEndpointAudit.record(
                requestedSlug: rule.slug, requestedURL: url, response: http,
                firstReleaseHTMLURL: nil, sentToken: token != nil)
            // An exact-tag lookup is channel discovery, not the update probe
            // itself. A custom/local build or a release whose tag was removed
            // simply cannot prove its channel; report that as "nothing found"
            // rather than as a retryable app error. The caller turns it into an
            // answer on the stable rule — it is the discovery that declines, not
            // the source.
            if tag != nil, http.statusCode == 404 { return nil }
            throw Self.statusError(http.statusCode, rateLimitRemaining: budget)
        }
        let decoded = Self.releases(from: data, list: list)
        // Verification-only bookkeeping: notice a slug that GitHub had to redirect,
        // and an authenticated request that came back on the anonymous budget
        // anyway. Recorded here because this is the last place the response and the
        // decoded body are both in hand. No-op when no ledger is installed, which
        // is every path except `duo verify`. See ``GitHubEndpointAudit``.
        GitHubEndpointAudit.record(
            requestedSlug: rule.slug, requestedURL: url, response: http,
            firstReleaseHTMLURL: decoded.first?.htmlURL, sentToken: token != nil)
        return decoded
    }

    /// `max(newest release in the installed version's major line, newest stable
    /// release)` — see `GitHubCandidateScope` for the measurement behind it.
    ///
    /// Returns nil when the installed string has no major component to anchor on
    /// (a hand-built or renamed copy). Callers decline instead of guessing: this
    /// scope exists precisely because "the newest release" is the wrong answer
    /// for these apps.
    static func lineAnchoredCeiling(
        _ releases: [Release], installed: String, pattern: String
    ) -> String? {
        guard let installedMajor = VersionComparator.majorComponent(installed) else { return nil }
        var newestInLine: String?
        var newestStable: String?
        for release in releases {
            // Drafts are filtered before this runs; refusing them here too means
            // the ceiling cannot be an unpublished build if those two steps are
            // ever reordered, and lets the property be asserted against THIS
            // function instead of against the order of its callers.
            guard !release.isDraft,
                  let v = VendorProbeRecipe.extractVersion(from: release.tag, pattern: pattern)
            else { continue }
            if VersionComparator.majorComponent(v) == installedMajor,
               newestInLine.map({ VersionComparator.isNewer(v, than: $0) }) ?? true {
                newestInLine = v
            }
            if !release.isPrerelease,
               newestStable.map({ VersionComparator.isNewer(v, than: $0) }) ?? true {
                newestStable = v
            }
        }
        switch (newestInLine, newestStable) {
        case let (line?, stable?): return VersionComparator.isNewer(stable, than: line) ? stable : line
        case let (line?, nil): return line
        case let (nil, stable?): return stable
        case (nil, nil): return nil
        }
    }

    private struct Resolution {
        let remote: RemoteVersion?
        let tags: [String]
        let archIncompatible: Bool
    }

    /// - anchoredTo: the marketing version of the copy on disk, for a rule whose
    ///   `candidateScope` needs to know which line the user is actually on. nil
    ///   for every `.newest` rule, and — deliberately — a hard stop rather than a
    ///   silent fall back to `.newest` for a rule that asked for an anchor: a
    ///   diagnostic that quietly measured a different algorithm than the one
    ///   users run is the failure mode `resolveDiagnostic` exists to prevent.
    /// - reusingListPage: a page of this rule's list endpoint the caller already
    ///   holds (`resolveDiagnostic`, after channel discovery fetched it). Only
    ///   valid for a rule whose full-page fetch IS the list endpoint; the caller
    ///   decides that. Given one, the one-row probe is skipped as well — the whole
    ///   page is already in hand, and the probe exists only to avoid paying for it.
    private func resolve(
        _ rule: GitHubReleaseRule,
        anchoredTo installedVersion: String? = nil,
        preferring hostArch: HostArch = .current,
        allowingIntelTranslation canRunIntel: Bool = HostArch.canRunIntelBuilds,
        reusingListPage prefetched: [Release]? = nil
    ) async throws -> Resolution {
        if let prefetched {
            return try await settle(
                rule, releases: prefetched, anchoredTo: installedVersion,
                preferring: hostArch, allowingIntelTranslation: canRunIntel,
                recordingMisses: true)
        }
        // One row first, when the rule allows it — see `newestProbeSize(for:)`.
        // A probe that cannot answer is not a recipe miss (the release it wants
        // may simply sit below the newest row), so nothing is recorded against
        // the rule until the full page has had its say. An arch-incompatible
        // newest row IS the answer — the full page would break on the same
        // row — so that one does not fall back either.
        if let probeSize = await newestProbeSize(for: rule) {
            guard let probed = try await fetchReleases(rule, list: true, pageSize: probeSize) else {
                return Resolution(remote: nil, tags: [], archIncompatible: false)
            }
            let first = try await settle(
                rule, releases: probed, anchoredTo: installedVersion,
                preferring: hostArch, allowingIntelTranslation: canRunIntel,
                recordingMisses: false)
            if first.remote != nil || first.archIncompatible { return first }
            Log.source.debug("GitHub \(rule.slug, privacy: .public): the newest release could not answer, paying for the full page of \(rule.listPageSize, privacy: .public)")
        }
        guard let releases = try await fetchReleases(rule, list: rule.usePrereleases) else {
            return Resolution(remote: nil, tags: [], archIncompatible: false)
        }
        return try await settle(
            rule, releases: releases, anchoredTo: installedVersion,
            preferring: hostArch, allowingIntelTranslation: canRunIntel,
            recordingMisses: true)
    }

    /// Everything `resolve` does once it holds a page: scope ceiling, the
    /// stable rule's missing-asset fallback, history, the asset walk. Split
    /// from the fetch so a one-row probe and the full page run the identical
    /// judgement; `recordingMisses` is the only difference, because a probe
    /// that finds nothing is not evidence about the recipe.
    private func settle(
        _ rule: GitHubReleaseRule,
        releases: [Release],
        anchoredTo installedVersion: String?,
        preferring hostArch: HostArch,
        allowingIntelTranslation canRunIntel: Bool,
        recordingMisses: Bool
    ) async throws -> Resolution {
        var releases = releases
        // Drafts are never releases, even when an authenticated token can see
        // them, and no scope should be able to offer one.
        releases = releases.filter { !$0.isDraft }

        // A line-anchored rule may not offer anything ABOVE its ceiling. Applied
        // as a ceiling rather than by picking one release so the walk-back below
        // (a release whose macOS asset is missing) still has somewhere to go.
        if rule.candidateScope == .installedMajorLineOrNewestStable {
            guard let installedVersion,
                  let ceiling = Self.lineAnchoredCeiling(
                    releases, installed: installedVersion, pattern: rule.versionPattern)
            else {
                Log.source.info(
                    "GitHub \(rule.slug, privacy: .public): line-anchored rule has no usable anchor, declining rather than offering the newest release")
                return Resolution(remote: nil, tags: releases.map(\.tag), archIncompatible: false)
            }
            releases = releases.filter { release in
                guard let v = VendorProbeRecipe.extractVersion(
                    from: release.tag, pattern: rule.versionPattern) else { return false }
                return !VersionComparator.isNewer(v, than: ceiling)
            }
        }

        // A rule that names a macOS installer asks a stricter question than "what
        // is the newest tag": **which release shipped this app for macOS.** Those
        // differ whenever a cross-platform project cuts a release for some of its
        // platforms only — LocalSend's v1.18.1 carries four `.apk` files and
        // nothing else, because the fixes in it were Android/iOS ones and the
        // macOS dmg is built by hand off CI. Reading the tag alone turns that into
        // a permanent phantom update: a version that is real, newer, and simply
        // does not exist for this platform, so it can never be installed and never
        // goes away.
        //
        // `/releases/latest` returns a single object, so when that one release has
        // no matching asset there is nothing to fall back to — pay for the list
        // then, and only then. The healthy path stays at one request, which is
        // what the unauthenticated 60/hour budget can afford.
        if let pattern = rule.installAssetPattern, !rule.usePrereleases,
           !releases.contains(where: {
               GitHubReleaseRule.carriesInstallableAsset(from: $0.assets, matching: pattern)
           }) {
            Log.source.debug("GitHub \(rule.slug, privacy: .public): latest release carries no macOS asset, falling back to the releases list")
            // The list endpoint is not the latest endpoint with more rows: GitHub
            // computes `/releases/latest` with prereleases excluded, and every
            // stable rule depends on that. Walking the raw list would let a
            // stable install be offered a `-beta`/`-rc`/`-pre` build the moment
            // its newest stable release happened to lack the macOS asset —
            // reintroducing exactly the cross-channel mixing the channel gate
            // exists to prevent. Drafts go too: they are visible on this endpoint
            // to a token with push access and are not released at all.
            if let list = try await fetchReleases(rule, list: true) {
                releases = Self.stableOnly(list)
            }
        }
        // Every matching release that carries a publish date — backfills the app's
        // visible release history into the timeline at no extra network cost (these
        // are the same releases we already fetched). A single-`latest` fetch yields
        // just one entry; a prerelease-channel list yields the whole page.
        //
        // #300: GitHub's `published_at` is normally a full ISO8601 timestamp, so
        // this almost always resolves to `.minute` in practice — but routing it
        // through `publishedFields` rather than the old `ReleaseDate.parse` means
        // a release that only carried a bare calendar day would still get a
        // history entry (as `vendorDay`) instead of being silently dropped, same
        // as `SparkleAppcastSource.releaseHistory` already does.
        let history: [ReleaseHistoryEntry] = releases.compactMap { release in
            guard let v = VendorProbeRecipe.extractVersion(from: release.tag, pattern: rule.versionPattern)
            else { return nil }
            let fields = ReleaseDate.publishedFields(from: release.publishedAt)
            guard fields.publishedAt != nil || fields.vendorDay != nil else { return nil }
            return ReleaseHistoryEntry(version: v, publishedAt: fields.publishedAt, vendorDay: fields.vendorDay)
        }
        var skippedForMissingAsset: [String] = []
        var archIncompatible = false
        for release in releases {
            if let version = VendorProbeRecipe.extractVersion(from: release.tag, pattern: rule.versionPattern) {
                // See the fallback above: for an install-capable rule the macOS
                // artifact IS the release, so a tag without one is not this app's
                // version and we keep walking back.
                if let pattern = rule.installAssetPattern,
                   !GitHubReleaseRule.carriesInstallableAsset(from: release.assets, matching: pattern) {
                    skippedForMissingAsset.append(release.tag)
                    // Walking back forever is how a renamed asset turns into a
                    // confident "up to date" on a version from a year ago. A
                    // handful of platform-partial releases is normal; a run of
                    // them means the pattern stopped matching, which is a recipe
                    // failure and has to surface as one.
                    if skippedForMissingAsset.count > Self.maxReleasesWithoutMacOSAsset { break }
                    continue
                }
                // A macOS asset exists here, but only for the other architecture,
                // and this host can never run it (no reverse translation on an
                // Intel Mac, or Rosetta no longer covering apps from macOS 28).
                // Stop rather than walk into older releases: they are no more
                // likely to differ, and offering a stale version as "the latest"
                // would be its own kind of wrong.
                if let pattern = rule.installAssetPattern,
                   GitHubReleaseRule.isArchIncompatibleOnly(
                       assets: release.assets, matching: pattern,
                       preferring: hostArch, allowingIntelTranslation: canRunIntel) {
                    archIncompatible = true
                    break
                }
                let page = release.htmlURL ?? URL(string: "https://github.com/\(rule.slug)/releases")
                let body = release.body.flatMap { $0.isEmpty ? nil : $0 }
                let structured = body.flatMap {
                    GitHubMarkdownParser.parse(body: $0, version: version, date: release.publishedAt)
                }
                // #300: same day/minute split as the history backfill above —
                // `release.publishedAt` is normally a full ISO8601 timestamp,
                // but a bare calendar day now lands honestly in `vendorDay`
                // instead of being dropped by the old `ReleaseDate.parse`.
                let publishedFields = ReleaseDate.publishedFields(from: release.publishedAt)

                // When the rule names an installable asset and this release ships
                // a matching one, offer a one-click in-place install (the Team-ID
                // gate in VendorInstaller still guards the swap). Otherwise stay
                // detection-only: link to the releases page, install nothing.
                let asset = rule.installAssetPattern.flatMap {
                    GitHubReleaseRule.installableAsset(
                        from: release.assets, matching: $0,
                        preferring: hostArch, allowingIntelTranslation: canRunIntel)
                }
                let installable = asset?.url != nil && rule.installerKind != nil

                // `recipeID`, not `slug`: two rules can share one repo (Zed and Zed
                // Preview, UTM Stable and Beta, GitHub Desktop's two channels), and
                // under a shared key whichever ran LAST decided the verdict for
                // both. A Preview rule whose tag pattern had stopped matching was
                // reported healthy on the strength of its stable sibling's success
                // while every Preview row went quietly `.unknown` — and the
                // diagnostics panel is the only surface that says a recipe broke.
                await RecipeHealth.shared.recordSuccess(id: rule.recipeID, source: name)
                return Resolution(remote: RemoteVersion(
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
                    publishedAt: publishedFields.publishedAt,
                    vendorDay: publishedFields.vendorDay,
                    releaseHistory: history,
                    releaseChannel: rule.channel
                ), tags: releases.map(\.tag), archIncompatible: false)
            }
        }
        // Not a recipe failure — the vendor did ship a macOS build for the
        // newest matching release, it just isn't one this Mac can launch. No
        // RecipeHealth signal either way: the recipe itself is fine, this
        // cycle's answer is purely a fact about this host's architecture.
        if archIncompatible {
            Log.source.debug(
                "GitHub \(rule.slug, privacy: .public): latest matching release only ships an asset for the other architecture, which this host cannot run — not offering it")
            return Resolution(
                remote: nil, tags: releases.map(\.tag), archIncompatible: true)
        }
        // Two different breakages end up here and they need different words: a
        // tag-format change (nothing matched the version pattern) versus an
        // asset rename (tags matched fine, none carried the macOS file). Reported
        // as the same thing, the second reads like the first and gets fixed in
        // the wrong place.
        guard recordingMisses else {
            return Resolution(remote: nil, tags: releases.map(\.tag), archIncompatible: false)
        }
        if !skippedForMissingAsset.isEmpty {
            let tags = skippedForMissingAsset.joined(separator: ", ")
            Log.source.error("GitHub \(rule.slug, privacy: .public): no release carries an asset matching /\(rule.installAssetPattern ?? "", privacy: .public)/ (walked \(tags, privacy: .public))")
            await RecipeHealth.shared.recordMiss(
                id: rule.recipeID, source: name,
                detail: "\(skippedForMissingAsset.count) release(s) matched the version pattern but "
                    + "none carried an asset matching the install pattern (\(tags)) — the vendor may "
                    + "have renamed the macOS artifact")
            return Resolution(
                remote: nil, tags: releases.map(\.tag), archIncompatible: false)
        }
        Log.source.error("GitHub \(rule.slug, privacy: .public): \(releases.count, privacy: .public) releases fetched, none matched /\(rule.versionPattern, privacy: .public)/")
        // Fetched fine but nothing matched the version pattern — the breakage
        // shape a tag-format change produces. Surface it in diagnostics.
        await RecipeHealth.shared.recordMiss(
            id: rule.recipeID, source: name,
            detail: "\(releases.count) releases fetched, none matched the version pattern")
        return Resolution(
            remote: nil, tags: releases.map(\.tag), archIncompatible: false)
    }

    /// A GitHub release reduced to the fields we use: tag, notes body, page URL,
    /// date, and downloadable assets (filename → URL + declared size, for
    /// installer selection and shortest-first "Update All" ordering).
    struct Release {
        let tag: String
        let body: String?
        let htmlURL: URL?
        let publishedAt: String?
        let assets: [(name: String, url: URL, size: Int64?)]
        /// Consulted on list endpoints and exact-tag channel discovery.
        /// `/releases/latest` is computed by GitHub with prereleases excluded,
        /// which is precisely why stable rules use it — see `resolve`.
        let isPrerelease: Bool
        let isDraft: Bool
        /// Exact-tag discovery must distinguish an explicit `false` from a
        /// response whose schema stopped carrying the two release-state fields.
        /// List filtering keeps its historic missing-means-stable behavior.
        let hasExplicitReleaseState: Bool
    }

    /// What the list endpoint may contribute to a *stable* rule. Split out from
    /// the call site so the filter is testable without a fetch — the bug it
    /// prevents is invisible until the day a stable release ships without its
    /// macOS asset, which is far too late to find out.
    static func stableOnly(_ releases: [Release]) -> [Release] {
        releases.filter { !$0.isPrerelease && !$0.isDraft }
    }

    /// Extract releases from either a single release object or a list.
    static func releases(from data: Data, list: Bool) -> [Release] {
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
                assets: assets,
                isPrerelease: (obj["prerelease"] as? Bool) ?? false,
                isDraft: (obj["draft"] as? Bool) ?? false,
                hasExplicitReleaseState: obj["prerelease"] is Bool && obj["draft"] is Bool
            )
        }
    }
}

/// The verified bundleID → GitHub repo table. Every entry was confirmed against
/// the live Releases API to yield the app's current version.
public enum GitHubReleaseRegistry {
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
    public static let rules: [GitHubReleaseRule] = AppRecipeIndex.all.flatMap(\.githubRules)
}
