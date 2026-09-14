import Foundation

enum com_intelliscapesolutions_caffeine {
    static let set = AppRecipeSet(
        family: "com-intelliscapesolutions-caffeine",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Caffeine — one constant `Caffeine.dmg` per release, tags are bare (e.g. `1.1.4`).
        // One-click: com.intelliscapesolutions.caffeine, Team YD6LEYT6WZ, notarized.
        GitHubReleaseRule(
            bundleID: "com.intelliscapesolutions.caffeine",
            owner: "IntelliScape", repo: "caffeine",
            installAssetPattern: #"^Caffeine\.dmg$"#,
            installerKind: .dmg),
        ])
}
