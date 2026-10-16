import Foundation

enum com_objective_see_KnockKnock {
    static let set = AppRecipeSet(
        family: "com-objective-see-KnockKnock",
        githubRules: [
        // KnockKnock (objective-see/KnockKnock, Team VBG97UB4TA, notarized) —
        // Objective-See's persistence scanner. No SUFeedURL: the app's own check
        // (Update.m) reads `version` from objective-see.org/products.json, whose
        // `zip` is this repo's release asset. One universal `KnockKnock_<ver>.zip`
        // per release (release.sh). The 4.0 betas were GitHub pre-releases
        // (v3.9.5…v3.9.8), excluded by `/releases/latest`; the anchored pattern
        // keeps any suffixed tag off the stable track.
        GitHubReleaseRule(
            bundleID: "com.objective-see.KnockKnock",
            owner: "objective-see", repo: "KnockKnock",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^KnockKnock_[0-9]+(?:\.[0-9]+)+\.zip$"#,
            installerKind: .zip),
        ])
}
