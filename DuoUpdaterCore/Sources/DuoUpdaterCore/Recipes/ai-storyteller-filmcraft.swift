import Foundation

enum ai_storyteller_filmcraft {
    static let set = AppRecipeSet(
        family: "ai-storyteller-filmcraft",
        githubRules: [
        // Shared rationale for storytold's "-craft" apps: Recipes/ai-storyteller-photocraft.swift.

        // FilmCraft — the Premiere Pro counterpart. Same pipeline, same anchors (they keep
        // `-rc.N` tags and the `filmcraft-cli-…` zip out).
        // One-click: ai.storyteller.filmcraft, Team DJ6XS33FX8, notarized.
        GitHubReleaseRule(
            bundleID: "ai.storyteller.filmcraft",
            owner: "storytold", repo: "filmcraft",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^filmcraft-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
