import Foundation

/// How we know a non-stable recipe's install spec resolves ITS OWN channel's
/// build rather than the stable one.
///
/// `ProbeFailure` catches a pattern that stopped matching, and
/// `ProbeWarning.installURLUnresolved` catches an install spec that resolves
/// nothing. Neither can see the failure in between: a pattern that still matches
/// and hands back the WRONG CHANNEL's installer. That one is silent all the way
/// through — the version resolves, the URL resolves, the download is a real
/// notarized build from the same vendor with the same Team ID, so the signature
/// gate passes too — and the user's Beta install is quietly replaced by Stable.
///
/// It is a live risk because most channel recipes are written by copying their
/// stable sibling: Signal Beta's install spec was a verbatim copy of stable's,
/// and OrbStack/Alfred/IntelliJ-EAP genuinely share an endpoint or an artifact
/// name with stable, so "it resolved something" proves nothing about which train
/// it came from.
public enum ChannelArtifactProof: Sendable, Hashable {
    /// The resolved installer URL must match this regex (case-insensitive).
    /// The normal case: the vendor's artifact path or filename names the channel.
    case artifact(String)

    /// The vendor ships ONE artifact to several channels, so the URL carries no
    /// channel token and there is nothing to assert on it. The proof is instead
    /// that the recipe reads a channel-dedicated endpoint (or a channel-tagged
    /// block of a shared feed).
    ///
    /// `fields` names the recipe fields the channel identity actually lives in
    /// (their `Mirror` labels — `"url"`, `"versionPattern"`, `"install"`, …),
    /// and the regex must match in EVERY one of them. That is the whole point:
    /// matching against the joined surface passes if any single line matches, so
    /// a token that happens to sit in two fields kept the proof green while
    /// either one drifted. WeChat DevTools RC is the live case — `"id": "rc"` is
    /// in both `versionPattern` and the install `bodyPattern`, and only the
    /// install half picks the artifact (issue #110).
    ///
    /// Which fields to name is a per-recipe fact, not a rule to apply uniformly.
    /// Measured across the five anchors registered on 2026-08-28:
    ///   * **Endpoint-keyed** (IntelliJ EAP, Alfred beta) — the response body
    ///     holds only that channel's builds, so neither `versionPattern` nor the
    ///     install pattern carries a channel token to anchor on. `["url"]` is the
    ///     whole proof, and naming anything else would be an assertion those
    ///     recipes cannot satisfy. (Their INSTALL patterns are byte-identical to
    ///     their stable siblings'; their version patterns are not, and that is not
    ///     an oversight to normalise away — IntelliJ EAP reads `"build"` where
    ///     stable reads `"version"` because `versionIsBuild` compares the build,
    ///     and Alfred beta's is merely written more strictly. Neither difference
    ///     names a channel, which is the property that matters here.)
    ///   * **Shared-feed** (WeChat DevTools RC, OrbStack beta/canary) — one
    ///     endpoint serves every channel, and the per-field patterns are what
    ///     select. Both the version half and the install half must stay anchored,
    ///     so both are named.
    ///
    /// An empty set, or a name that is not an anchorable field of the recipe, is
    /// a hard finding rather than a pass — either would be a proof that cannot
    /// fail. See `RecipeSanity.recipeAnchorFailure`.
    ///
    /// **Granularity is the whole field**, and `install` is one field. Naming it
    /// asserts the token is somewhere in the install spec — the `urlSource`
    /// pattern, but also `kind`, `checksumPattern` and `requestHeaders`. So the
    /// shape this case exists to close survives one level down: a
    /// `.bodyTemplate(_, fields: [withToken, withoutToken])` would stay green
    /// while the sub-pattern that actually resolves the URL drifted. Not reachable
    /// today — no anchored recipe uses `bodyTemplate` — and said out loud rather
    /// than left for the next person to discover the way #110 was discovered.
    case recipeAnchor(String, in: Set<String>)
}

/// A `(bundleID, channel)` pair — the same key `VendorProbeSource` selects a
/// recipe by, so recipes that share a bundle id across channels stay distinct.
public struct ChannelProofKey: Hashable, Sendable, CustomStringConvertible {
    public let bundleID: String
    public let channel: ReleaseChannel

