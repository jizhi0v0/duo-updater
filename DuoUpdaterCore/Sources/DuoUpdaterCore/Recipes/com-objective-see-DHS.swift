import Foundation

enum com_objective_see_DHS {
    static let set = AppRecipeSet(
        family: "com-objective-see-DHS",
        githubRules: [
        // DHS (Dylib Hijack Scanner) — Objective-See's on-demand scanner for
        // apps susceptible to dylib hijacking. No updater of its own: no
        // SUFeedURL, no Sparkle, and unlike KnockKnock no products.json check
        // (the v1.6.0 source and the 1.4.1–1.6.0 binaries only open the
        // product page in the browser). Nothing resident: no nested app, login
        // item or launchd job.
        //
        // Tags read `v1.6.0`; the bundle says 1.6.0. One universal zip per
        // release, named `DHS_1.6.0.zip` in v1.6.0 but `DHS_1_5_1.zip` /
        // `DHS_1_5_0.zip` before, so the asset pattern takes `.` or `_`.
        // 1.4.1 (bitbucket), 1.5.0, 1.5.1 and 1.6.0 are all
        // com.objective-see.DHS, Team VBG97UB4TA, notarized.
        GitHubReleaseRule(
            bundleID: "com.objective-see.DHS",
            owner: "objective-see", repo: "DylibHijackScanner",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^DHS_[0-9]+(?:[._][0-9]+)+\.zip$"#,
            installerKind: .zip),
        ])
}
