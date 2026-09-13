import Foundation

enum io_github_clash_verge_rev_clash_verge_rev {
    static let set = AppRecipeSet(
        family: "io-github-clash-verge-rev-clash-verge-rev",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Clash Verge Rev — aarch64 and x64 dmgs ship together; pin aarch64.
        // One-click: io.github.clash-verge-rev.clash-verge-rev, Team JPH3Z7PPBB,
        // notarized.
        GitHubReleaseRule(
            bundleID: "io.github.clash-verge-rev.clash-verge-rev",
            owner: "clash-verge-rev", repo: "clash-verge-rev",
            installAssetPattern: #"^Clash\.Verge_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
