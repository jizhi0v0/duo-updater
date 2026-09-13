import Foundation

enum net_sourceforge_sqlitebrowser {
    static let set = AppRecipeSet(
        family: "net-sourceforge-sqlitebrowser",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // DB Browser for SQLite — the repo also publishes rolling `nightly` and
        // `continuous` prereleases, both excluded by `/releases/latest`. The release
        // carries Windows/Linux artifacts too, so the pattern anchors the single
        // macOS dmg and, importantly, the `SQLite` product: a `…for.SQLCipher…dmg`
        // (a different app) ships from the same builds.
        // One-click: net.sourceforge.sqlitebrowser, Team C34AV33YLK, notarized.
        GitHubReleaseRule(
            bundleID: "net.sourceforge.sqlitebrowser",
            owner: "sqlitebrowser", repo: "sqlitebrowser",
            installAssetPattern: #"^DB\.Browser\.for\.SQLite-v[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
