import Foundation

enum ai_multica_desktop {
    static let set = AppRecipeSet(
        family: "ai-multica-desktop",
        githubRules: [
            // The same release carries standalone CLI archives. Only a release
            // with the Apple Silicon desktop DMG can update the app.
            GitHubReleaseRule(
                bundleID: "ai.multica.desktop",
                owner: "multica-ai", repo: "multica",
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                installAssetPattern: #"^multica-desktop-[0-9]+\.[0-9]+\.[0-9]+-mac-arm64\.dmg$"#,
                installerKind: .dmg),
        ])
}
