import Foundation

enum com_compresso_app {
    static let set = AppRecipeSet(
        family: "com-compresso-app",
        githubRules: [
        // CompressO — Tauri v2 updater. The bundle's endpoint is the repo's
        // `releases/latest/download/latest.json`, which no source here reads, so
        // the row was `.unknown` and the app had no notes at all.
        //
        // Tags are bare `4.1.0` (no `v`), so the pattern is anchored to the whole
        // tag instead of relying on the default's optional `v?`. The release body
        // is the app's changelog and `GitHubMarkdownParser` renders it, so this one
        // rule supplies detection and notes together.
        //
        // Detection-only: the updater's `CompressO_<ver>_aarch64.dmg` was not
        // mounted to confirm the vendor's Team ID, so no in-place install is
        // offered.
        GitHubReleaseRule(
            bundleID: "com.compresso.app",
            owner: "codeforreal1", repo: "compressO",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#),
        ])
}
