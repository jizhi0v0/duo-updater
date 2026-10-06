import Foundation

enum ai_storyteller_designcraft {
    static let set = AppRecipeSet(
        family: "ai-storyteller-designcraft",
        githubRules: [
        // Shared rationale for storytold's "-craft" apps: Recipes/ai-storyteller-photocraft.swift.

        // DesignCraft — the InDesign counterpart. Same pipeline, same anchors (they keep
        // `-rc.N` tags and the `designcraft-cli-…` zip out).
        // One-click: ai.storyteller.designcraft, Team DJ6XS33FX8, notarized.
        GitHubReleaseRule(
            bundleID: "ai.storyteller.designcraft",
            owner: "storytold", repo: "designcraft",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^designcraft-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
