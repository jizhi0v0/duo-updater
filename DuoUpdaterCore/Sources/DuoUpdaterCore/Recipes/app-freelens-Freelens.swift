import Foundation

enum app_freelens_Freelens {
    static let set = AppRecipeSet(
        family: "app-freelens-Freelens",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Freelens — the OpenLens fork. `-macos-amd64` and `-macos-arm64` dmgs ship
        // together; pin arm64. One-click: app.freelens.Freelens, Team TFR6NT55MB,
        // notarized.
        GitHubReleaseRule(
            bundleID: "app.freelens.Freelens",
            owner: "freelensapp", repo: "freelens",
            installAssetPattern: #"^Freelens-[0-9.]+-macos-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
