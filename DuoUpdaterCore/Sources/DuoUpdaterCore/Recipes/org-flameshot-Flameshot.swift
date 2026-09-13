import Foundation

enum org_flameshot_Flameshot {
    static let set = AppRecipeSet(
        family: "org-flameshot-Flameshot",
        githubRules: [
        // Flameshot — ad-hoc signed, no Team ID.
        GitHubReleaseRule(
            bundleID: "org.flameshot.Flameshot",
            owner: "flameshot-org", repo: "flameshot"),
        ])
}
