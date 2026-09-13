import Foundation

enum ai_deepseek_dsh_desktop {
    static let set = AppRecipeSet(
        family: "ai-deepseek-dsh-desktop",
        githubRules: [
        // DSH Desktop — the DeepSeek Harness desktop client (anywhere-labs).
        // No SUFeedURL; v-tags, one universal dmg per release beside a Windows
        // setup.exe. Mounted v2.0.4: ai.deepseek.dsh.desktop, short == build
        // == tag, Team UM3Z9G5DNH, notarized.
        GitHubReleaseRule(
            bundleID: "ai.deepseek.dsh.desktop",
            owner: "anywhere-labs", repo: "dsh-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^DSH\.Desktop-[0-9.]+-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