    public init(_ bundleID: String, _ channel: ReleaseChannel) {
        self.bundleID = bundleID
        self.channel = channel
    }

    public var description: String { "\(bundleID) [\(channel.rawValue)]" }
}

public enum ChannelProofRegistry {

    /// Proof of channel identity for every non-stable install-carrying recipe.
    ///
    /// Required to be exhaustive — `channelProofsCoverEveryChannelRecipe` fails if
    /// a non-stable recipe with an install spec has no entry — so a new channel
    /// can't ship without someone stating how they know it isn't crossing trains.
    /// Verified against the live endpoints on 2026-08-09.
    public static let proofs: [ChannelProofKey: ChannelArtifactProof] =
        AppRecipeIndex.merged(\.channelProofs, into: "ChannelProofRegistry.proofs")

    /// Every `(bundleID, channel)` in the vendor registry that carries an install
    /// spec and is NOT on stable — the set `proofs` has to cover.
    public static var channelRecipesWithInstall: [ChannelProofKey] {
        VendorProbeRegistry.recipes
            .filter { $0.install != nil && $0.channel != .stable }
            .map { ChannelProofKey($0.bundleID, $0.channel) }
    }

    /// The same proof, for `GitHubReleaseRegistry` (issue #101).
    ///
    /// **A separate map, not extra keys in `proofs`.** `ChannelProofKey` is
    /// `(bundleID, channel)` and says nothing about which registry it came from,
    /// so one map would silently collide the day a bundle id appears in both
    /// registries on the same channel — the entry written for one would be
    /// checked against the other, and the exhaustiveness test would pass while
    /// proving the wrong thing. No such pair exists today
    /// (`channelProofMapsDoNotCollide` measures it rather than assuming), and
    /// keeping them apart means the day one does exist is not a silent day.
    ///
    /// A GitHub rule's protection is real but structural: it lives in whichever
    /// pattern the author happened to write, and nothing re-derives it. Most of
    /// the rules this map covers gate the channel in their `versionPattern` — a stable tag
    /// cannot satisfy `-pre`, `-beta<N>` or `-insider` — which is why the live
    /// sweep of 2026-08-27 found nothing misresolving. FOUR do not, and they are
    /// the four carrying `.recipeAnchor` proofs: UTM's beta and T3 Code's alpha
    /// because their patterns hold no channel token at all (each is byte-identical
    /// to a stable pattern), and WhatCable's beta and CotEditor's beta because
    /// their token is OPTIONAL — deliberately, so each accepts the stable tag its
    /// prereleases graduate into.
    /// (Counted, not eyeballed: an earlier revision said "all three rules below
    /// gate the channel", the next said WhatCable was the only one that did not,
    /// and both were wrong. It then read THREE for as long as CotEditor's entry
    /// had been registered without being counted — recounted 2026-09-14, and the
    /// count is the thing this parenthesis exists to keep honest.) What was
    /// missing is any
    /// statement that this is REQUIRED. A future rule written with the registry's
    /// default `v?([0-9]+(?:\.[0-9]+)+)` plus `usePrereleases: true` plus a
    /// non-stable channel would have no discriminator at all, and nothing
    /// anywhere would say so.
    ///
    /// Verified against the live Releases API, most recently 2026-09-03. Most are
    /// provable from the URL because GitHub builds an asset URL as
    /// `…/releases/download/<tag>/<name>` — the tag the `versionPattern` matched
    /// is IN the path, so an `.artifact` proof here asserts the same thing the
    /// version pattern does, but against what was actually resolved rather than
    /// against what someone meant to write. FOUR entries are not provable that
    /// way and carry `.recipeAnchor` proofs instead — UTM's beta and T3 Code's
    /// alpha, because neither tag nor asset names a channel, and WhatCable's beta
    /// and CotEditor's beta, because each one's artifact is allowed to be
    /// stable's. See each entry for what its anchor does and does not cover.
    public static let githubProofs: [ChannelProofKey: ChannelArtifactProof] =
        AppRecipeIndex.merged(\.githubChannelProofs, into: "ChannelProofRegistry.githubProofs")

