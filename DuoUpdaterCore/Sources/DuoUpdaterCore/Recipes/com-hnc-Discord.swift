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
        // endpoints — their dedicated recipes follow below.
        //
        // One-click: Discord's distro tree carries each version's app dmg right
        // beside the manifest's own `full.distro` url —
        // `<distro host>/distro/app/<channel>/osx/universal/<ver>/<App>.dmg` — so
        // the install is pinned to the version this probe reported, not to
        // whatever "latest" a redirect answers with at download time. Stable's
        // host is `dl.discordapp.net` (the one this manifest's urls name; History
        // has the times it moved). NOT `discord.com/api/download?…&format=dmg`:
        // that redirect now lands on a Linux-only `installers/latest` endpoint,
        // which answers `format=dmg` with HTTP 400 — and without the parameter it
        // serves a build behind the manifest. History has the measurements.
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
                urlSource: .versionTemplate(
                    "https://dl.discordapp.net/distro/app/stable/osx/universal/{version}/Discord.dmg"),
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
            // One-click: PTB's own distro host, pinned to the version the probe
            // resolved — `ptb.dl2.discordapp.net/distro/app/ptb/osx/universal/
            // <ver>/DiscordPTB.dmg`, holding `Discord PTB.app` — bundle id
            // com.hnc.DiscordPTB, Team 53Q6R32WPB, accepted by spctl. The `ptb.`
            // host is also what the channel proof matches.
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://ptb.dl2.discordapp.net/distro/app/ptb/osx/universal/{version}/DiscordPTB.dmg"),
                kind: .dmg),
            channel: .ptb),
        VendorProbeRecipe(
            bundleID: "com.hnc.DiscordCanary",
            url: URL(string: "https://updates.discord.com/distributions/app/manifests/latest?channel=canary&platform=osx&arch=x64")!,
            mode: .responseBody,
            versionPattern: #"discordapp\.net/distro/app/canary/osx/universal/([0-9]+(?:\.[0-9]+){1,3})/"#,
            changelogURL: URL(string: "https://discord.com/blog"),
            // One-click: the canary track's distro path, pinned to the resolved
            // version. Canary publishes its dmg ONLY under `/distro/…` — its
            // `/apps/osx/<ver>/DiscordCanary.dmg` answers 403 — so the distro path
            // is the versioned address for it, not a "latest" redirect.
            // `Discord Canary.app`, bundle id com.hnc.DiscordCanary, Team
            // 53Q6R32WPB, accepted by spctl; the `canary.` host is what the channel
            // proof matches.
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://canary.dl2.discordapp.net/distro/app/canary/osx/universal/{version}/DiscordCanary.dmg"),
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
