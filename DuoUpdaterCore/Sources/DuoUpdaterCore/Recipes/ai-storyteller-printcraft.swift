import Foundation

enum ai_storyteller_printcraft {
    static let set = AppRecipeSet(
        family: "ai-storyteller-printcraft",
        githubRules: [
        // Shared rationale for storytold's "-craft" apps: Recipes/ai-storyteller-photocraft.swift.

        // PrintCraft — the Acrobat counterpart. Same pipeline, same anchors (they keep
        // `-rc.N` tags and the `printcraft-cli-…` zip out).
        // One-click: ai.storyteller.printcraft, Team DJ6XS33FX8, notarized.
        GitHubReleaseRule(
            bundleID: "ai.storyteller.printcraft",
            owner: "storytold", repo: "printcraft",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^printcraft-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
