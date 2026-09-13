import Foundation

enum com_github_githubapp {
    static let set = AppRecipeSet(
        family: "com-github-githubapp",
        githubRules: [
        // GitHub Copilot — the native client from github/app. No SUFeedURL,
        // cask `auto_updates`, so the row was unknown. Stable tags `vX.Y.Z`
        // only; the anchored pattern keeps a future prerelease from reading as
        // stable under the list fallback. One-click pins the arm64 dmg — each
        // release also ships darwin-x64.dmg, .zip and .tar.gz (+ .sig) beside
        // it, and Windows/Linux artifacts. Mounted v1.1.14 dmg:
        // com.github.githubapp, short == build == 1.1.14, arm64-only, Team
        // VEKTX9H2N7, notarized.
        GitHubReleaseRule(
            bundleID: "com.github.githubapp",
            owner: "github", repo: "app",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^GitHub-Copilot-darwin-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
