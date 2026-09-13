import Foundation

enum com_github_marktext_marktext {
    static let set = AppRecipeSet(
        family: "com-github-marktext-marktext",
        githubRules: [
        // MarkText — ad-hoc signed, no Team ID.
        GitHubReleaseRule(
            bundleID: "com.github.marktext.marktext",
            owner: "marktext", repo: "marktext"),
        ])
}
