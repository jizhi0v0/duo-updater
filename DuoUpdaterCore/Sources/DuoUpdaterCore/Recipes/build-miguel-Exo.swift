import Foundation

enum build_miguel_Exo {
    static let set = AppRecipeSet(
        family: "build-miguel-Exo",
        githubRules: [
            // Miguel Piedrafita's Gmail client. Both published versions ship
            // the same notarized Developer ID identity in an Apple Silicon DMG.
            GitHubReleaseRule(
                bundleID: "build.miguel.Exo",
                owner: "m1guelpf", repo: "Exo",
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                installAssetPattern: #"^exo-v[0-9]+\.[0-9]+\.[0-9]+-macos-arm64\.dmg$"#,
                installerKind: .dmg),
        ])
}