    /// Every `(bundleID, channel)` in the GitHub registry that carries an install
    /// spec and is NOT on stable — the set `githubProofs` has to cover.
    ///
    /// Scoped to install-carrying rules for the same reason the vendor side is:
    /// a detection-only rule resolves no artifact, so there is no wrong build for
    /// it to hand anyone. Today that is no restriction at all — every non-stable
    /// GitHub rule carries an install spec — but writing it as the same
    /// predicate keeps the two registries answerable to one rule.
    public static var channelGitHubRulesWithInstall: [ChannelProofKey] {
        GitHubReleaseRegistry.rules
            .filter { $0.installAssetPattern != nil && $0.channel != .stable }
            .map { ChannelProofKey($0.bundleID, $0.channel) }
    }

    /// Proof of channel identity for the binding population (issue #111).
    ///
    /// A third map rather than entries in `proofs`, for exactly the reason
    /// `githubProofs` is a third: `ChannelProofKey` is `(bundleID, channel)` and
    /// says nothing about which population it came from, so one map would
    /// silently collide the day a bundle id appears in two of them on the same
    /// channel — and the exhaustiveness test would pass while proving the wrong
    /// thing. `channelProofMapsDoNotCollide` measures that for the two recipe
    /// registries; `bindingProofsDoNotCollideWithTheOtherRegistries` extends it to
    /// this one, comparing POPULATIONS and not merely the keys somebody happened
    /// to register — a bundle id that two populations could both serve is the
    /// ambiguity, whether or not both entries exist yet.
    ///
    /// Every entry is a `.recipeAnchor`, and none of them could honestly be an
    /// `.artifact`: none of these vendors puts a CHANNEL TOKEN anywhere in the
    /// artifact, so there is nothing in the response to anchor on. The channel
    /// signal lives entirely in the REQUEST.
    ///
    /// Not "the same filename from the same host" — that is a stronger claim than
    /// the measurement supports and it is false for three of the four. Fork serves
    /// `Fork-2.66.7.dmg` against `Fork-2.69.0.dmg`, Surge puts a per-build hash in
    /// the name, and only TablePlus reuses one filename (`TablePlus.dmg`, under
    /// different build-numbered paths). The filenames DIFFER; what none of them
    /// carries is a token that says which train the build came from — a version
    /// or a hash is not a channel. That is not a
    /// weaker proof than the recipe population gets — Alfred's registered anchor
    /// is `prerelease\.xml` in its endpoint, which is the same assertion about
    /// the same kind of evidence.
    ///
    /// What these DO buy, and what they do not: an anchor here fails in a PR when
    /// the discriminator is edited away, which is the drift that would otherwise
    /// be silent. It cannot notice a vendor retiring the discriminator on their
    /// side — nothing in the response would change shape. `duo verify` does not
    /// sweep this population (it sweeps recipes and rules), so enforcement is
    /// build-time only. Said plainly because the opposite impression is exactly
    /// the "green check nobody should trust" issue #111 warned about.
    public static let bindingProofs: [ChannelProofKey: ChannelArtifactProof] =
        AppRecipeIndex.merged(\.bindingProofs, into: "ChannelProofRegistry.bindingProofs")

