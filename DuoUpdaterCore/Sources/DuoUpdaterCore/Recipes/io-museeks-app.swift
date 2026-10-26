import Foundation

enum io_museeks_app {
    static let set = AppRecipeSet(
        family: "io-museeks-app",
        githubRules: [
        // Museeks — open-source music player (martpie/museeks). Electron up to
        // 0.13.1, Tauri 2 from 0.20.0. It has no updater of its own: on launch
        // (setting `auto_update_checker`, on by default) it reads this repo's
        // /releases list and only shows a toast pointing at museeks.io. Nothing
        // is downloaded or swapped, and the bundle has no helper or login item.
        //
        // Tags read `0.23.4`; the bundle says 0.23.4. Every Tauri release
        // carries one `Museeks_<version>_universal.dmg`; 0.22.0 through 0.23.4
        // are io.museeks.app, Team YK6MWU3892, notarized. 0.20.0–0.21.1 were
        // signed as `Museeks` (same Team), which this rule does not reach; the
        // Electron builds (0.13.1 and older) were io.museeks.app again. No
        // release is flagged prerelease.
        GitHubReleaseRule(
            bundleID: "io.museeks.app",
            owner: "martpie", repo: "museeks",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Museeks_[0-9]+(?:\.[0-9]+)+_universal\.dmg$"#,
            installerKind: .dmg),
        ],
        // One-click only for Tauri builds (0.20.0 and later). An Electron copy
        // (0.13.1 and older) has the same id and Team, but the vendor's 0.20.0
        // notes say the Tauri storage is not backwards compatible: the library
        // has to be re-imported and playlists exported from the old app before
        // installing. Swapping it in place would leave the user without the app
        // that can still export them; detection still offers the update.
        oneClickGates: [
            OneClickGate(
                bundleID: "io.museeks.app",
                requirement: .installedVersion(
                    pattern: #"^(?:0\.(?:[2-9][0-9]|[1-9][0-9]{2,})|[1-9][0-9]*)(?:\.[0-9]+)*$"#),
                reason: "Museeks 0.20 replaced the Electron app with a rewrite whose library and playlists do not carry over; export playlists first, then install it from museeks.io"),
        ])
}
