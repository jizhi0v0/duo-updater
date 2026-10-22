import Foundation

enum io_bdash {
    static let set = AppRecipeSet(
        family: "io-bdash",
        githubRules: [
        // Bdash (bdash-app/bdash) — an Electron SQL client. It has no updater
        // that downloads: "Check for Updates..." reads /releases/latest and opens
        // a web page (`src/main/updateChecker.ts`, `src/main/menu.ts`). The
        // bundle's `app-update.yml` (`provider: github`) is electron-builder's
        // publish config, not a live updater: app.asar carries no
        // electron-updater or autoUpdater, and feed-discover can't build a
        // manifest address from a github provider anyway.
        //
        // Tags read `v1.35.4`; the bundle says 1.35.4. The five oldest releases
        // (1.0.0–1.2.2, 2017) are the same app tagged without the `v`, so the
        // pattern takes an optional `v`. The 1.0.0 betas/rcs are prereleases and
        // the anchor keeps their suffix out.
        // `Bdash-<version>-universal.dmg` is io.bdash, Team 4GERXBURZN,
        // notarized — the same Team back to the x86_64-only 1.17.1.
        GitHubReleaseRule(
            bundleID: "io.bdash",
            owner: "bdash-app", repo: "bdash",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Bdash-[0-9]+(?:\.[0-9]+)+-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
