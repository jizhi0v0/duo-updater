import Foundation

enum com_xd_cindycn {
    static let set = AppRecipeSet(
        family: "com-xd-cindycn",
        changelogs: [com_xd_cindy.changelog(for: "com.xd.cindycn")],
        githubRules: [
        // Shared rationale for both Cindy editions: Recipes/com-xd-cindy.swift.

        // Cindy, Mainland China edition — same repo, same tags, its own
        // `-cn.dmg` assets, a different bundle id and a different Team.
        // One-click: com.xd.cindycn, Team NTC4BJ542G, notarized.
        GitHubReleaseRule(
            bundleID: "com.xd.cindycn",
            owner: "makecindy", repo: "cindy",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-cn\.dmg$"#,
            installerKind: .dmg,
            variant: "cn"),

        // Beta — same track and same shape as the global edition's beta rule.
        GitHubReleaseRule(
            bundleID: "com.xd.cindycn",
            owner: "makecindy", repo: "cindy",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)(?:-beta)?$"#,
            installAssetPattern: #"^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-cn\.dmg$"#,
            installerKind: .dmg,
            channel: .beta,
            variant: "cn"),
        ],
        githubChannelProofs: [
        ChannelProofKey("com.xd.cindycn", .beta):
            .recipeAnchor(#"^true$|\(\?:-beta\)\?\$$"#, in: ["usePrereleases", "versionPattern"]),
        ])
}