    /// The channel bindings whose non-stable resolution needs a proof (issue #111).
    ///
    /// The third install-carrying population. `ChannelBinding` + `SparkleAppcastSource`
    /// reaches an install without passing through either registry above, so neither
    /// `channelRecipesWithInstall` nor `channelGitHubRulesWithInstall` can see it.
    ///
    /// Three predicates, each excluding a group for a DIFFERENT reason — which is
    /// the point, because issue #111's own warning was that a proof table half
    /// full of no-ops is worse than none:
    ///
    ///  1. **Non-stable only**, as everywhere else: a stable resolution has no
    ///     other channel to cross into.
    ///  2. **Not backed by a vendor probe.** OrbStack, Alfred, Tailscale and CapCut
    ///     have bindings, but the binding only picks which `VendorProbeRecipe`
    ///     runs; the install comes from that recipe and `proofs` already covers it.
    ///     Counting them here would register a second proof for the same artifact.
    ///  3. **The channel choice is ours to get wrong** — the resolution carries a
    ///     `feedOverride`, `feedHTTPHeaders`, or hand-declared `sparkleChannelNames`.
    ///
    /// That third predicate is the real discriminator, and it deliberately covers
    /// two shapes rather than one:
    ///
    ///   * **Request-keyed** (Fork, Surge, IINA, TablePlus) — the channel signal
    ///     is which URL we fetched or which header we sent, and nothing in the
    ///     response corroborates it. TablePlus is the sharpest: retire
    ///     `X-Tiny-Beta-Update` and a beta user is served the stable dmg, past
    ///     every gate we have.
    ///   * **Hand-declared tags** (BetterDisplay) — `SparkleAppcastSource` filters
    ///     the feed by `<sparkle:channel>`, but the TAG NAMES come from a per-app
    ///     constant (`BetterDisplayChannel.preTag`/`internalTag`), because its feed
    ///     spells them `pre`/`internal` and no `ReleaseChannel` case does. Retype
    ///     one and `allowedChannels` builds a set matching NOTHING in the feed, so
    ///     the user matches only untagged items and is silently offered STABLE —
    ///     the failure `ResolvedChannel.sparkleChannelNames`' own doc warns about.
    ///     `allowedChannels` cannot validate a name it is handed; an anchor can.
    ///
    /// What predicate 3 EXCLUDES is the binding whose tag is derived rather than
    /// declared: DuoPaste's comes from `ReleaseChannel.rawValue` in shared code,
    /// so there is no per-app constant to mistype and an entry here would be a
    /// literal no-op. That is the distinction — not "channel-tag apps are safe",
    /// which is false, but "a tag nobody hand-wrote has nothing to drift."
    public static var channelBindingsNeedingProof: [ChannelProofKey] {
        ChannelBinding.allResolutions
            .filter { entry in
                entry.resolved.channel != .stable
                    && !ChannelBinding.vendorProbeBackedBindings
                        .contains(entry.bundleID.lowercased())
                    && (entry.resolved.feedOverride != nil
                        || !entry.resolved.feedHTTPHeaders.isEmpty
                        || !entry.resolved.sparkleChannelNames.isEmpty)
            }
            .map { ChannelProofKey($0.bundleID, $0.resolved.channel) }
            // A binding can produce one resolution from several preference
            // combinations — BetterDisplay's `internal` toggle subsumes `pre`, so
            // two of its four reach the same `(bundleID, channel)`. Deduplicated
            // so the population is a set of keys and not a count of ways to get
            // there.
            .reduce(into: [ChannelProofKey]()) { out, key in
                if !out.contains(key) { out.append(key) }
            }
    }

    /// Pre-release tokens that must never appear in a STABLE recipe's installer
    /// URL — the mirror of the same failure, and the worse direction: pushing a
    /// nightly onto someone who chose stable.
    ///
    /// Matched against scheme+host+path only. Several stable URLs carry signed or
    /// opaque query tokens (Raycast's AWS signature, WhatsApp's CDN params) whose
    /// random contents would otherwise produce occasional false hits. The
    /// surrounding `(?<![a-z0-9])`/`(?![a-z0-9])` guards keep `dl.devmate.com` and
    /// friends from tripping a bare substring match.
    ///
    /// ⚠️ **`rc` is NOT in this list, and that is a gap rather than a decision** —
    /// noticed 2026-09-14 while widening CotEditor's beta rule to read the `-rc`
    /// phase of its train. A stable recipe resolving `…/7.1.0-rc/App.dmg` is
    /// reported when the vendor spells that phase `-beta` and passes silently when
    /// they spell it `-rc`, and release candidates are a phase many vendors ship
    /// (CotEditor alone has 38 `-rc*` tags).
    ///
    /// Not closed here because closing it needs a measurement this list cannot be
    /// changed without: `rc` is two characters, this regex runs against every
    /// stable recipe's RESOLVED URL, and a false hit is a red finding filed on
    /// every machine for a recipe working exactly as written — the failure mode
    /// the rest of this file exists to avoid. The measurement is a full
    /// `duo verify` sweep with `rc` added, checking that no stable URL trips it.
    /// CotEditor's own stable rule is not exposed meanwhile: its
    /// `installAssetPattern` is `^CotEditor_[0-9.]+\.dmg$`, which cannot match a
    /// `-rc` asset name at all.
    static let preReleaseTokens =
        #"(?i)(?<![a-z0-9])(beta|canary|nightly|alpha|insider|snapshot|preview|eap|esr|ptb|devedition)(?![a-z0-9])"#
}

