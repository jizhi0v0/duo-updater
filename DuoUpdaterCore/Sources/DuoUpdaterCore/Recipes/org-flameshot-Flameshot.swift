import Foundation

enum org_flameshot_Flameshot {
    static let set = AppRecipeSet(
        family: "org-flameshot-Flameshot",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.
        // Shared rationale for Detection-only: Recipes/org-alacritty.swift.

        // Flameshot — ad-hoc signed, no Team ID.
        GitHubReleaseRule(
            bundleID: "org.flameshot.Flameshot",
            owner: "flameshot-org", repo: "flameshot"),
        ])
}
