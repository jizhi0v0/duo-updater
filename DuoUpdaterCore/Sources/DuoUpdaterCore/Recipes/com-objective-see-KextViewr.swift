import Foundation

enum com_objective_see_KextViewr {
    static let set = AppRecipeSet(
        family: "com-objective-see-KextViewr",
        githubRules: [
        // KextViewr — Objective-See's viewer for loaded kernel extensions
        // (lists them via /usr/bin/kmutil). No updater of its own: no
        // SUFeedURL, no Sparkle, no products.json check (the v2.0.0 source
        // and the 1.1.0 / 2.0.0 binaries only open the product page in the
        // browser). Nothing resident: no nested app, login item or launchd job.
        //
        // Tags read `v2.0.0`; the bundle says 2.0.0. One universal zip per
        // release, `KextViewr_2.0.0.zip`. Sibling Objective-See apps have
        // named assets with `_` (`DHS_1_5_1.zip`) as well as `.`, so the asset
        // pattern takes either. 1.1.0 (bitbucket, the product page's "older
        // version" for pre-11 macOS) and 2.0.0 are both
        // com.objective-see.KextViewr, Team VBG97UB4TA, notarized.
        GitHubReleaseRule(
            bundleID: "com.objective-see.KextViewr",
            owner: "objective-see", repo: "KextViewr",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^KextViewr_[0-9]+(?:[._][0-9]+)+\.zip$"#,
            installerKind: .zip),
        ])
}
