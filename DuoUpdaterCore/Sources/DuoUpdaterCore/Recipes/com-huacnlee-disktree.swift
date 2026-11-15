import Foundation

enum com_huacnlee_disktree {
    static let set = AppRecipeSet(
        family: "com-huacnlee-disktree",
        githubRules: [
            // History: docs/app-audits/com-huacnlee-disktree.md
            // The NSH implementation by huacnlee, independent of tobi's GPUI
            // app. Tags and both bundle version fields use the same semver.
            // The ordinary arm64 archive carries a complete Disktree.app;
            // exclude the separate updater archive, Intel and Linux builds.
            // The app is ad-hoc signed with a valid seal and an identifier
            // matching its bundle ID. Use GitHub's published asset digest and
            // the existing opt-in digest-only identity gates.
            GitHubReleaseRule(
                bundleID: "com.huacnlee.disktree",
                owner: "huacnlee", repo: "disktree",
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                installAssetPattern: #"^disktree-v[0-9]+\.[0-9]+\.[0-9]+-aarch64-apple-darwin\.tar\.gz$"#,
                installerKind: .tarGz,
                installTrust: .publishedDigestOnly),
        ])
}
