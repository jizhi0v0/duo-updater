import Foundation

enum ai_storyteller_vectorcraft {
    static let set = AppRecipeSet(
        family: "ai-storyteller-vectorcraft",
        githubRules: [
        // Shared rationale for storytold's "-craft" apps: Recipes/ai-storyteller-photocraft.swift.

        // VectorCraft — the Illustrator counterpart. Same pipeline, same anchors (they keep
        // `-rc.N` tags and the `vectorcraft-cli-…` zip out).
        // One-click: ai.storyteller.vectorcraft, Team DJ6XS33FX8, notarized.
        GitHubReleaseRule(
            bundleID: "ai.storyteller.vectorcraft",
            owner: "storytold", repo: "vectorcraft",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^vectorcraft-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
