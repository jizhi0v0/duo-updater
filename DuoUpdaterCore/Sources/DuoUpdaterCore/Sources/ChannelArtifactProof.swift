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
    /// block of a shared feed): the regex must appear in the recipe's endpoint
    /// URL, version pattern, or install URL source.
    case recipeAnchor(String)
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
        ChannelProofKey("com.jetbrains.intellij-EAP", .preview): .recipeAnchor(#"type=eap"#),
        // Android Studio: each preview channel accepts builds at its own quality OR
        // MORE STABLE (the stability floor documented on the recipes), so the marker
        // has to be that whole ladder, not just the channel's own name — Canary
        // resolves the newest of {Canary, Beta, RC}, Beta the newest of {Beta, RC}.
        // That is not a bug being papered over: it is why a Canary install correctly
        // moves onto `2026.1.4 RC 2` when it is newer than any open Canary, which is
        // exactly what the feed served on 2026-08-26. Google's Beta train has in
        // practice shipped RELEASE CANDIDATES for years (no `Beta` item since
        // 2025-03-18), so `-rc<N>-` is the marker actually seen on both.
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
        ChannelProofKey("com.tencent.wechatdevtools", .rc): .recipeAnchor(#""id":.*"rc""#),

        // MARK: Everything else
        ChannelProofKey("dev.warp.Warp-Preview", .preview): .artifact(#"channel=preview"#),
        ChannelProofKey("io.tailscale.ipn.macsys", .unstable): .artifact(#"/unstable/"#),
        ChannelProofKey("io.tailscale.ipn.macsys", .rc): .artifact(#"/release-candidate/"#),
        ChannelProofKey("com.figma.DesktopBeta", .beta): .artifact(#"/beta/FigmaBeta-"#),
        // Alfred serves stable and pre-release from two endpoints that frequently
        // carry the SAME build (both were 5.7.3 (2320) on 2026-08-09), and the
        // tarball name never mentions a channel — only the endpoint can prove it.
        ChannelProofKey("com.runningwithcrayons.Alfred", .beta): .recipeAnchor(#"prerelease\.xml"#),
        // OrbStack publishes one appcast with a `<sparkle:channel>` tag per item and
        // promotes the same dmg across channels (all three were v2.2.3_20963 on
        // 2026-08-09). The channel tag the patterns are anchored to is the proof.
        ChannelProofKey("dev.kdrag0n.MacVirt", .beta): .recipeAnchor(#"<sparkle:channel>beta"#),
        ChannelProofKey("dev.kdrag0n.MacVirt", .canary): .recipeAnchor(#"<sparkle:channel>canary"#),
        // Longbridge splits the two trains by CDN path — `/longbridge-desktop/
        // preview/` vs `/stable/` — and the artifact filename carries the
        // `-preview.N` suffix on top of that, so the URL names the channel twice.
        // Unusually for a copied-from-stable recipe, the two manifests cannot even
        // match each other's version pattern (stable's requires a closing quote
        // straight after the numeric version; preview's requires the suffix), so a
        // cross-train resolve fails closed rather than silently succeeding.
        ChannelProofKey("com.longbridge.app.desktop.preview", .preview):
            .artifact(#"/longbridge-desktop/preview/"#),
    ]

    /// Every `(bundleID, channel)` in the vendor registry that carries an install
    /// spec and is NOT on stable — the set `proofs` has to cover.
    public static var channelRecipesWithInstall: [ChannelProofKey] {
        VendorProbeRegistry.recipes
            .filter { $0.install != nil && $0.channel != .stable }
            .map { ChannelProofKey($0.bundleID, $0.channel) }
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

        case .recipeAnchor(let pattern):
            let surface = [
                recipe.url.absoluteString,
                recipe.versionPattern,
                recipe.install.map { String(describing: $0.urlSource) } ?? "",
            ].joined(separator: "\n")
            guard surface.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
            else { return nil }
            return "recipe is no longer anchored on /\(pattern)/ — nothing ties its "
                + "\(recipe.channel.rawValue) install to that channel"
        }
    }
}
