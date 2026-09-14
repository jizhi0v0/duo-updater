import Foundation

enum com_claudecode_context {
    static let set = AppRecipeSet(
        family: "com-claudecode-context",
        githubRules: [
        // claude-devtools — visualiser/analyser for Claude Code sessions.
        // v-tags, and each release ships both an arm64 dmg and an x64 dmg plus
        // zip/blockmap siblings (the Homebrew cask picks between the two dmgs by
        // architecture). Mounted v0.5.0:
        // com.claudecode.context, short == build == tag, Team 55PSHY2MW6,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.claudecode.context",
            owner: "matt1398", repo: "claude-devtools",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^claude-devtools-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
