import Foundation

enum com_objective_see_lulu_app {
    static let set = AppRecipeSet(
        family: "com-objective-see-lulu-app",
        githubRules: [
        // LuLu — Objective-See's firewall. One universal dmg per release,
        // `LuLu_<ver>.dmg`. One-click: com.objective-see.lulu.app, Team VBG97UB4TA,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.objective-see.lulu.app",
            owner: "objective-see", repo: "LuLu",
            installAssetPattern: #"^LuLu_[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
