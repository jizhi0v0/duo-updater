import Foundation

enum com_neovide_neovide {
    static let set = AppRecipeSet(
        family: "com-neovide-neovide",
        githubRules: [
        // Neovide — Rust Neovim GUI, no SUFeedURL and no in-app updater. Bare
        // tags (`0.16.2`) equal CFBundleShortVersionString, which is bumped by
        // hand in the checked-in `extra/osx/.../Info.plist` in each "prepare
        // release" commit; CFBundleVersion is frozen there and not compared.
        // The rolling `nightly` tag is a prerelease and the pattern rejects it;
        // its bundle is indistinguishable (same id, short version, Team), so
        // that track is not covered. `-aarch64-apple-darwin` and
        // `-x86_64-apple-darwin` dmgs ship together; pin aarch64. Team
        // X8CNW77992, notarized.
        GitHubReleaseRule(
            bundleID: "com.neovide.neovide",
            owner: "neovide", repo: "neovide",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Neovide-aarch64-apple-darwin\.dmg$"#,
            installerKind: .dmg),
        ])
}
