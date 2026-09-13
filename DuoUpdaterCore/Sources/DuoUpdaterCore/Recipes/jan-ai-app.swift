import Foundation

enum jan_ai_app {
    static let set = AppRecipeSet(
        family: "jan-ai-app",
        githubRules: [
        // Jan ships a universal macOS zip whose app reports the release tag's
        // version verbatim. Mounted/extracted zip: jan.ai.app, Team F8AH6NHVY5,
        // notarized. Pin the desktop asset; the same release carries source and
        // dependency archives plus Linux/Windows builds.
        GitHubReleaseRule(
            bundleID: "jan.ai.app",
            owner: "janhq", repo: "jan",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^jan-mac-universal-[0-9.]+\.zip$"#,
            installerKind: .zip),
        ])
}
