import Foundation

enum com_brave_Browser {
    static let set = AppRecipeSet(
        family: "com-brave-Browser",
        probes: [
        // History: docs/app-audits/com-brave-Browser.md#历史与实测
        // Brave Browser — Beta / Nightly. Sparkle appcast per channel and per ARCH.
        // Distinct bundle ids (`com.brave.Browser.beta` / `.nightly`) so the channel
        // gate routes each install to its own feed.
        //
        // COMPARE ON THE BUILD, not the marketing string. The feed's
        // `sparkle:shortVersionString` is Brave's own 4-part version (e.g. "1.94.104.0")
        // while the installed bundle reports a CHROMIUM-prefixed one
        // (e.g. "151.1.94.104"). Comparing those puts 1 against 151 and concludes the
        // installed copy is newer — so the row read "up to date" forever and Brave
        // Beta/Nightly could never surface an update. `sparkle:version` (e.g. "194.104")
        // is exactly the bundle's `CFBundleVersion`, so that's the pair that lines
        // up; `displayVersionPattern` keeps the human-readable string on screen.
        //
        // The `-arm64` feed is deliberate: the plain path serves x64 dmgs only
        // (`Brave-Browser-Beta-x64.dmg`). The two feeds are published separately and
        // are not always on the same build, so reading the arm64 feed keeps the
        // version and the artifact in one document. Team KL8N8XSYF4, notarized.
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
            // A complete, well-formed feed with no `<item>` at all is the
            // vendor's feed being empty for a while, not a closed track: this
            // track publishes every day. So it reads as an outage rather than a
            // recipe to fix. Anchored to the whole document: any `<item>`, a
            // healthy feed's only content, keeps it from matching.
            transientBodyPattern: #"(?s)\A\s*(?:<\?xml[^>]*\?>\s*)?<rss\b(?:(?!<item\b).)*</channel>\s*</rss>\s*\z"#,
            changelogURL: URL(string: "https://brave.com/latest/")!,
            versionIsBuild: true,
            displayVersionPattern: #"sparkle:shortVersionString="([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://[^"]+Brave-Browser-Nightly-arm64\.dmg)""#),
                kind: .dmg),
            channel: .nightly),
        ],
        changelogs: [
        // Brave Browser (stable) — the Sparkle item's `<description>` is only a
        // link to this file ("Release notes at <a …CHANGELOG_DESKTOP.md>"), so
        // `releaseNotesHTML` rendered a bare URL and the pane looked empty. The
        // repo's `CHANGELOG_DESKTOP.md` is the vendor's own stable changelog:
        //   ## [1.98.63](…/releases/tag/v1.98.63)
        //    - Upgraded Chromium to … ([#60306](…)) ([Changelog for …](…))
        //    ### Leo
        //    - Added passages …
        // newest first. `markdownSource` unwraps the inline issue/commit links in
        // the bullets, and `headingPattern` keeps the `###` categories (Leo, Web3,
        // …) as sections instead of flattening them into the bullet list.
        //
        // Keyed to the stable bundle id on purpose: the Beta and Nightly probes
        // below keep their own `changelogURL` (brave.com/latest, channel versions
        // only), so this recipe cannot answer for those channels.
        ChangelogRecipe(
            bundleID: "com.brave.Browser",
            source: URL(
                string:
                    "https://raw.githubusercontent.com/brave/brave-browser/master/CHANGELOG_DESKTOP.md")!,
            entryPattern:
                #"(?:^|\n)##\s+\[(?<version>[0-9]+(?:\.[0-9]+){1,3})\]\([^)\n]*\)\n(?<body>.*?)(?=\n##\s|\z)"#,
            itemPatterns: [#"\n\s*-\s+(?<item>[^\n]+)"#],
            markdownSource: true,
            maxEntries: 20,
            headingPattern: #"\n###\s+(?<heading>[^\n]+)"#),
        ],
        channelProofs: [
        ChannelProofKey("com.brave.Browser.beta", .beta): .artifact(#"beta-arm64/.*Brave-Browser-Beta"#),
        ChannelProofKey("com.brave.Browser.nightly", .nightly): .artifact(#"nightly-arm64/.*Brave-Browser-Nightly"#),
        ])
}
