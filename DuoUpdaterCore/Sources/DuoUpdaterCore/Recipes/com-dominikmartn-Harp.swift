import Foundation

enum com_dominikmartn_Harp {
    static let set = AppRecipeSet(
        family: "com-dominikmartn-Harp",
        githubRules: [
        // Harp — an unofficial fork of Warp (dominikmartn/harp). Built on Warp's
        // `oss` channel, whose own updater refuses to run ("open-source channel
        // binaries don't support autoupdate"), so GitHub Releases is the only
        // route. Tags are `v0.1.1`, matching CFBundleShortVersionString; one
        // `Harp-<version>.dmg` asset per release, arm64 only.
        // One-click: com.dominikmartn.Harp, Team 423S87ZC86, notarized.
        GitHubReleaseRule(
            bundleID: "com.dominikmartn.Harp",
            owner: "dominikmartn", repo: "harp",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Harp-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
