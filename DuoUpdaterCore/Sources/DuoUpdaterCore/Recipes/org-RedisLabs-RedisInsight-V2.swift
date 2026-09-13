import Foundation

enum org_RedisLabs_RedisInsight_V2 {
    static let set = AppRecipeSet(
        family: "org-RedisLabs-RedisInsight-V2",
        githubRules: [
        // RedisInsight — org.RedisLabs.RedisInsight-V2, Team UUK47G4BAZ, notarized.
        // Tagged WITHOUT a leading `v` (`3.8.0`). Reached here from the vendor
        // pile: its S3 host does publish an electron-builder manifest, but only
        // under a path that embeds the major version
        // (`…/public/upgrades-v3/latest-mac.yml`), so a probe would have to know
        // the answer to ask the question — and the release lives on plain GitHub
        // Releases regardless, which needs no recipe at all.
        GitHubReleaseRule(
            bundleID: "org.RedisLabs.RedisInsight-V2",
            owner: "redis", repo: "RedisInsight",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Redis-Insight-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
