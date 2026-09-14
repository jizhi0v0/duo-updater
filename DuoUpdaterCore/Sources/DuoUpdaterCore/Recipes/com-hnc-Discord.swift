import Foundation

enum com_hnc_Discord {
    static let set = AppRecipeSet(
        family: "com-hnc-Discord",
        probes: [
        // History: docs/app-audits/com-hnc-Discord.md#历史与实测
        // Discord — official update manifest (channel=stable, platform=osx). The
        // version lives ONLY as the JSON array (e.g. `host_version:[0,0,393]`) and as
        // a path segment in each distro `url` (e.g. …/osx/universal/0.0.393/…). The array
        // is unusable — extractVersion takes capture group 1 only and can't join
        // three groups (it'd read "0") — so we anchor to the distro url path,
        // which carries the whole X.Y.Z in one group. Every url in the body (full
        // + deltas + per-module) targets the same destination version, so first
        // match is correct; the delta SOURCE (e.g. 0.0.392) never appears as a
        // /universal/<v>/ segment. Discord self-updates via its own host updater.
        // ptb/canary ship as separate bundle ids with their own channel=ptb|canary
        // endpoints — their dedicated recipes follow below. One-click NOTE: the
        // manifest carries only `.distro` module files, not an app dmg, so the
        // install uses Discord's SEPARATE public download endpoint —
        // `discord.com/api/download?platform=osx&format=dmg` — which 302s to the same
        // version's `…/apps/osx/<ver>/Discord.dmg`. ptb/canary install the same way
        // from their own download redirects (below).
        //
        // The patterns do not name the CDN HOST, which Discord has changed before
        // (History has the break it caused). The channel lives in the URL PATH
        // (`/distro/app/stable/…`), which is the part that actually has to be
        // pinned: it is what keeps a channel's recipe off its siblings' numbers.
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
        // pattern only swaps the channel literal). Discord self-updates via its own
        // host updater; one-click is the fallback, from each channel's own download
        // redirect. Canary's "Discord Canary" name
        // detects as .canary via the standalone word; PTB needs the dedicated
        // `.ptb` channel (no word/suffix otherwise carries "Public Test Build").
        VendorProbeRecipe(
            bundleID: "com.hnc.DiscordPTB",
            url: URL(string: "https://updates.discord.com/distributions/app/manifests/latest?channel=ptb&platform=osx&arch=x64")!,
            mode: .responseBody,
            versionPattern: #"discordapp\.net/distro/app/ptb/osx/universal/([0-9]+(?:\.[0-9]+){1,3})/"#,
            changelogURL: URL(string: "https://discord.com/blog"),
            // One-click: `https://discord.com/api/download/ptb` 302s to a versioned
            // `…/apps/osx/<ver>/DiscordPTB.dmg`, holding `Discord PTB.app` — bundle id
            // com.hnc.DiscordPTB, Team 53Q6R32WPB, accepted by spctl.
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
        ],
        appStoreCases: [
        // Discord — `kind == "software"`, installable on Apple Silicon Macs
        // as the wrapped iOS binary. Exercises
        // `remoteVersion(checkMacCompat: true)`, which reads
        // `isIOSBinaryMacOSCompatible` and `appPlatforms` off the plain (non
        // `?platform=mac`) product page. The listing measured as a true negative
        // (flag false, no Mac in its Compatibility section; History has the
        // measurement), which is what keeps this case a useful probe of the
        // `false` verdict.
        //
        // Do not explain that `false` as "Discord ships a native build": the App
        // Store listing publishes no Mac binary (Discord's Mac app is a direct
        // download, off-store), and a native Mac build is precisely the shape that
        // makes `isIOSBinaryMacOSCompatible == false` mean "supported", which is
        // the bug `MacCompatibilityReading` exists to fix.
        MacAppStoreProbeCase(
            bundleID: "com.hammerandchisel.discord", trackId: 985746746,
            expectedKind: "software", route: .wrappedIOS),
        ],
        channelProofs: [
        ChannelProofKey("com.hnc.DiscordPTB", .ptb): .artifact(#"^https://ptb\."#),
        ChannelProofKey("com.hnc.DiscordCanary", .canary): .artifact(#"^https://canary\."#),
        ])
}
