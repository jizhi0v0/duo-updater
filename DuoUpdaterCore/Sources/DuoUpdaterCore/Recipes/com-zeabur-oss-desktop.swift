import Foundation

enum com_zeabur_oss_desktop {
    static let set = AppRecipeSet(
        family: "com-zeabur-oss-desktop",
        githubRules: [
            // History: docs/app-audits/com-zeabur-oss-desktop.md#历史与实测
            // Desktop first shipped on the 0.3.0 line. Earlier releases can
            // carry a Mac zeaburctl archive under the same tag scheme.
            GitHubReleaseRule(
                bundleID: "com.zeabur.oss.desktop",
                owner: "zeabur-oss", repo: "zeabur",
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                installAssetPattern: #"^zeabur-desktop-v[0-9]+\.[0-9]+\.[0-9]+-darwin-arm64\.dmg$"#,
                installerKind: .dmg),

            // The installed -beta.N suffix selects this rule. Like Zeabur's
            // updater, choose by version so a higher Stable can graduate a
            // Beta copy, even when a lower Beta was published later.
            GitHubReleaseRule(
                bundleID: "com.zeabur.oss.desktop",
                owner: "zeabur-oss", repo: "zeabur",
                usePrereleases: true,
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?)$"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"^zeabur-desktop-v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?-darwin-arm64\.dmg$"#,
                installerKind: .dmg,
                channel: .beta),
        ],
        githubChannelProofs: [
            ChannelProofKey("com.zeabur.oss.desktop", .beta):
                .recipeAnchor(#"^true$|^highestVersion$"#, in: ["usePrereleases", "candidateScope"]),
        ])
}
