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
    /// measured at 6%–51% of the JSON, 421 KB of the 481 KB these six repos cost
    /// per sweep round at `per_page=20` (2026-09-04, real responses, **gzipped
    /// wire bytes** — the same unit the request log counts. Re-measure with
    /// `curl --compressed`; identity bytes run 4-10x larger and reading these
    /// as identity would look like a regression that isn't there).
    /// Shrinking the page cuts that dead weight, but ONLY as far as the specific
    /// rule's tag pattern has been measured to need: too small and the release
    /// this rule is looking for scrolls off the page, which reads as "no update"
    /// rather than as an error. Set this only after walking the rule's own
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
        channel: ReleaseChannel = .stable
    ) {
        self.bundleID = bundleID
        self.channel = channel
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
    static let nonAnchorFields: Set<String> = ["bundleID", "channel", "listPageSize"]

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
    /// the tests measure. No `githubProofs` entry is an anchor today — every one
    /// of them is provable from the resolved URL — so the per-field half below
    /// exists so that the first rule which does need an anchor cannot silently get
    /// the weaker any-field behaviour.
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
    /// Where a proven channel is remembered between checks. nil means "prove it
    /// every time and persist nothing" — the default, so a test that doesn't
    /// inject one cannot write into the user's real file. `SourceStack` passes
    /// the shared instance, and passes the SAME instance to `UpdateChecker` so a
    /// failed check can still read what an earlier one proved.
    private let channelStore: ResolvedChannelStore?

    public init(
        rules: [GitHubReleaseRule] = GitHubReleaseRegistry.rules,
        token: String? = nil,
        session: URLSession = .updates,
        channelStore: ResolvedChannelStore? = nil
    ) {
        self.rules = Dictionary(grouping: rules, by: { $0.bundleID })
        self.token = token
        self.session = session
        self.channelStore = channelStore
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
    func channelDiscoveryProbe(
        _ rule: GitHubReleaseRule
    ) async throws -> (failure: ProbeFailure?, provenVersion: String?, tags: [String]) {
        guard let prefix = rule.installedTagPrefix else { return (nil, nil, []) }
        guard let list = try await fetchReleases(rule, list: true) else {
            return (.channelDiscoveryBroken("could not fetch the releases list"), nil, [])
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
                nil, tags)
        }

        let tag = prefix + version
        guard let exact = try await fetchReleases(rule, list: false, tag: tag)?.first else {
            // `fetchReleases` turns a 404 on an exact-tag lookup into nil — the
            // one status that really does mean "this mechanism cannot classify
            // an install on this version".
            return (.channelDiscoveryBroken(
                "exact-tag lookup for \(tag) returned nothing — an install on this version could not be classified"),
                nil, tags)
        }
        guard exact.hasExplicitReleaseState else {
            return (.channelDiscoveryBroken(
                "\(tag) no longer carries both `prerelease` and `draft`; channel identification reads those fields"),
                nil, tags)
        }
        guard VendorProbeRecipe.extractVersion(
            from: exact.tag, pattern: rule.versionPattern) == version
        else {
            return (.channelDiscoveryBroken(
                "\(tag) resolved to a different tag (\(exact.tag))"), nil, tags)
        }
        return (nil, version, tags)
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
            if rule.installedTagPrefix != nil {
                let discovery = try await channelDiscoveryProbe(rule)
                if let failure = discovery.failure {
                    return outcome(remote: nil, failure: failure, tags: discovery.tags)
                }
                anchor = anchor ?? discovery.provenVersion
            }
            let resolved = try await resolve(
                rule, anchoredTo: anchor, preferring: hostArch,
                allowingIntelTranslation: canRunIntel)
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
    private func fetchReleases(
        _ rule: GitHubReleaseRule, list: Bool, tag: String? = nil
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
                ? "https://api.github.com/repos/\(rule.slug)/releases?per_page=\(rule.listPageSize)"
                : "https://api.github.com/repos/\(rule.slug)/releases/latest"
        }
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        // Authenticated requests get 5000/hour instead of 60/hour per IP.
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        Log.source.debug("GitHub GET \(endpoint, privacy: .public) (auth=\(self.token != nil, privacy: .public))")
        let (data, response) = try await session.versionFeedData(
            for: request, label: "GitHub \(rule.slug)")
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else {
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
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
            throw GitHubError.badStatus(http.statusCode)
        }
        // Walk releases in document order (GitHub returns newest first) and take
        // the first whose tag the pattern matches — for prerelease channels this
        // skips interleaved stable releases.
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
    private func resolve(
        _ rule: GitHubReleaseRule,
        anchoredTo installedVersion: String? = nil,
        preferring hostArch: HostArch = .current,
        allowingIntelTranslation canRunIntel: Bool = HostArch.canRunIntelBuilds
    ) async throws -> Resolution {
        guard var releases = try await fetchReleases(rule, list: rule.usePrereleases) else {
            return Resolution(remote: nil, tags: [], archIncompatible: false)
        }

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

                await RecipeHealth.shared.recordSuccess(id: rule.slug, source: name)
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
        if !skippedForMissingAsset.isEmpty {
            let tags = skippedForMissingAsset.joined(separator: ", ")
            Log.source.error("GitHub \(rule.slug, privacy: .public): no release carries an asset matching /\(rule.installAssetPattern ?? "", privacy: .public)/ (walked \(tags, privacy: .public))")
            await RecipeHealth.shared.recordMiss(
                id: rule.slug, source: name,
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
            id: rule.slug, source: name,
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

        // AgentsView — browser for past AI coding sessions, no SUFeedURL,
        // GitHub v-tags. Two of the last forty releases shipped no mac dmg at
        // all (v0.41.0 and v0.33.1 were tar.gz-only) — the release walk skips
        // them and one-click lands on the newest dmg-bearing release, same
        // semantics the cask livecheck encodes. The aarch64 dmg is arm64-only
        // (AgentsView_{v}_x64.dmg is the Intel twin); Team 2YMZH84KR8,
        // notarized. Mounted v0.41.1: io.agentsview.desktop, short == build.
        GitHubReleaseRule(
            bundleID: "io.agentsview.desktop",
            owner: "kenn-io", repo: "agentsview",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^AgentsView_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),

        // GitHub Copilot — the native client from github/app. No SUFeedURL,
        // cask `auto_updates`, so the row was unknown. Stable tags `vX.Y.Z`
        // only; the anchored pattern keeps a future prerelease from reading as
        // stable under the list fallback. One-click pins the arm64 dmg — each
        // release also ships darwin-x64.dmg, .zip and .tar.gz (+ .sig) beside
        // it, and Windows/Linux artifacts. Mounted v1.1.14 dmg:
        // com.github.githubapp, short == build == 1.1.14, arm64-only, Team
        // VEKTX9H2N7, notarized.
        GitHubReleaseRule(
            bundleID: "com.github.githubapp",
            owner: "github", repo: "app",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^GitHub-Copilot-darwin-arm64\.dmg$"#,
            installerKind: .dmg),

        // FluidVoice — on-device dictation. Homebrew cask `fluidvoice` is
        // `auto_updates`, no `SUFeedURL`, so the row was unknown. Tags are
        // `vX.Y.Z`; the same repo also ships `vX.Y.Z-beta.N` macOS prereleases
        // and `windows-vX.Y.Z` Windows builds, so the pattern is anchored on
        // both ends rather than stripping a `v` off whatever comes first.
        //
        // ⚠️ Renamed altic-dev/Fluid-oss → altic-dev/FluidVoice. The old slug
        // 301s onto this one (`full_name` is FluidVoice). Pin the canonical
        // name: URLSession drops `Authorization` while following GitHub's 301,
        // and the fetch that actually returns the releases would come back
        // anonymous. See #135.
        //
        // One-click: each stable release ships `Fluid-oss-<ver>.dmg` beside a
        // zip of the same build. Mounted 1.6.9 dmg: com.FluidApp.app, short
        // `1.6.9` == tag (CFBundleVersion is a small counter `20`, not compared),
        // universal x86_64+arm64, Team V4J43B279J, notarized + stapled. The
        // filename keeps the old product token; the zip and the Windows
        // `FluidVoice_*_x64-setup.exe` share the release and must not match.
        GitHubReleaseRule(
            bundleID: "com.FluidApp.app",
            owner: "altic-dev", repo: "FluidVoice",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Fluid-oss-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

        // Helium — Chromium-based AI browser (imputnet/helium-macos). Bare tags
        // (`0.16.2.1`, no v), and the repo DOES cut prerelease releases with
        // the same all-digit tag shape (`0.16.1.1`) — /releases/latest excludes
        // prereleases, so the stable rule never sees them. One-click pins the
        // arm64 dmg; the x86_64 dmg ships beside it. Mounted 0.16.2.1:
        // net.imput.helium, short == build == tag, Team S4Q33XPHB4, notarized.
        GitHubReleaseRule(
            bundleID: "net.imput.helium",
            owner: "imputnet", repo: "helium-macos",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^helium_[0-9.]+_arm64-macos\.dmg$"#,
            installerKind: .dmg),

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
        // listPageSize: measured 2026-09-04 against the newest 100 releases —
        // the newest is always a `-pre` tag (first-match index 0) and the worst
        // run of non-`-pre` tags between two `-pre` releases is 3 (index gap;
        // e.g. `v1.5.1-pre`→`v1.5.0-pre`). 5 keeps ~67% headroom over that and
        // was the real page measured at 32 KB, vs 104 KB at the old per_page=20.
        GitHubReleaseRule(
            bundleID: "dev.zed.Zed-Preview",
            owner: "zed-industries", repo: "zed",
            usePrereleases: true,
            listPageSize: 5,
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

        // Kun — local-first AI agent workspace (KunAgent). No SUFeedURL;
        // v-tags, each release ships mac-arm64/mac-x64 dmgs plus zips and
        // Linux deb/AppImage siblings. One-click pins the arm64 dmg. Mounted
        // v0.3.7: com.xingyuzhong.deepseekgui, short == build == tag, Team
        // YBR76S5LNP, notarized.
        GitHubReleaseRule(
            bundleID: "com.xingyuzhong.deepseekgui",
            owner: "KunAgent", repo: "Kun",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Kun-[0-9.]+-mac-arm64\.dmg$"#,
            installerKind: .dmg),

        // DSH Desktop — the DeepSeek Harness desktop client (anywhere-labs).
        // No SUFeedURL; v-tags, one universal dmg per release beside a Windows
        // setup.exe. Mounted v2.0.4: ai.deepseek.dsh.desktop, short == build
        // == tag, Team UM3Z9G5DNH, notarized.
        GitHubReleaseRule(
            bundleID: "ai.deepseek.dsh.desktop",
            owner: "anywhere-labs", repo: "dsh-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^DSH\.Desktop-[0-9.]+-universal\.dmg$"#,
            installerKind: .dmg),

        // Meetily — local-first AI meeting transcription (Tauri). No SUFeedURL
        // (the release's `latest.json` is Tauri-updater state, not a feed we
        // read). v-tags with one legacy bare tag (`0.1.1`) deep in history —
        // /releases/latest returns the newest stable v-tag regardless. One
        // -click pins the aarch64 dmg (arm64-only; the x64 setup.exe/msi
        // siblings are Windows). Mounted v0.4.0: com.meetily.ai, short ==
        // build == tag, Team 554AZZ38TB, notarized.
        GitHubReleaseRule(
            bundleID: "com.meetily.ai",
            owner: "Zackriya-Solutions", repo: "meetily",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^meetily_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),

        // Paseo — self-hosted daemon/desktop for AI coding agents. Stable v-tags
        // plus a beta train cut as prerelease releases (`v0.7.0-beta.2`, assets
        // `beta-mac.yml` + dmg) — the anchored stable pattern rejects the beta
        // suffix and /releases/latest excludes prereleases anyway, so the stable
        // rule never serves a beta. One-click pins the arm64 dmg (the deb/
        // AppImage siblings are Linux). Mounted v0.6.1: sh.paseo.desktop, short
        // == build == tag, Team 99ZMJMKU9Y, notarized.
        GitHubReleaseRule(
            bundleID: "sh.paseo.desktop",
            owner: "getpaseo", repo: "paseo",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Paseo-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // OpenSuperWhisper — bare tags (no `v`), and the dmg asset name is
        // versionless (`OpenSuperWhisper.dmg` on every release), so the version
        // pattern must anchor `$` and the asset pattern must be the literal
        // filename. All releases are stable so far; `$` keeps a future
        // `0.2.0-beta.1` from reading as stable. arm64-only dmg (the cask is
        // `depends_on arch: :arm64`), Team 8LLDD7HWZK, notarized. Mounted
        // 0.1.0: ru.starmel.OpenSuperWhisper, short == tag, build 13.
        GitHubReleaseRule(
            bundleID: "ru.starmel.OpenSuperWhisper",
            owner: "starmel", repo: "OpenSuperWhisper",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenSuperWhisper\.dmg$"#,
            installerKind: .dmg),

        // claude-devtools — visualiser/analyser for Claude Code sessions.
        // v-tags, and each release ships both an arm64 dmg and an x64 dmg plus
        // zip/blockmap siblings (the cask itself is x86_64-gated, but the repo
        // has shipped arm64 dmgs all along). Mounted v0.5.0:
        // com.claudecode.context, short == build == tag, Team 55PSHY2MW6,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.claudecode.context",
            owner: "matt1398", repo: "claude-devtools",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^claude-devtools-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),

        // Claude Status Bar — menu-bar quota indicator for Claude Code. v-tags,
        // and the dmg asset name is versionless (ClaudeStatusBar.dmg on every
        // release), so the asset pattern is the literal filename. Mounted
        // v0.4.4: com.local.claudestatusbar, short == build == tag, Team
        // W9JZ4932LA, notarized.
        GitHubReleaseRule(
            bundleID: "com.local.claudestatusbar",
            owner: "m1ckc3s", repo: "claude-status-bar",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^ClaudeStatusBar\.dmg$"#,
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
        // listPageSize: not installed on the measuring machine, so measured
        // directly against the live endpoint (2026-09-04, newest 100 releases):
        // first-match index 0, worst run of non-`core@` tags between two
        // `core@` releases is 9 (`core@11.0.0`→`core@10.3.1`, the Design/CLI
        // trains publish in between). 15 keeps ~67% headroom over that.
        GitHubReleaseRule(
            bundleID: "com.insomnia.app",
            owner: "Kong", repo: "insomnia",
            usePrereleases: true,
            listPageSize: 15,
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
        // listPageSize: not installed on the measuring machine, so measured
        // directly against the live endpoint (2026-09-04, newest 100 releases):
        // first-match index 1 (the newest release is often the stable
        // `release-…` tag one spot above), worst run between two `-betaN` tags
        // is 4 (`release-3.4.16-beta1`→`release-3.4.13-beta2`). 8 keeps 2x
        // headroom over that.
        GitHubReleaseRule(
            bundleID: "com.github.GitHubClient",
            owner: "desktop", repo: "desktop",
            usePrereleases: true,
            listPageSize: 8,
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

        // Vorssaint — Homebrew marks the cask `auto_updates true`, so the generic
        // Homebrew source intentionally skips it. Stable and Beta share both the
        // bundle id and app name; the installed beta's real short version carries
        // `-beta.<N>`, which ReleaseChannel uses to select this pair safely.
        //
        // One-click enabled 2026-09-03 after measuring the artifacts rather than
        // trusting the earlier note. That note said the stable dmg's app failed
        // strict code-sign verification on macOS 27 and used it as the reason to
        // withhold an install spec; on the same OS build (27.0 / 26A5425a) both
        // the stable 3.3.2 and the 3.3.3-beta.3 app pass
        // `codesign --verify --deep --strict` ("valid on disk", "satisfies its
        // Designated Requirement") and `spctl -a -t execute` ("accepted",
        // "Notarized Developer ID", ticket stapled, Team 3D485NHW29). What IS
        // unsigned is the dmg CONTAINER — and `SignatureVerifier` gates on the
        // extracted `.app`, never the container, so it was never the blocker it
        // was read as.
        //
        // Both trains ship exactly one asset per release, and the beta's carries
        // the channel: `Vorssaint-3.3.2.dmg` vs `Vorssaint-3.3.3-beta.3.dmg`. The
        // stable pattern's `[0-9.]+` run refuses the `-` in `-beta.3`, so it
        // cannot match a beta artifact even on the list fallback (which is
        // stable-only anyway); the beta pattern names the suffix outright. The
        // beta pair is registered in `ChannelProofRegistry` — see
        // `ChannelArtifactProof` for why an install-capable non-stable rule
        // without a proof is a hard finding.
        //
        // Verified end to end 2026-09-03 from the beta side, which is the one
        // that can go wrong: installed `3.3.3-beta.1` in `~/Applications`, the
        // row offered `3.3.3-beta.3` and NOT stable 3.3.2 (the display version's
        // `-beta.N` is what `ReleaseChannel.detect` reads — stable and beta share
        // both the bundle id and the app name, so nothing else distinguishes
        // them), and `duo install` landed it on the beta build.
        GitHubReleaseRule(
            bundleID: "com.vorssaint.utils",
            owner: "vorssaintapp", repo: "vorssaint-utils",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Vorssaint-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        // listPageSize: measured 2026-09-04 — only 4 `-beta.` tags exist in the
        // repo's whole history (73 releases scanned), all consecutive
        // (first-match index 0, worst gap 1). Small sample, so 5 keeps margin
        // rather than trimming to the observed minimum; real page measured at
        // 17 KB, vs 48 KB at the old per_page=20.
        GitHubReleaseRule(
            bundleID: "com.vorssaint.utils",
            owner: "vorssaintapp", repo: "vorssaint-utils",
            usePrereleases: true,
            listPageSize: 5,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+-beta\.[0-9]+)$"#,
            installAssetPattern: #"^Vorssaint-[0-9.]+-beta\.[0-9]+\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),

        // OpenLogi — fast-moving native Logitech utility. The real 0.8.1 bundle
        // is `org.openlogi.openlogi` and carries neither Sparkle nor another
        // standard update feed in Info.plist; its Homebrew cask is
        // `auto_updates: true`, so Homebrew correctly defers to the app updater.
        // That updater's compiled-in stable manifest and release workflow both
        // point at AprilNEA/OpenLogi, where stable tags are exactly `vX.Y.Z` and
        // publishing is gated on both macOS DMGs existing. The anchored pattern
        // rejects prerelease suffixes rather than truncating one onto stable.
        //
        // One-click verified 2026-09-03 end to end: installed 0.8.2 in
        // `~/Applications`, `duo install` took it to 0.8.3. Mounted arm64 dmg:
        // org.openlogi.openlogi, short `0.8.3` == tag, Team 8U3ZJ258K9 (the same
        // Team 0.8.2 carries, so the swap gate passes), signed Developer ID and
        // accepted by `spctl` as Notarized Developer ID. Each release also ships
        // an `-macos-x86_64.dmg` plus Windows/Linux artifacts and a `.minisig`
        // beside every one of them, so the pattern pins the arm64 dmg and ends on
        // `.dmg$` — without the anchor `OpenLogi-v0.8.3-macos-arm64.dmg.minisig`
        // truncates onto a URL nobody published.
        //
        // ⚠️ Two facts worth not rediscovering. The app carries NO stapled
        // notarization ticket (0.8.2 and 0.8.3 both; it is how this vendor ships,
        // not a regression) — `SignatureVerifier` checks signature validity and
        // Team, never stapling, so the swap is unaffected, but Gatekeeper has to
        // resolve the ticket online at first launch. And `CFBundleVersion` is a
        // TIMESTAMP (`20260830.162827`), a different namespace from the tag —
        // harmless only because this source sets the remote build to nil, so the
        // comparison is marketing-only. Do not "improve" that by feeding the tag
        // in as a build.
        GitHubReleaseRule(
            bundleID: "org.openlogi.openlogi",
            owner: "AprilNEA", repo: "OpenLogi",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenLogi-v[0-9.]+-macos-arm64\.dmg$"#,
            installerKind: .dmg),

        // LocalSend — the reason `installAssetPattern` doubles as the macOS-release
        // gate. Upstream builds Windows/Linux/Android on CI but the dmg by hand
        // (`support/scripts/compile_mac_dmg.sh`, one maintainer, Developer ID +
        // notarization), and version numbers are shared across all five platforms
        // out of a single `pubspec.yaml`. So a mobile-only hotfix advances the tag
        // without producing a macOS build: v1.18.1 (2026-08-12) ships four `.apk`
        // files and says so in its own release notes — "Android+iOS only hotfix".
        // Reading the tag alone reported a 1.18.0 → 1.18.1 update that nobody can
        // ever install. With the pattern set, resolution walks back to v1.18.0,
        // which is genuinely the newest macOS release (Homebrew's cask and the
        // vendor's own download page both agree).
        //
        // The CLI tarballs (`LocalSend-CLI-1.18.0-macos-arm-64.tar.gz`) and the
        // Windows zip share the prefix, so the pattern anchors both ends.
        // Mounted dmg: org.localsend.localsendApp 1.18.0 (60), Team 3W7H4PYMCV,
        // hardened runtime, `spctl -a -t install` accepted.
        GitHubReleaseRule(
            bundleID: "org.localsend.localsendApp",
            owner: "localsend", repo: "localsend",
            installAssetPattern: #"^LocalSend-[0-9.]+\.dmg$"#,
            installerKind: .dmg),

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

        // UTM — virtualiser. Stable and Beta share EVERYTHING visible locally:
        // bundle id, app name, plain numeric marketing/build versions, Team ID,
        // and the literal `UTM.dmg` asset name. The tag is plain numeric too
        // (`v5.0.5`), so no suffix can gate the beta rule. Instead, the source
        // looks up the exact tag for the installed version and reads GitHub's own
        // authoritative `prerelease` bit to decide WHICH RULE this copy is on. An
        // unprovable tag claims no channel and answers on the stable rule.
        //
        // What that bit does NOT mean here is "a parallel Beta train". Measured
        // over all 131 releases: 78 are prereleases, and each minor line ships
        // previews and then graduates at a higher patch number (`v4.7.0…v4.7.3`
        // are "(Beta)", `v4.7.4`/`v4.7.5` are not). Confining a preview install to
        // prereleases therefore strands it at every graduation — 14 times in the
        // real history, worst window 2024-11-27 → 2025-07-09 with four stable
        // releases published into the silence — while offering it the newest
        // release of any kind walks a `v4.7.3` install onto a `v5.0.5` preview
        // instead of its own line's `v4.7.5`. Hence the line-anchored scope.
        //
        // Real v5.0.5 DMG verified 2026-09-03: 302,621,893 bytes, SHA-256
        // 713afe73c711f01344b8766654be531cd391ed2e30931206f43b5159f143764f;
        // com.utmapp.UTM 5.0.5 (124), Team WDNLXAD4W8, strict deep signature
        // valid, Gatekeeper `accepted, source=Notarized Developer ID`.
        GitHubReleaseRule(
            bundleID: "com.utmapp.UTM",
            owner: "utmapp", repo: "UTM",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^UTM\.dmg$"#,
            installerKind: .dmg),

        // listPageSize deliberately left at the 20 default — do NOT copy the
        // "first-match index 0" number from the stable rule above or from any
        // simple per-repo table: `.installedMajorLineOrNewestStable` doesn't
        // walk for the first tag match, it needs `lineAnchoredCeiling` to find
        // EITHER the newest release in the installed major line OR the newest
        // STABLE release within the fetched page (whichever's newer) — missing
        // both makes it decline rather than offer anything. Measured 2026-09-04
        // against the newest 100 releases, filtering on GitHub's own
        // `prerelease` bit (not the version pattern, which nearly every tag
        // matches — 98/100): the newest STABLE release currently sits at index
        // 6 (UTM is mid-preview-burst right now), and the worst historical run
        // between two consecutive stable releases in that window was 10
        // (`v3.1.4`→`v2.4.1`, an older/slower era). A page of 20 comfortably
        // covers both; trimming it below ~15 would be gambling on the burst
        // never growing past what's been observed once already.
        GitHubReleaseRule(
            bundleID: "com.utmapp.UTM",
            owner: "utmapp", repo: "UTM",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            candidateScope: .installedMajorLineOrNewestStable,
            installedTagPrefix: "v",
            installAssetPattern: #"^UTM\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),

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
        //
        // ⚠️ Renamed containers/podman-desktop
        // -> podman-desktop/podman-desktop (measured 2026-08-29). The canonical
        // name is pinned here on purpose, and it is not cosmetic: GitHub answers the
        // old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
        // `Authorization` while following it — the fetch that actually returns
        // the releases came back `x-ratelimit-limit: 60`, i.e. ANONYMOUS,
        // whatever token the user configured. Three rules were quietly doing
        // that. See #135.
        GitHubReleaseRule(
            bundleID: "io.podmandesktop.PodmanDesktop",
            owner: "podman-desktop", repo: "podman-desktop",
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
        // Depends on a window the RULE now controls via `listPageSize` (it used
        // to be a source-wide constant). Measured over the newest 100 releases,
        // consecutive `desktop-v` tags are at most 7 apart (re-verified
        // 2026-09-04: same 7, `desktop-v2026.6.0`→`desktop-v2026.5.0` and three
        // other pairs), so the desktop tag sits well inside a page of 10 today
        // — chosen over the observed 7 to leave margin rather than trim to the
        // minimum, per the same logic as every other rule below — but a long
        // burst of web/cli/browser releases would still push it off the page,
        // and the rule would then resolve nothing, which surfaces as the row
        // going quiet rather than as an error.
        //
        // One-click: the universal dmg is com.bitwarden.desktop, Team LTZ2PFU5D6,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.bitwarden.desktop",
            owner: "bitwarden", repo: "clients",
            usePrereleases: true,
            listPageSize: 10,
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

        // VSCodium Insiders — its own repo (VSCodium/vscodium-insiders), its own
        // bundle id com.vscodium.VSCodiumInsiders. NOT VS Code Insiders (the
        // com.microsoft.VSCodeInsiders VendorProbeRecipe in
        // VendorProbeRecipe.swift) — different product, different cask
        // (`vscodium@insiders` vs `visual-studio-code@insiders`).
        //
        // Detection needs no `ReleaseChannel` change, but not for the reason it
        // might look like: the bundle id has no `.insiders`/`-insiders` SUFFIX
        // (it's the single camelCase component "VSCodiumInsiders", no separator
        // before "Insiders"), so `detect`'s bundle-id-suffix step does not fire.
        // What actually resolves it to `.preview` is the display name step: the
        // installed app's CFBundleName/CFBundleDisplayName is "VSCodium -
        // Insiders" (confirmed below), and "Insiders" is a standalone word there.
        // `ChannelGuardTests.vscodiumInsidersDisplayNameSignalsPreview` pins our
        // half of this against `ReleaseChannel.detect`. It cannot pin the VENDOR's
        // half: the display name is their string, and if VSCodium ever glues it
        // ("VSCodiumInsiders", the shape the bundle id already has) `detect`
        // returns `.stable`, the channel gate skips this rule, and the app goes
        // quiet with the test still green. That is the failure to watch for here.
        //
        // CRUCIAL — this is the SECOND instance of a trap the VS Code Insiders
        // recipe (VendorProbeRecipe.swift) already hit, not a VSCodium quirk:
        // tags carry the `-insider` suffix (`1.126.04518-insider`), which IS
        // part of both CFBundleShortVersionString and CFBundleVersion on the
        // installed app — verified by downloading the real asset and reading
        // Info.plist directly (not just trusting the tag). The default pattern
        // `v?([0-9]+(?:\.[0-9]+)+)` stops at the last digit run and drops the
        // suffix; `VersionComparator` then pads the missing 4th component to "0",
        // which outranks the text token "insider" (a numeric component always
        // beats a textual one — see VersionComparator.swift), so the bare
        // "1.126.04518" would read as NEWER than the correctly-suffixed
        // installed version — a permanent phantom update on an up-to-date
        // install, never resolving. Any other `-insider`-suffixed product would
        // hit the same trap; the pattern below keeps the suffix in the capture
        // so it compares equal instead.
        //
        // arm64 ONLY, deliberately, even though this repo also publishes
        // `VSCodium-darwin-x64-<ver>-insider.zip`. Matching both looked free —
        // `installableAsset` prefers the native slice — but this track ships
        // PLATFORM-PARTIAL releases: tag `1.126.04405-insider` carries an x64
        // macOS zip and no arm64 one (checked against the API 2026-08-27). On
        // such a release a both-arch pattern reaches `installableAsset` step 3,
        // which on Apple silicon with Rosetta returns the FOREIGN build — so an
        // arm64 Insiders install gets swapped for an Intel one. Pinning arm64
        // makes that release carry no installable asset instead, and the
        // list-fallback below then offers nothing until an arm64 build exists,
        // which is the right answer for a host class that is all we ship to
        // (`App/project.yml`, `ARCHS: arm64`).
        //
        // One-click: verified 2026-08-27 by downloading the real
        // VSCodium-darwin-arm64-1.126.04518-insider.zip and reading the
        // extracted app directly — CFBundleIdentifier
        // com.vscodium.VSCodiumInsiders, CFBundleShortVersionString/
        // CFBundleVersion both "1.126.04518-insider", `codesign -dv` shows
        // TeamIdentifier VC39D2VNQ7 (same team as stable) with a stapled
        // notarization ticket, and `spctl -a --type execute` returns "accepted,
        // source=Notarized Developer ID" — passes VendorInstaller's same-Team
        // gate.
        GitHubReleaseRule(
            bundleID: "com.vscodium.VSCodiumInsiders",
            owner: "VSCodium", repo: "vscodium-insiders",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+-insider)$"#,
            installAssetPattern: #"^VSCodium-darwin-arm64-[0-9.]+-insider\.zip$"#,
            installerKind: .zip,
            channel: .preview),

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
        //
        // If a snapshot-channel rule is ever added for this bundle id: no
        // `installAssetPattern`/`installerKind` — snapshot ships completely
        // unsigned (docs/app-audits/org-keepassxc-keepassxc.md, #95).
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
        //
        // ⚠️ Renamed headlamp-k8s/headlamp
        // -> kubernetes-sigs/headlamp (measured 2026-08-29). The canonical name
        // is pinned here on purpose, and it is not cosmetic: GitHub answers the
        // old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
        // `Authorization` while following it — the fetch that actually returns
        // the releases came back `x-ratelimit-limit: 60`, i.e. ANONYMOUS,
        // whatever token the user configured. Three rules were quietly doing
        // that. See #135.
        // listPageSize: measured 2026-09-04 against the newest 100 releases —
        // first-match index 0 (the interleaved `headlamp-helm-`/`headlamp-plugin-`
        // tags this comment warns about don't match `^v…$`), worst run between
        // two app tags is 4 (`v0.23.0`→`v0.22.0`). 8 keeps 2x headroom; a
        // per_page=5 was measured at 42 KB (barely less than per_page=3's
        // 40 KB — `body` dominates either way), so 8 doesn't cost meaningfully
        // more than 5 while leaving real margin over the observed gap of 4.
        GitHubReleaseRule(
            bundleID: "com.microsoft.Headlamp",
            owner: "kubernetes-sigs", repo: "headlamp",
            usePrereleases: true,
            listPageSize: 8,
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

        // Goose (aaif-goose/goose) — the `goose-*-apple-darwin.tar.gz` assets beside
        // the app are the CLI and `goose-source-*.zip` is a source drop, so the app is
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
        //
        // ⚠️ Renamed block/goose
        // -> aaif-goose/goose (measured 2026-08-29). The canonical name
        // is pinned here on purpose, and it is not cosmetic: GitHub answers the
        // old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
        // `Authorization` while following it — the fetch that actually returns
        // the releases came back `x-ratelimit-limit: 60`, i.e. ANONYMOUS,
        // whatever token the user configured. Three rules were quietly doing
        // that. See #135.
        GitHubReleaseRule(
            bundleID: "com.electron.goose",
            owner: "aaif-goose", repo: "goose",
            installAssetPattern: #"^Goose(_intel_mac)?\.zip$"#,
            installerKind: .zip),

        // PureMac — a dmg and a zip of the same build ship together; take the dmg.
        // One-click: com.puremac.app, Team H3WXHVTP97, notarized.
        //
        // The tag is anchored because this repo ships a *second product* out of
        // the same releases: on 2026-08-17 it published `cli-v1.0.0`, carrying
        // only `puremac-cli-1.0.0.tar.gz`, and GitHub marks it latest. The default
        // pattern is unanchored, so it read that tag as version 1.0.0 — which,
        // against an installed 2.9.x, evaluates as "up to date" and hides every
        // real update. The macOS-asset gate already walks past that release, but
        // the number it walked past should never have parsed in the first place:
        // one guard against a silent no-update is not enough.
        GitHubReleaseRule(
            bundleID: "com.puremac.app",
            owner: "momenbasel", repo: "PureMac",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
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

        // T3 Code — two trains, ONE bundle id (`com.t3tools.t3code`), one repo.
        // `ReleaseChannel.detect()` reads the display name: the primary build is
        // `T3 Code (Alpha).app` (→ .alpha) and the prerelease train is
        // `T3 Code (Nightly).app` (→ .nightly), verified on the mounted artifacts.
        // Neither carries SUFeedURL; the cask is auto_updates, so Homebrew defers.
        //
        // The alpha train tags plain `vX.Y.Z` and is NOT prerelease-flagged, so
        // `/releases/latest` answers for it; the anchored pattern keeps the
        // nightly tags (same repo) from ever reading as alpha. One-click: the
        // arm64 dmg holds the same notarized `T3 Code (Alpha)` app — Team
        // ARK85ZXQ4Z, verified on the mounted v0.0.36 artifact.
        GitHubReleaseRule(
            bundleID: "com.t3tools.t3code",
            owner: "pingdotgg", repo: "t3code",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^T3-Code-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg,
            channel: .alpha),

        // T3 Code nightly — prerelease tags `vX.Y.Z-nightly.<date>.<seq>`, several
        // per day, marked prerelease, so `usePrereleases` reads the list and the
        // pattern is anchored to the nightly shape end to end. The app reports the
        // whole string as BOTH marketing and build, so the extracted version must
        // keep it intact rather than truncate to `X.Y.Z` — a nightly install shows
        // `0.0.37-nightly.20260830.1227` on both sides, and `VersionComparator`
        // orders the date/seq runs numerically. One-click: same Team
        // ARK85ZXQ4Z, verified on the mounted nightly artifact. The asset name
        // carries `-nightly.` — which is also why the alpha pattern above cannot
        // drift onto this train: its `[0-9.]+` run refuses the dash.
        // listPageSize: measured 2026-09-04 against the newest 100 releases —
        // first-match index 0, worst run between two nightly tags is 2 (the
        // alpha train's occasional release lands a single non-nightly entry in
        // between, e.g. `v0.0.39-nightly.20260902.1252`→
        // `v0.0.38-nightly.20260901.1250`). 5 keeps 2.5x headroom; real page
        // measured at 9 KB for per_page=3, vs 64 KB at the old per_page=20.
        GitHubReleaseRule(
            bundleID: "com.t3tools.t3code",
            owner: "pingdotgg", repo: "t3code",
            usePrereleases: true,
            listPageSize: 5,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^T3-Code-[0-9.]+-nightly\.[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg,
            channel: .nightly),

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
