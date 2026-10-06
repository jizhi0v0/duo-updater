import Foundation

enum ai_storyteller_lightcraft {
    static let set = AppRecipeSet(
        family: "ai-storyteller-lightcraft",
        githubRules: [
        // Shared rationale for storytold's "-craft" apps: Recipes/ai-storyteller-photocraft.swift.

        // LightCraft — the Lightroom counterpart. Same pipeline, same anchors (they keep
        // `-rc.N` tags and the `lightcraft-cli-…` zip out).
        // One-click: ai.storyteller.lightcraft, Team DJ6XS33FX8, notarized.
        GitHubReleaseRule(
            bundleID: "ai.storyteller.lightcraft",
            owner: "storytold", repo: "lightcraft",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^lightcraft-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
