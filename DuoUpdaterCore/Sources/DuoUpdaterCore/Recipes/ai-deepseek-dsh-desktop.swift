import Foundation

enum ai_deepseek_dsh_desktop {
    static let set = AppRecipeSet(
        family: "ai-deepseek-dsh-desktop",
        githubRules: [
        // DSH Desktop — the DeepSeek Harness desktop client (anywhere-labs).
        // No SUFeedURL; v-tags, one universal dmg per release beside a Windows
        // setup.exe. Mounted v2.0.4: ai.deepseek.dsh.desktop, short == build
        // == tag, Team UM3Z9G5DNH, notarized. Up to v2.0.15 the dmg was
        // `DSH.Desktop-` (GitHub's dot for the space in "DSH Desktop"); from
        // v2.0.16 it is `DSH-Desktop-`. Each tag also has a `-beta.N`
        // prerelease (`DSH-Desktop-Beta-…`) and a `-next` release
        // (`DSH-NEXT-…`) beside it; the tag anchor and the digit right after
        // `Desktop-` keep both out.
        GitHubReleaseRule(
            bundleID: "ai.deepseek.dsh.desktop",
            owner: "anywhere-labs", repo: "dsh-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^DSH[.-]Desktop-[0-9.]+-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