/// What `RecipeSanity.recipeAnchorFailure` needs from whatever it is judging.
///
/// The three call sites used to hand it `subject`, a type name, and a surface
/// closure as three independent strings that had to agree; nothing linked them,
/// so `subject: "rule", of: "VendorProbeRecipe", surface: recipe…` compiled and
/// produced a self-contradictory finding. That is the same hand-paired-list shape
/// this file argues against everywhere else, so it is derived instead: conforming
/// a type supplies all three at once and a caller cannot mismatch them.
protocol ChannelAnchorSubject {
    /// What to call one of these in a finding ("recipe", "rule", "binding").
    static var anchorSubjectName: String { get }
    /// The type name to blame when a proof names a field this type does not have.
    static var anchorTypeName: String { get }
    /// The text one named field contributes, or nil when there is no ANCHORABLE
    /// field by that name — see the implementations' own docs.
    func channelAnchorSurface(ofField label: String) -> String?
}

extension VendorProbeRecipe: ChannelAnchorSubject {
    static var anchorSubjectName: String { "recipe" }
    static var anchorTypeName: String { "VendorProbeRecipe" }
}

extension GitHubReleaseRule: ChannelAnchorSubject {
    static var anchorSubjectName: String { "rule" }
    static var anchorTypeName: String { "GitHubReleaseRule" }
}

extension ResolvedChannel: ChannelAnchorSubject {
    static var anchorSubjectName: String { "binding" }
    static var anchorTypeName: String { "ResolvedChannel" }
}

extension RecipeSanity {

    /// The check that catches an install spec resolving the WRONG CHANNEL's build.
    ///
    /// Advisory, like `remoteBehindInstalled` — it reads a hand-maintained marker
    /// table, and a vendor renaming a path should surface as a warning to look at,
    /// not as a hard failure that blocks a sweep. Returns nil when there is
    /// nothing to judge: no install spec, or an install spec that did not resolve
    /// this time (that case is already `ProbeWarning.installURLUnresolved` or
    /// `.installURLTransient`).
    ///
    /// "Did not resolve" is read off `vendorInstallerKind`, NOT off `downloadURL`.
    /// A detection-only result still carries a `downloadURL` — the recipe's page,
    /// or the probe endpoint when it has none (`makeRemoteVersion`) — and judging
    /// that as the artifact turned Discord PTB's rate-limited download redirect
    /// (HTTP 429, 2026-09-15) into "resolved the update manifest, the install may
    /// be crossing channels". `makeRemoteVersion` sets the kind exactly when it
    /// has an install plan.
    public static func crossChannelArtifact(
        recipe: VendorProbeRecipe, remote: RemoteVersion
    ) -> String? {
        guard recipe.install != nil, remote.vendorInstallerKind != nil,
              let url = remote.downloadURL?.absoluteString else {
            return nil
        }
        let key = ChannelProofKey(recipe.bundleID, recipe.channel)

        guard recipe.channel != .stable else {
            // Strip the query: only the host and path are the vendor's own naming.
            guard let comps = URLComponents(string: url) else { return nil }
            let bare = "\(comps.scheme ?? "")://\(comps.host ?? "")\(comps.path)"
            guard bare.range(of: ChannelProofRegistry.preReleaseTokens,
                             options: .regularExpression) != nil else { return nil }
            return "stable recipe resolved what looks like a PRE-RELEASE artifact: \(bare)"
        }

        guard let proof = ChannelProofRegistry.proofs[key] else {
            return "no channel proof registered for \(key) — nothing checks that its "
                + "install spec resolves its own channel's build rather than stable's"
        }

        switch proof {
        case .artifact(let pattern):
            guard url.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
            else { return nil }
            return "resolved \(url), which carries no \(recipe.channel.rawValue) marker "
                + "(expected /\(pattern)/) — the install may be crossing channels"

        case .recipeAnchor(let pattern, let fields):
            // Each named field's own text, never the join — see
            // `VendorProbeRecipe.channelAnchorFields`. The fields themselves are
            // still derived by reflection; the list this replaced named three of
            // them by hand and had already missed `entryStartPattern`.
            return recipeAnchorFailure(
                pattern: pattern, fields: fields, channel: recipe.channel, subject: recipe)
        }
    }

