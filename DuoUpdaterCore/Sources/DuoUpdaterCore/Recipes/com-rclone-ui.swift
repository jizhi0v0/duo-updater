import Foundation

enum com_rclone_ui {
    static let set = AppRecipeSet(
        family: "com-rclone-ui",
        githubRules: [
        // Rclone UI — a Tauri 2 desktop front end for rclone, open source in
        // rclone/rclone-ui (formerly rclone-ui/rclone-ui, which redirects). Its
        // own updater is tauri-plugin-updater reading this repo's
        // `/releases/latest/download/latest.json`: at launch it asks, and on
        // Update calls `downloadAndInstall()`, which swaps the bundle in the
        // same call, so nothing is left parked. The app spawns `rclone rcd`
        // from a binary it provisions outside the bundle, so a swap replaces
        // none of the daemon's code.
        //
        // Tags read `v3.7.5`, the bundle says 3.7.5. Not read on purpose:
        // `cloud-v0.1.0` and `cloud-latest` (Rclone Cloud, a separate CLI with
        // no dmg); both fail on the tag. The 2.7.x prereleases of 2025-10/11
        // are an old beta run on the same id, long passed by stable; no
        // prerelease since. Up to 1.9.1 the dmgs were named
        // `Rclone.UI_<version>_aarch64.dmg`; 0.9.x and 1.x are `com.stray.app`
        // (see `BundleIDMigration`), so the asset pattern only needs today's name.
        // One-click: com.rclone.ui, Team 8FT82R3S6A, notarized, on every
        // release read (2.0.0, 2.2.0, 3.7.4, 3.7.5).
        GitHubReleaseRule(
            bundleID: "com.rclone.ui",
            owner: "rclone", repo: "rclone-ui",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Rclone\.UI_aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
