import Foundation

enum com_zeabur_oss_desktop {
    static let bundleID = "com.zeabur.oss.desktop"

    static let set = AppRecipeSet(
        family: "com-zeabur-oss-desktop",
        githubRules: [
            // History: docs/app-audits/com-zeabur-oss-desktop.md#历史与实测
            // Desktop first shipped on the 0.3.0 line. Earlier releases can
            // carry a Mac zeaburctl archive under the same tag scheme.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "zeabur-oss", repo: "zeabur",
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"^zeabur-desktop-v[0-9]+\.[0-9]+\.[0-9]+-darwin-arm64\.dmg$"#,
                installerKind: .dmg),

            // The installed -beta.N or -rc.N suffix selects this rule. Like
            // Zeabur's updater, read a page of 30 and choose by version.
            // GitHubReleasesSource also checks /releases/latest for promotion.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "zeabur-oss", repo: "zeabur",
                usePrereleases: true,
                listPageSize: 30,
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+(?:-(?:beta|rc)\.[0-9]+)?)$"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"^zeabur-desktop-v[0-9]+\.[0-9]+\.[0-9]+(?:-(?:beta|rc)\.[0-9]+)?-darwin-arm64\.dmg$"#,
                installerKind: .dmg,
                channel: .beta),
        ],
        githubChannelProofs: [
            ChannelProofKey(bundleID, .beta):
                .recipeAnchor(#"^true$|^highestVersion$"#, in: ["usePrereleases", "candidateScope"]),
        ])
}
