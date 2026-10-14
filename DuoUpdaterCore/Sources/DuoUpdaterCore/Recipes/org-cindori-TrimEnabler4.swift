import Foundation

enum org_cindori_TrimEnabler4 {
    static let set = AppRecipeSet(
        family: "org-cindori-TrimEnabler4",
        probes: [
        // History: docs/app-audits/org-cindori-TrimEnabler4.md#历史与实测
        // Trim Enabler (Cindori) — DevMate Sparkle appcast, the same shape as
        // `Recipes/com-macpaw-site-theunarchiver.swift`: the bundle carries no
        // Info.plist SUFeedURL (DevMateKit builds the address from
        // `https://updates.devmate.com/%@.xml` at runtime), so it reaches us here.
        // That address 301s to the `updateinfo` host read below. The feed is
        // newest-first, one <item> per build; `entryStartPattern` binds the
        // version, the date and the zip to that one item. The version is read
        // from the item's main <enclosure> only: each item's <sparkle:deltas>
        // enclosures repeat the same `sparkle:shortVersionString`, so an
        // unanchored pattern matches more than once inside one item and
        // `highestVersionEntry` declines the slice.
        // The product is frozen: 4.3.6 (build 26, 2021-01-02) is the last
        // release, and its notes say Big Sur is the last macOS it supports.
        // changelogURL is DevMate's notes page for build 26; it lists every
        // release back to 4.0 between <hr>s, but only the newest is labelled
        // with a version, so there is nothing to structure per release.
        VendorProbeRecipe(
            bundleID: "org.cindori.TrimEnabler4",
            url: URL(string: "https://updateinfo.devmate.com/org.cindori.TrimEnabler4/updates.xml")!,
            mode: .responseBody,
            versionPattern: #"<enclosure(?![^>]*deltaFrom)[^>]*sparkle:shortVersionString="([0-9.]+)""#,
            changelogURL: URL(string: "https://updateinfo.devmate.com/org.cindori.TrimEnabler4/26/releasenotes.html"),
            publishedAtPattern: #"<pubDate>([^<]+)</pubDate>"#,
            entryStartPattern: #"<item[\s>]"#,
            // One-click: the zip holds `Trim Enabler.app`, bundle id
            // org.cindori.TrimEnabler4, Team ZQK6SX26CE (Cindori's Team, the
            // same one Sensei and Backdrop are signed with), notarized, x86_64
            // only (Rosetta on Apple silicon; `HostArch.canRunIntelBuilds`
            // gates the install). The enclosure URL carries the build and an
            // upload timestamp, so it can only come from the feed. The feed
            // publishes a length and no digest.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://dl\.devmate\.com/[^"]+\.zip)""#),
                kind: .zip)),
        ])
}