    /// The same check for a `GitHubReleaseRule` (issue #101).
    ///
    /// The GitHub sweep passed `sanity: { _, _ in [] }`, so the one registry
    /// where a tag can outrun what it claims to be was also the one with no
    /// second opinion about WHICH channel it resolved. A vendor recipe that
    /// skipped its proof got a hard finding; a GitHub rule in the same situation
    /// got silence, and the asymmetry was invisible exactly where it mattered —
    /// at the point where somebody adds a rule.
    ///
    /// Advisory, like the recipe overload. Returns nil when there is nothing to
    /// judge: a detection-only rule resolves no artifact, and its `downloadURL`
    /// is the repository's releases PAGE rather than a build, so there is no
    /// wrong thing for it to have handed anyone. The same holds for a rule that
    /// names an install asset this release does not carry — `GitHubReleasesSource`
    /// falls back to that page and leaves `vendorInstallerKind` nil — which is why
    /// the guard reads the kind, as the recipe overload does.
    public static func crossChannelArtifact(
        rule: GitHubReleaseRule, remote: RemoteVersion
    ) -> String? {
        guard rule.installAssetPattern != nil, remote.vendorInstallerKind != nil,
              let url = remote.downloadURL?.absoluteString else { return nil }
        let key = ChannelProofKey(rule.bundleID, rule.channel)

        guard rule.channel != .stable else {
            // The mirror direction is deliberately NOT checked here, and that is
            // a measurement rather than an oversight. `preReleaseTokens` matches
            // scheme+host+path, and every GitHub asset URL carries `owner/repo`
            // in its path — so a stable rule in a repo whose name contains one of
            // those words would be a permanent false accusation. The vendor side
            // does not have that problem because its paths are the vendor's own.
            // A stable GitHub rule's protection is `/releases/latest`, which
            // GitHub computes with prereleases excluded (and `stableOnly` for the
            // list fallback — see `GitHubReleasesSource.resolve`).
            return nil
        }

        guard let proof = ChannelProofRegistry.githubProofs[key] else {
            return "no channel proof registered for \(key) — nothing checks that its "
                + "install spec resolves its own channel's build rather than stable's"
        }

        switch proof {
        case .artifact(let pattern):
            guard url.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
            else { return nil }
            return "resolved \(url), which carries no \(rule.channel.rawValue) marker "
                + "(expected /\(pattern)/) — the install may be crossing channels"

        case .recipeAnchor(let pattern, let fields):
            return recipeAnchorFailure(
                pattern: pattern, fields: fields, channel: rule.channel, subject: rule)
        }
    }

