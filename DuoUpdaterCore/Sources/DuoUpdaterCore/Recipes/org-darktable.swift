import Foundation

enum org_darktable {
    static let set = AppRecipeSet(
        family: "org-darktable",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.
        // Shared rationale for Detection-only: Recipes/org-alacritty.swift.

        // darktable — ad-hoc signed. Tags are `release-5.6.0`; the default pattern
        // takes the version out of them.
        GitHubReleaseRule(
            bundleID: "org.darktable",
            owner: "darktable-org", repo: "darktable"),
        ])
}
