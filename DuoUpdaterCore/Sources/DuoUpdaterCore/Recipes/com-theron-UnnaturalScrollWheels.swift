import Foundation

enum com_theron_UnnaturalScrollWheels {
    static let set = AppRecipeSet(
        family: "com-theron-UnnaturalScrollWheels",
        githubRules: [
        // UnnaturalScrollWheels — bare tags, one dmg per release.
        // One-click: com.theron.UnnaturalScrollWheels, Team VH8UL6UKQL, notarized.
        GitHubReleaseRule(
            bundleID: "com.theron.UnnaturalScrollWheels",
            owner: "ther0n", repo: "UnnaturalScrollWheels",
            installAssetPattern: #"^UnnaturalScrollWheels-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
