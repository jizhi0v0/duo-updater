import Foundation

enum com_xingyuzhong_deepseekgui {
    static let set = AppRecipeSet(
        family: "com-xingyuzhong-deepseekgui",
        githubRules: [
        // Kun — local-first AI agent workspace (KunAgent). No SUFeedURL;
        // v-tags, each release ships mac-arm64/mac-x64 dmgs plus zips and
        // Linux deb/AppImage siblings. One-click pins the arm64 dmg. Mounted
        // v0.3.7: com.xingyuzhong.deepseekgui, short == build == tag, Team
        // YBR76S5LNP, notarized.
        GitHubReleaseRule(
            bundleID: "com.xingyuzhong.deepseekgui",
            owner: "KunAgent", repo: "Kun",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Kun-[0-9.]+-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
