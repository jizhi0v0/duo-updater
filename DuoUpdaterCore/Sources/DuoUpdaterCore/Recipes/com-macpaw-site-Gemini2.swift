import Foundation

enum com_macpaw_site_Gemini2 {
    static let set = AppRecipeSet(
        family: "com-macpaw-site-Gemini2",
        probes: [
        // History: docs/app-audits/com-macpaw-site-Gemini2.md#历史与实测
        // Gemini 2 (MacPaw) — DevMate Sparkle appcast, the same mechanism as The
        // Unarchiver (`Recipes/com-macpaw-site-theunarchiver.swift`): the bundle
        // carries no `SUFeedURL` (DevMate configures the feed internally), so it
        // reaches us here.
        //
        // The version reported is the BUILD, not the marketing string. The feed
        // reuses `sparkle:shortVersionString` for the marketing version on older
        // items ("2.10.1"), but the newest item publishes the build there too
        // (`sparkle:version="407" sparkle:shortVersionString="407"`), while that
        // package's own `CFBundleShortVersionString` is 2.10.2. Comparing the
        // marketing string would therefore offer "407", and every copy of 2.10.2
        // would keep seeing an update forever. `versionIsBuild` compares
        // `sparkle:version` against the bundle's `CFBundleVersion` instead, and
        // the row names the installed side out of the same namespace.
        //
        // One-click: the enclosure of that same first (newest) item is a zip
        // holding `Gemini 2.app`, bundle id com.macpaw.site.Gemini2, Team
        // S8EX82NJP6, notarized Developer ID — the same Team as the installed
        // app. The URL is versioned and carries a build timestamp, so it can only
        // come from the feed we just read.
        //
        // changelogURL is DevMate's per-build notes page. It is pinned to the
        // build this recipe was written against, so it lags a release behind —
        // cosmetic; the app has no stable changelog path of its own.
        VendorProbeRecipe(
            bundleID: "com.macpaw.site.Gemini2",
            url: URL(string: "https://updates.devmate.com/com.macpaw.site.Gemini2.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:version="([0-9]+)""#,
            changelogURL: URL(string: "https://updates.devmate.com/releasenotes/407/com.macpaw.site.Gemini2.html"),
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://dl\.devmate\.com/[^"]+\.zip)""#),
                kind: .zip)),
        ])
}
