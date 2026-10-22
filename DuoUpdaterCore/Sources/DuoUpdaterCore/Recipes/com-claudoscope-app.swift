import Foundation

enum com_claudoscope_app {
    static let set = AppRecipeSet(
        family: "com-claudoscope-app",
        githubRules: [
        // Claudoscope — a menu bar viewer for Claude Code's local data
        // (cordwainersmith/Claudoscope). Since v0.3.3 its own updater reads
        // this repo's /releases/latest, and only on the user's click
        // downloads the dmg, swaps the bundle in place and keeps the old one
        // as `Claudoscope.app.bak`. It stages nothing, so it doesn't race ours.
        //
        // Tags read `v1.4.0`; the bundle says 1.4.0 (build 202610081625).
        // v0.3.0 and v0.3.1 bundles say 1.0.0 and v0.3.6 says 0.3.5; all are
        // below the latest tag, so those copies are still offered it.
        // `Claudoscope.dmg`, the only asset in every release, is
        // com.claudoscope.app, Team DN8M2CQ4D2, notarized (same Team from
        // v0.3.0 to v1.4.0). No nested apps; `claudoscope-mcp` in
        // Contents/MacOS runs only when Claude Code spawns it.
        GitHubReleaseRule(
            bundleID: "com.claudoscope.app",
            owner: "cordwainersmith", repo: "Claudoscope",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Claudoscope\.dmg$"#,
            installerKind: .dmg),
        ])
}
