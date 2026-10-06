import Foundation

enum ai_storyteller_effectcraft {
    static let set = AppRecipeSet(
        family: "ai-storyteller-effectcraft",
        githubRules: [
        // Shared rationale for storytold's "-craft" apps: Recipes/ai-storyteller-photocraft.swift.

        // EffectCraft — the After Effects counterpart. Same pipeline, same anchors (they keep
        // `-rc.N` tags and the `effectcraft-cli-…` zip out).
        // One-click: ai.storyteller.effectcraft, Team DJ6XS33FX8, notarized.
        GitHubReleaseRule(
            bundleID: "ai.storyteller.effectcraft",
            owner: "storytold", repo: "effectcraft",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^effectcraft-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