    /// The same check for a `ChannelBinding` resolution (issue #111).
    ///
    /// Deliberately NOT an overload of `crossChannelArtifact`, and not given a
    /// `RemoteVersion`: there is no artifact to inspect. No binding in this
    /// population resolves an artifact that names its channel — the filenames
    /// differ, but by version or by build hash, never by train — so a URL check
    /// would be the vacuous kind of proof this file exists to refuse. What is
    /// checked is the request the resolution will make.
    ///
    /// Stable resolutions return nil rather than being checked against
    /// `preReleaseTokens` the way a stable recipe is, and the honest reason is
    /// that the check would not mean anything here, NOT that these URLs would
    /// trip it. (Measured 2026-08-28: none of the four stable feeds contains a
    /// pre-release token — `feed-stable.xml`, `appcast.xml`, `appcast-signed.xml`,
    /// and TablePlus has no feed override at all. An earlier revision of this
    /// comment claimed two of them did; that was wrong.) The reason to skip it is
    /// that a token scan over a REQUEST says nothing about which train the server
    /// answers with — Surge's stable and beta feeds differ by a filename we chose
    /// to fetch, not by anything the vendor asserts. The stable direction is
    /// protected by each resolver falling back to its stable feed when the
    /// preference is unreadable, and `everyBindingProofFailsOnItsOwnStableSibling`
    /// pins it from the other side.
    public static func crossChannelBinding(
        binding: ResolvedChannel, bundleID: String
    ) -> String? {
        guard binding.channel != .stable else { return nil }
        let key = ChannelProofKey(bundleID, binding.channel)
        // Matched case-insensitively on the bundle id, like `ChannelBinding.resolve`
        // and for the same reason it documents: a `CFBundleIdentifier` is
        // case-insensitive and TablePlus ships `com.tinyapp.TablePlus` while its
        // prefs (and this registry) use the lower-cased spelling. A case-sensitive
        // lookup here would tell the first caller that passes a real
        // `InstalledApp.bundleID` that its sharpest-case proof is unregistered.
        let proofEntry = ChannelProofRegistry.bindingProofs[key]
            ?? ChannelProofRegistry.bindingProofs.first {
                $0.key.bundleID.lowercased() == bundleID.lowercased()
                    && $0.key.channel == binding.channel
            }?.value
        guard let proof = proofEntry else {
            return "no channel proof registered for \(key) — nothing checks that its "
                + "appcast request is the one that serves its own channel"
        }
        switch proof {
        case .artifact(let pattern):
            return "\(key) is proven by .artifact(/\(pattern)/), which cannot hold for a "
                + "binding: stable and non-stable resolve the same artifact from the same "
                + "host, so the URL never names the channel — use .recipeAnchor"
        case .recipeAnchor(let pattern, let fields):
            return recipeAnchorFailure(
                pattern: pattern, fields: fields, channel: binding.channel, subject: binding)
        }
    }

    /// Match a field-scoped `.recipeAnchor` and describe the first way it fails.
    ///
    /// Shared by both overloads so the two registries cannot drift into different
    /// notions of what an anchor asserts — the asymmetry issue #101 was filed
    /// about, in miniature. The subject's own name and type name come from
    /// `ChannelAnchorSubject` rather than from arguments, so a caller cannot pair
    /// one type's surface with another's label either.
    ///
    /// EVERY named field must match. An anchor names the fields its channel
    /// identity lives in, so a field that stopped carrying the token is exactly
    /// the drift the proof exists to report, even while a sibling field still
    /// carries it (issue #110).
    ///
    /// The two degenerate inputs are findings, not passes. An empty `fields`
    /// would make the loop vacuous, and a name that is not an anchorable field —
    /// a typo, a renamed field, or one of the labelling `nonAnchorFields` —
    /// yields nothing to match against. Both describe a proof that could not have
    /// failed for any input, which is the one outcome worse than no proof: it
    /// reads as green forever. `everyRegisteredAnchorNamesRealFields` fails on
    /// them in a PR; this is the runtime half, for a proof written after it.
    static func recipeAnchorFailure<Subject: ChannelAnchorSubject>(
        pattern: String,
        fields: Set<String>,
        channel: ReleaseChannel,
        subject: Subject
    ) -> String? {
        let name = Subject.anchorSubjectName
        guard !fields.isEmpty else {
            return "the anchor /\(pattern)/ names no fields at all, so it cannot fail "
                + "and proves nothing about which channel the \(name) reads — name the "
                + "field(s) that tie it to \(channel.rawValue)"
        }
        for label in fields.sorted() {
            guard let text = subject.channelAnchorSurface(ofField: label) else {
                return "the anchor /\(pattern)/ names '\(label)', which is not an "
                    + "anchorable field of \(Subject.anchorTypeName) (no such field, or "
                    + "one that only labels the \(name)) — the proof cannot fail as written"
            }
            guard text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
            else { continue }
            return "the \(name)'s \(label) is no longer anchored on /\(pattern)/ — "
                + "nothing there ties its \(channel.rawValue) install to that channel"
        }
        return nil
    }
}
