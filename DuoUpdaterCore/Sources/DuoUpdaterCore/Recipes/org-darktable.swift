import Foundation

enum org_darktable {
    static let set = AppRecipeSet(
        family: "org-darktable",
        githubRules: [
        // darktable — ad-hoc signed. Tags are `release-5.6.0`; the default pattern
        // takes the version out of them.
        GitHubReleaseRule(
            bundleID: "org.darktable",
            owner: "darktable-org", repo: "darktable"),
        ])
}
