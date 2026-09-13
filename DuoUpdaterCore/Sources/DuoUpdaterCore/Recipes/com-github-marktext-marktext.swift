import Foundation

enum com_github_marktext_marktext {
    static let set = AppRecipeSet(
        family: "com-github-marktext-marktext",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.
        // Shared rationale for Detection-only: Recipes/org-alacritty.swift.

        // MarkText — ad-hoc signed, no Team ID.
        GitHubReleaseRule(
            bundleID: "com.github.marktext.marktext",
            owner: "marktext", repo: "marktext"),
        ])
}
