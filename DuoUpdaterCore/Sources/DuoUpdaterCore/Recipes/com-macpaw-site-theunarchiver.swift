import Foundation

enum com_macpaw_site_theunarchiver {
    static let set = AppRecipeSet(
        family: "com-macpaw-site-theunarchiver",
        probes: [
        // The Unarchiver (MacPaw) — DevMate Sparkle appcast. Like the Codex/Alfred
        // neighbors it carries no Info.plist SUFeedURL (DevMate configures the feed
        // internally), so it reaches us here. The version is the
        // `sparkle:shortVersionString` ATTRIBUTE on each <enclosure> (NOT an
        // element); the feed is descending (newest item first), so first match is
        // the latest. Detection only — self-updates via DevMate's Sparkle.
        // changelogURL is DevMate's release-notes page (pinned to a build number,
        // so it lags a release behind — cosmetic; theunarchiver.com has no stable
        // changelog path).
        VendorProbeRecipe(
            bundleID: "com.macpaw.site.theunarchiver",
            url: URL(string: "https://updates.devmate.com/com.macpaw.site.theunarchiver.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:shortVersionString="([0-9.]+)""#,
            changelogURL: URL(string: "https://updates.devmate.com/releasenotes/147/com.macpaw.site.theunarchiver.html"),
            // One-click verified 2026-08-09 on the 4.3.9 archive from this same
            // feed: `The Unarchiver.app` inside, bundle id and Team (S8EX82NJP6)
            // matching the installed copy, spctl "Notarized Developer ID". The
            // enclosure URL is versioned AND carries a build timestamp, so it can
            // only come from the feed we just read — first item is newest here.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://dl\.devmate\.com/[^"]+\.zip)""#),
                kind: .zip)),
        ])
}
