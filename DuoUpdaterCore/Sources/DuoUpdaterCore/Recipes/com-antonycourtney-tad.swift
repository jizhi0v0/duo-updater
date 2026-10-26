import Foundation

enum com_antonycourtney_tad {
    static let set = AppRecipeSet(
        family: "com-antonycourtney-tad",
        githubRules: [
        // Tad — tabular data viewer (antonycourtney/tad, Electron). Its own
        // updater is electron-updater 4.6.5 with the GitHub provider, run only
        // from the "Check for Updates" menu item: it asks, downloads the zip
        // into ~/Library/Application Support/Caches/tad-updater/pending (the
        // pre-5 electron-updater path, which `SelfUpdaterStash` does not read),
        // then quits and lets
        // Squirrel.Mac swap the bundle. No automatic check, no login item; the
        // four nested `Tad Helper*.app`s are Electron's own child processes.
        //
        // Tags read `v0.14.0`; the bundle says 0.14.0 (build 0.14.0.1). Since
        // v0.12.0 every release carries `Tad-<version>-arm64.dmg`
        // (com.antonycourtney.tad, Team VPS8BQAV8D, notarized; same id and Team
        // back to v0.6.4). The arch-less `Tad-<version>.dmg` / `-mac.zip` are
        // x86_64 only, and they are the only files `latest-mac.yml` lists.
        GitHubReleaseRule(
            bundleID: "com.antonycourtney.tad",
            owner: "antonycourtney", repo: "tad",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Tad-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
