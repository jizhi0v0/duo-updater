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
    public static let proofs: [ChannelProofKey: ChannelArtifactProof] = [
        // MARK: Editors / IDEs
        ChannelProofKey("com.microsoft.VSCodeInsiders", .preview): .artifact(#"/download/insider/"#),
        // EAP dmgs are named `idea-<build>-aarch64.dmg` — the same shape stable
        // uses, so the filename proves nothing. The endpoint does: `type=eap` vs
        // stable's `type=release`, and the install pattern reads the dmg out of
        // that response body.
        //
        // `url` alone, and that is the honest scope rather than a weaker one: the
        // response to `type=eap` contains ONLY EAP builds, so `versionPattern`
        // (`"build": "…"`) and the install pattern (`"macM1" … "link"`) carry no
        // channel token at all. Naming either would assert something this recipe
        // cannot satisfy. (The install pattern is byte-identical to the stable
        // recipe's; the version pattern is NOT — stable reads `"version"` and this
        // reads `"build"`, because `versionIsBuild` compares the build. That
        // difference is deliberate and says nothing about the channel.)
        // What naming `url` buys is that swapping the endpoint back to
        // `type=release` fails the proof instead of passing on patterns that never
        // mentioned a channel.
        ChannelProofKey("com.jetbrains.intellij-EAP", .preview):
            .recipeAnchor(#"type=eap"#, in: ["url"]),
        // Android Studio: each preview channel accepts builds at its own quality OR
        // MORE STABLE (the stability floor documented on the recipes), so the marker
        // has to be that whole ladder, not just the channel's own name — Canary
        // resolves the newest of {Canary, Beta, RC}, Beta the newest of {Beta, RC}.
        // That is not a bug being papered over: an RC genuinely is the legitimate
        // answer for a Canary install once it is the highest build on the ladder —
        // e.g. before a newer feature version's Canary train has opened. (It is NOT
        // legitimate merely because the RC was the most recently PUBLISHED item —
        // the feed is ordered by publish date, not by version, which is what made
        // the canary recipe land on `2026.1.4 RC 2` over the already-published,
        // already-newer `2026.2.1 Canary 2` on 2026-08-26; see issue #76 and
        // `VendorProbeRecipe.entryStartPattern`, which now resolves that correctly.)
        // Google's Beta train has in practice shipped RELEASE CANDIDATES for years
        // (no `Beta` item since 2025-03-18), so `-rc<N>-` is the marker actually
        // seen on both.
        // What the marker still excludes is the pair that WOULD be a cross-channel
        // install: `Release` (`android-studio-quail3-mac_arm.dmg`) and `Patch`
        // (`…-patch1-mac_arm.dmg`) — neither carries a ladder token.
        ChannelProofKey("com.google.android.studio", .canary):
            .artifact(#"-(canary|beta|rc)[0-9]*-mac"#),
        ChannelProofKey("com.google.android.studio", .beta): .artifact(#"-(beta|rc)[0-9]*-mac"#),
        ChannelProofKey("io.dcloud.HBuilderXAlpha", .alpha): .artifact(#"-alpha\."#),

        // MARK: Browsers
        ChannelProofKey("com.google.Chrome.beta", .beta): .artifact(#"/beta/googlechromebeta\.dmg"#),
        ChannelProofKey("com.google.Chrome.dev", .dev): .artifact(#"/dev/googlechromedev\.dmg"#),
        ChannelProofKey("com.google.Chrome.canary", .canary): .artifact(#"/canary/googlechromecanary\.dmg"#),
        ChannelProofKey("com.brave.Browser.beta", .beta): .artifact(#"beta-arm64/.*Brave-Browser-Beta"#),
        ChannelProofKey("com.brave.Browser.nightly", .nightly): .artifact(#"nightly-arm64/.*Brave-Browser-Nightly"#),
        ChannelProofKey("com.vivaldi.Vivaldi.snapshot", .preview): .artifact(#"/snapshot-auto/"#),
        ChannelProofKey("com.microsoft.edgemac.Beta", .beta): .artifact(#"MicrosoftEdgeBeta-"#),
        ChannelProofKey("com.microsoft.edgemac.Dev", .dev): .artifact(#"MicrosoftEdgeDev-"#),

        // MARK: Mozilla
        // The installed bundles hide their channel (`CFBundleShortVersionString`
        // drops the `b`/`esr` suffix — see `ReleaseChannel.detect`), but the
        // download paths do not: Beta sits under a `<major>.0b<N>` release dir, ESR
        // under an `esr` one, Developer Edition under `/devedition/`, Nightly under
        // `/nightly/`. Firefox Beta and Developer Edition resolve the SAME upstream
        // version (154.0b8), so only the `/devedition/` vs `/firefox/` path tells
        // them apart — which is exactly why the marker is a path, not a version.
        ChannelProofKey("org.mozilla.firefox", .beta): .artifact(#"/firefox/releases/[0-9.]+b[0-9]+/"#),
        ChannelProofKey("org.mozilla.firefox", .esr): .artifact(#"/firefox/releases/[0-9.]+esr/"#),
        ChannelProofKey("org.mozilla.firefoxdeveloperedition", .dev): .artifact(#"/devedition/releases/"#),
        ChannelProofKey("org.mozilla.nightly", .nightly): .artifact(#"/firefox/nightly/"#),
        ChannelProofKey("org.mozilla.thunderbirdbeta", .beta): .artifact(#"/thunderbird/releases/[0-9.]+b[0-9]+/"#),
        ChannelProofKey("org.mozilla.thunderbird", .esr): .artifact(#"/thunderbird/releases/[0-9.]+esr/"#),
        ChannelProofKey("org.mozilla.thunderbird-daily", .nightly): .artifact(#"/thunderbird/nightly/"#),

        // MARK: Media
        // CapCut's two tracks share one bundle id, one app name and one endpoint —
        // the beta build does not even carry a channel word in the version
        // `ReleaseChannel.detect()` reads (`9.3.4531`). The artifact name is where
        // the vendor does say it: stable ships `…_capcutpc_0_creatortool.dmg` and
        // beta `…_capcutpc_beta_creatortool.dmg`, and `capcutpc_beta` was read off
        // the beta bundle's own `Contents/Resources/PackageConfig.plist` →
        // `Channel Name` after mounting it (2026-08-27), so this is the vendor's
        // own token rather than a filename convention we inferred.
        ChannelProofKey("com.lemon.lvoverseas", .beta): .artifact(#"_capcutpc_beta_"#),

        // MARK: Chat / messaging
        ChannelProofKey("org.whispersystems.signal-desktop-beta", .beta): .artifact(#"signal-desktop-beta-mac-"#),
        ChannelProofKey("im.riot.nightly", .nightly): .artifact(#"/nightly/"#),
        ChannelProofKey("com.hnc.DiscordPTB", .ptb): .artifact(#"^https://ptb\."#),
        ChannelProofKey("com.hnc.DiscordCanary", .canary): .artifact(#"^https://canary\."#),

        // MARK: WeChat DevTools (微信开发者工具)
        // Nightly builds live under their own CDN prefix (`/WechatWebDev/nightly/…`)
        // while Stable and RC are both served from `/WechatWebDev/release/<hash>/`,
        // so only Nightly can be proven from the URL. RC's artifact is byte-for-byte
        // shaped like Stable's — same host, same directory, same filename template,
        // differing only in the version — so its proof is the anchor instead: the
        // recipe reads the `"id": "rc"` block of the vendor's own `config.json`, and
        // if that anchor ever stops being there the recipe would start reading
        // whichever channel `config.json` lists first (Stable).
        ChannelProofKey("com.tencent.wechatdevtools", .nightly): .artifact(#"/WechatWebDev/nightly/"#),
        // Named on BOTH halves, which is what issue #110 was about. The token sits
        // in `versionPattern` and in the install `bodyPattern`, and matching the
        // joined surface passed on either — so if the install regex alone were
        // rewritten (the vendor renames the block, someone retypes it), the version
        // pattern would keep this green while the install fell back to whichever
        // channel `config.json` lists first. Which is Stable, into an RC install,
        // through every gate we have. Requiring both means the half that picks the
        // artifact is checked as the half that picks the artifact.
        ChannelProofKey("com.tencent.wechatdevtools", .rc):
            .recipeAnchor(#""id":.*"rc""#, in: ["versionPattern", "install"]),

        // MARK: Everything else
        ChannelProofKey("dev.warp.Warp-Preview", .preview): .artifact(#"channel=preview"#),
        ChannelProofKey("io.tailscale.ipn.macsys", .unstable): .artifact(#"/unstable/"#),
        ChannelProofKey("io.tailscale.ipn.macsys", .rc): .artifact(#"/release-candidate/"#),
        ChannelProofKey("com.figma.DesktopBeta", .beta): .artifact(#"/beta/FigmaBeta-"#),
        // Alfred serves stable and pre-release from two endpoints that frequently
        // carry the SAME build (both were 5.7.3 (2320) on 2026-08-09), and the
        // tarball name never mentions a channel — only the endpoint can prove it.
        // Endpoint-scoped for the same reason as IntelliJ EAP: this recipe's
        // install `bodyPattern` is byte-identical to the stable Alfred recipe's
        // (same plist shape, different endpoint) and its `versionPattern` differs
        // only in strictness — neither names a channel. So the endpoint is not
        // merely the best evidence, it is the only evidence there is, and the
        // proof says so.
        ChannelProofKey("com.runningwithcrayons.Alfred", .beta):
            .recipeAnchor(#"prerelease\.xml"#, in: ["url"]),
        // OrbStack publishes one appcast with a `<sparkle:channel>` tag per item and
        // promotes the same dmg across channels (all three were v2.2.3_20963 on
        // 2026-08-09). The channel tag the patterns are anchored to is the proof.
        // Both halves named, like WeChat RC and for the same reason: one appcast
        // serves all three channels, and the `<sparkle:channel>` prefix on the
        // version pattern and on the install pattern is what confines each to its
        // own `<item>`. Losing it from the install pattern alone would let the
        // enclosure match the first item in the feed regardless of channel.
        ChannelProofKey("dev.kdrag0n.MacVirt", .beta):
            .recipeAnchor(#"<sparkle:channel>beta"#, in: ["versionPattern", "install"]),
        ChannelProofKey("dev.kdrag0n.MacVirt", .canary):
            .recipeAnchor(#"<sparkle:channel>canary"#, in: ["versionPattern", "install"]),
        // Longbridge splits the two trains by CDN path — `/longbridge-desktop/
        // preview/` vs `/stable/` — and the artifact filename carries the
        // `-preview.N` suffix on top of that, so the URL names the channel twice.
        // Unusually for a copied-from-stable recipe, the two manifests cannot even
        // match each other's version pattern (stable's requires a closing quote
        // straight after the numeric version; preview's requires the suffix), so a
        // cross-train resolve fails closed rather than silently succeeding.
        ChannelProofKey("com.longbridge.app.desktop.preview", .preview):
            .artifact(#"/longbridge-desktop/preview/"#),
        // Termius Beta already has an independent bundle id (`com.termius-beta.mac`
        // vs stable's `com.termius-dmg.mac`), so this is belt-and-suspenders: the
        // resolved install URL's own path names the channel.
        ChannelProofKey("com.termius-beta.mac", .beta): .artifact(#"/mac-beta-universal/"#),
    ]

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
    /// pattern the author happened to write, and nothing re-derives it. All three
    /// rules below gate the channel in their `versionPattern` — a stable tag
    /// cannot satisfy `-pre`, `-beta<N>` or `-insider` — which is why the live
    /// sweep of 2026-08-27 found nothing misresolving. What was missing is any
    /// statement that this is REQUIRED. A future rule written with the registry's
    /// default `v?([0-9]+(?:\.[0-9]+)+)` plus `usePrereleases: true` plus a
    /// non-stable channel would have no discriminator at all, and nothing
    /// anywhere would say so.
    ///
    /// Verified against the live Releases API 2026-08-28. All three are provable
    /// from the URL because GitHub builds an asset URL as
    /// `…/releases/download/<tag>/<name>` — the tag the `versionPattern` matched
    /// is IN the path, so an `.artifact` proof here asserts the same thing the
    /// version pattern does, but against what was actually resolved rather than
    /// against what someone meant to write.
    public static let githubProofs: [ChannelProofKey: ChannelArtifactProof] = [
        // `Zed-aarch64.dmg` is byte-identical in name to stable's — the tag is
        // the only discriminator, and it is in the path:
        // `…/download/v1.18.0-pre/Zed-aarch64.dmg`.
        ChannelProofKey("dev.zed.Zed-Preview", .preview): .artifact(#"/download/v[0-9.]+-pre/"#),
        // Likewise `GitHub.Desktop-arm64.zip`:
        // `…/download/release-3.6.5-beta1/GitHub.Desktop-arm64.zip`.
        ChannelProofKey("com.github.GitHubClient", .beta):
            .artifact(#"/download/release-[0-9.]+-beta[0-9]+/"#),
        // VSCodium Insiders names the channel in the tag AND in the asset filename,
        // and lives in its own repository besides.
        //
        // Anchored to the tag segment on purpose. A bare `-insider` would be
        // satisfied by `VSCodium/vscodium-insiders` in the path of EVERY url this
        // rule can ever resolve, which is the same fact the stable branch of
        // `crossChannelArtifact(rule:remote:)` below refuses to check on — read
        // there it prevents a false accusation, read here it would have been a
        // permanent false acquittal, and the proof could not have failed for any
        // input. Live releases could not show this: every real tag in that repo
        // carries `-insider` too, so the loose pattern and the anchored one agree
        // on all 57 of them and disagree only on the artifact this exists to
        // catch. Caught in adversarial review of #101, not by measurement.
        ChannelProofKey("com.vscodium.VSCodiumInsiders", .preview):
            .artifact(#"/download/[^/]*-insider"#),
    ]

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
    /// thing. `channelProofMapsDoNotCollide` measures that rather than assuming it.
    ///
    /// Every entry is a `.recipeAnchor`, and none of them could honestly be an
    /// `.artifact`: for all four of these vendors, stable and beta are the same
    /// filename from the same host, so there is no token in the response to
    /// anchor on. The channel signal lives entirely in the REQUEST. That is not a
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
    public static let bindingProofs: [ChannelProofKey: ChannelArtifactProof] = [
        // Fork ships two entirely separate feed documents. Note which is which:
        // the BETA train is the unsuffixed `feed.xml` (also the code-signed
        // `SUFeedURL`, and the shipped default), and stable is the one that had to
        // be given a suffix. So the anchor is the absence of that suffix, and it
        // discriminates precisely because `feed-stable.xml` does not contain the
        // literal `feed.xml`.
        ChannelProofKey("com.DanPristupov.Fork", .beta):
            .recipeAnchor(#"/update/feed\.xml"#, in: ["feedOverride"]),
        ChannelProofKey("com.nssurge.surge-mac", .beta):
            .recipeAnchor(#"appcast-signed-beta\.xml"#, in: ["feedOverride"]),
        ChannelProofKey("com.colliderli.iina", .beta):
            .recipeAnchor(#"appcast-beta\.xml"#, in: ["feedOverride"]),
        // TablePlus is the sharpest case in the population and the only
        // header-keyed one. Stable and beta share ONE feed URL; the server decides
        // which builds to return from a request header, and the VALUE is
        // load-bearing — the app sends the literal `true` and the server treats
        // `1`/`yes` as stable (`TablePlusChannel`). So the anchor covers the value,
        // not just the field name, which is why `ResolvedChannel.anchorLines`
        // renders a header as one `key: value` line instead of two.
        ChannelProofKey("com.tinyapp.tableplus", .beta):
            .recipeAnchor(#"X-Tiny-Beta-Update:\s*true"#, in: ["feedHTTPHeaders"]),
    ]

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
    ///  3. **Request-keyed only** — `feedOverride` or `feedHTTPHeaders`. This is
    ///     the real discriminator. A channel-TAG binding (DuoPaste, BetterDisplay)
    ///     is already protected structurally: `SparkleAppcastSource.allowedChannels`
    ///     narrows the feed to the `<sparkle:channel>` values the user opted into,
    ///     in code that runs for every such app whether or not anyone remembered
    ///     to register anything — a stronger guarantee than a hand-written regex,
    ///     and one that would be a literal no-op to restate here.
    ///
    /// What is left is exactly the population where the channel signal lives in
    /// the REQUEST and nothing in the response corroborates it: the feed-swap and
    /// header-keyed apps. TablePlus is the sharpest — stable and beta come from
    /// the same host with the same filename, differing only in build number, so
    /// if the vendor retires `X-Tiny-Beta-Update` a beta user is served the stable
    /// dmg and every gate we have passes.
    public static var channelBindingsNeedingProof: [ChannelProofKey] {
        ChannelBinding.allResolutions
            .filter { entry in
                entry.resolved.channel != .stable
                    && !ChannelBinding.vendorProbeBackedBindings
                        .contains(entry.bundleID.lowercased())
                    && (entry.resolved.feedOverride != nil
                        || !entry.resolved.feedHTTPHeaders.isEmpty)
            }
            .map { ChannelProofKey($0.bundleID, $0.resolved.channel) }
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
    /// nothing to judge: no install spec, or no resolved URL (that case is already
    /// `ProbeWarning.installURLUnresolved`).
    public static func crossChannelArtifact(
        recipe: VendorProbeRecipe, remote: RemoteVersion
    ) -> String? {
        guard recipe.install != nil, let url = remote.downloadURL?.absoluteString else {
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
    /// wrong thing for it to have handed anyone.
    public static func crossChannelArtifact(
        rule: GitHubReleaseRule, remote: RemoteVersion
    ) -> String? {
        guard rule.installAssetPattern != nil,
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
    /// `RemoteVersion`: there is no artifact to inspect. For every binding in this
    /// population stable and non-stable resolve the same filename from the same
    /// host, so a URL check would be the vacuous kind of proof this file exists to
    /// refuse. What is checked is the request the resolution will make.
    ///
    /// Stable resolutions return nil rather than being checked against
    /// `preReleaseTokens` the way a stable recipe is. That is measured, not lazy:
    /// two of these four bindings' STABLE feeds would trip a bare token match —
    /// Surge's `appcast-signed.xml` sits beside `appcast-signed-beta.xml` on the
    /// same path, and a token scan over a feed URL says nothing about which train
    /// the server answers with. The stable direction here is protected by the
    /// resolver returning the stable feed when the preference is unreadable, which
    /// `everyBindingProofFailsOnItsOwnStableSibling` pins from the other side.
    public static func crossChannelBinding(
        binding: ResolvedChannel, bundleID: String
    ) -> String? {
        guard binding.channel != .stable else { return nil }
        let key = ChannelProofKey(bundleID, binding.channel)
        guard let proof = ChannelProofRegistry.bindingProofs[key] else {
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
