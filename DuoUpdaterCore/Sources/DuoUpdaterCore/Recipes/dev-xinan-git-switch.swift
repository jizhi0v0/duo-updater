import Foundation

enum dev_xinan_git_switch {
    static let set = AppRecipeSet(
        family: "dev-xinan-git-switch",
        githubRules: [
        // Git Switch (anxndsgn/git-switch, Team 9FX2RB5LD6) — a menu-bar app
        // that switches the global git user.name/user.email. No SUFeedURL and no
        // updater of its own; no Homebrew cask. Each release carries
        // `Git-Switch-v<version>.zip` (root is `Git Switch.app`) and a dmg holding
        // the same app; the rule takes the zip.
        //
        // The version is `MARKETING_VERSION` in the Xcode project, not stamped
        // from the tag, so the two agree only as long as the vendor bumps both
        // (1.0.1 = v1.0.1, checked on the real zip). See the audit's 已知问题.
        GitHubReleaseRule(
            bundleID: "dev.xinan.git-switch",
            owner: "anxndsgn", repo: "git-switch",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Git-Switch-v[0-9]+(?:\.[0-9]+)+\.zip$"#,
            installerKind: .zip),
        ])
}
