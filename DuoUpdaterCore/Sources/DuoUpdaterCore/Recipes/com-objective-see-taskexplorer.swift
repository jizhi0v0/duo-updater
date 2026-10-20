import Foundation

enum com_objective_see_taskexplorer {
    static let set = AppRecipeSet(
        family: "com-objective-see-taskexplorer",
        githubRules: [
        // TaskExplorer (objective-see/TaskExplorer, Team VBG97UB4TA, notarized) —
        // Objective-See's process explorer. No SUFeedURL and no updater of its
        // own: "Check for Updates…" (App/Update.m) only compares against
        // `version` in objective-see.com/products.json, whose `zip` is this
        // repo's release asset, and opens the product page. One universal
        // `TaskExplorer_<ver>.zip` per release (release.sh); no pre-releases.
        //
        // 3.x embeds an Endpoint Security system extension
        // (`Contents/Library/SystemExtensions/com.objective-see.taskexplorer.extension.systemextension`).
        // The app re-submits the activation request on every launch and
        // answers "replace" (App/Extension.m), so the next launch after a swap
        // moves the extension to the new version. Apple uninstalls an app's
        // extensions when the app is deleted; whether a swap counts is settled
        // only by the real-machine run (audit doc, 一键安装).
        //
        // 2.x shipped as `com.objective-see.TaskExplorer` (case differs):
        // `BundleIDMigration` files those copies here.
        GitHubReleaseRule(
            bundleID: "com.objective-see.taskexplorer",
            owner: "objective-see", repo: "TaskExplorer",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^TaskExplorer_[0-9]+(?:\.[0-9]+)+\.zip$"#,
            installerKind: .zip),
        ])
}
