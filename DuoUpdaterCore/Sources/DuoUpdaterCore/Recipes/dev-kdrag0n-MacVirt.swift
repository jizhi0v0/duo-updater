import Foundation

enum dev_kdrag0n_MacVirt {
    static let set = AppRecipeSet(
        family: "dev-kdrag0n-MacVirt",
        probes: [
        // History: docs/app-audits/dev-kdrag0n-MacVirt.md#历史与实测
        // OrbStack — one Sparkle appcast (`appcast.new.xml`; the old `appcast.xml`
        // froze at an older release, History has which) carrying every channel as
        // <sparkle:channel> elements.
        // OrbStack has no Info.plist SUFeedURL, so it reaches us here, not via
        // SparkleAppcastSource; `AppScanner` reads `updates_optinChannel` to set
        // the install's channel (see `OrbStackChannel`) and we pick the matching
        // recipe per `channel`. Each anchors its regex to its own channel tag, so
        // a user is only ever offered their channel's build. Install stays on the
        // codesign path (Team HUAQ24HBR6) — OrbStack ships no SUPublicEDKey.
        orbStackRecipe(.stable, tag: "stable"),
        orbStackRecipe(.beta, tag: "beta"),
        orbStackRecipe(.canary, tag: "canary"),
        ],
        changelogs: [
        // OrbStack — VitePress docs at docs.orbstack.dev/release-notes. The page
        // is server-side rendered with the full changelog inline. Each version is
        // an <h2 id="v{major}-{minor}-{patch}-{month}-{day}"> whose visible text
        // is "v{version} ({month} {day})", followed immediately by a <ul>. The id
        // slug uses month names (e.g. "v2-1-3-may-10") so [\w-]+ is needed.
        ChangelogRecipe(
            bundleID: "dev.kdrag0n.MacVirt",
            source: URL(string: "https://docs.orbstack.dev/release-notes")!,
            entryPattern:
                #"<h2[^>]+id="v[\w-]+"[^>]*>v(?<version>[\d.]+)\s*\((?<date>[^)]+)\).*?</a></h2>\s*"#
                + #"<ul>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),
        ],
        channelProofs: [
        // OrbStack publishes one appcast with a `<sparkle:channel>` tag per item and
        // promotes the same dmg across channels (History has a dated case where
        // all three carried the same build). The channel tag the patterns are
        // anchored to is the proof.
        // Both halves named, like WeChat RC and for the same reason: one appcast
        // serves all three channels, and the `<sparkle:channel>` prefix on the
        // version pattern and on the install pattern is what confines each to its
        // own `<item>`. Losing it from the install pattern alone would let the
        // enclosure match the first item in the feed regardless of channel.
        ChannelProofKey("dev.kdrag0n.MacVirt", .beta):
            .recipeAnchor(#"<sparkle:channel>beta"#, in: ["versionPattern", "install"]),
        ChannelProofKey("dev.kdrag0n.MacVirt", .canary):
            .recipeAnchor(#"<sparkle:channel>canary"#, in: ["versionPattern", "install"]),
        ])

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
}
