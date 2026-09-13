import Foundation

enum net_kovidgoyal_kitty {
    static let set = AppRecipeSet(
        family: "net-kovidgoyal-kitty",
        githubRules: [
        // kitty — terminal. The repo carries a rolling `nightly` prerelease tag, so
        // again `/releases/latest` (not the list) is what keeps a stable install on
        // stable. One dmg per release, `kitty-<ver>.dmg`, universal.
        // One-click: net.kovidgoyal.kitty, Team NTY7FVCEKP, notarized.
        GitHubReleaseRule(
            bundleID: "net.kovidgoyal.kitty",
            owner: "kovidgoyal", repo: "kitty",
            installAssetPattern: #"^kitty-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
