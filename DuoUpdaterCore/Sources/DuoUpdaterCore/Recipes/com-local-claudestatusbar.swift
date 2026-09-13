import Foundation

enum com_local_claudestatusbar {
    static let set = AppRecipeSet(
        family: "com-local-claudestatusbar",
        githubRules: [
        // Claude Status Bar — menu-bar quota indicator for Claude Code. v-tags,
        // and the dmg asset name is versionless (ClaudeStatusBar.dmg on every
        // release), so the asset pattern is the literal filename. Mounted
        // v0.4.4: com.local.claudestatusbar, short == build == tag, Team
        // W9JZ4932LA, notarized.
        GitHubReleaseRule(
            bundleID: "com.local.claudestatusbar",
            owner: "m1ckc3s", repo: "claude-status-bar",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^ClaudeStatusBar\.dmg$"#,
            installerKind: .dmg),
        ])
}
