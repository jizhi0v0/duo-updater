import Foundation

enum phpstudy_xpfme_com {
    static let set = AppRecipeSet(
        family: "phpstudy-xpfme-com",
        githubRules: [
        // FlyEnv (xpf0000/FlyEnv, Electron) — local dev-environment manager,
        // formerly PhpWebStudy. The repo and the cask were renamed; the bundle
        // id `phpstudy.xpfme.com` never changed (electron-builder `appId` at
        // v1.0.0 and today), so no `BundleIDMigration`.
        //
        // Its own update check is notify-only: `checkAppVersionUpdate` reads
        // `latest-mac-arm64.yml` / `latest-mac.yml` on the repo's master branch
        // and offers to open `FlyEnv-<v>-arm64.dmg` / `FlyEnv-<v>.dmg` in the
        // browser. electron-updater ships in `app.asar` (and `app-update.yml`
        // names this repo), but nothing calls it, so nothing installs itself
        // and nothing is parked.
        //
        // The app installs a root LaunchDaemon (`com.flyenv.helper`, KeepAlive)
        // by copying `Resources/helper/flyenv-helper` to `/Library/Application
        // Support/FlyEnv/Helper/` behind an admin prompt. A bundle swap leaves
        // that copy running; the new app checks the helper's version on every
        // privileged request, refuses an older one and offers to reinstall it.
        // The vendor's own update path (download the dmg, drag it over) leaves
        // exactly the same state. See the audit, 一键安装.
        //
        // Tags read `v4.20.1`; the bundle says 4.20.1. Each release ships an
        // arm64 dmg beside an x64 one (`FlyEnv-<v>.dmg`) and two zips, all
        // phpstudy.xpfme.com, Team 956BZQ2F2P, notarized (4.15.2, 4.20.0 and
        // 4.20.1 read). The vendor publishes a release before attaching its
        // assets (v4.20.2, 2026-10-24); the source walks past it to the newest
        // release that carries the dmg.
        GitHubReleaseRule(
            bundleID: "phpstudy.xpfme.com",
            owner: "xpf0000", repo: "FlyEnv",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^FlyEnv-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
