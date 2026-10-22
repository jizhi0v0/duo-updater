import Foundation

enum com_ToWatchList_SimpleComic {
    static let set = AppRecipeSet(
        family: "com-ToWatchList-SimpleComic",
        githubRules: [
        // Simple Comic (MaddTheSane/Simple-Comic) — a comic-archive reader with
        // no self-updater (no Sparkle, no SUFeedURL, no update code in the
        // binary), so GitHub Releases is the route for the notarized download.
        //
        // Tags read `App-Store-1.9.9`: the vendor names every release after
        // the Mac App Store build it goes out with, but the asset is a
        // Developer ID build (no `_MASReceipt`). The one tag without that
        // prefix, `1.9.1`, is the same product (release "App Store 1.9.1",
        // branch `App-Store-1.9.1`, and 1.9.2's compare link starts from it),
        // so the prefix is optional. A store copy carries the same bundle id
        // and is skipped by the `isMASApp` gate before it reaches this rule.
        //
        // The asset has been `Simple.Comic.<v>.zip`, `Simple.Comic.zip`,
        // `Simple.Comic.app.zip` and `Simple.Comic.app.<v>.zip`; the pattern
        // takes all four so a renamed asset does not read as "no macOS build".
        // One-click: com.ToWatchList.SimpleComic, Team 3D9SMH4RWM, notarized,
        // universal, at both 1.9.8 and 1.9.9.
        GitHubReleaseRule(
            bundleID: "com.ToWatchList.SimpleComic",
            owner: "MaddTheSane", repo: "Simple-Comic",
            versionPattern: #"^(?:App-Store-)?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Simple\.Comic(?:\.app)?(?:\.[0-9]+(?:\.[0-9]+)+)?\.zip$"#,
            installerKind: .zip),
        ])
}
