import Foundation

enum com_mockoon_app {
    static let set = AppRecipeSet(
        family: "com-mockoon-app",
        githubRules: [
        // Mockoon — open-source API mocking desktop app (mockoon/mockoon,
        // Electron). Its own update check reads api.mockoon.com's
        // `releases/desktop/stable.json` (`{"tag","digest"}`); on macOS it only
        // shows a banner whose button opens mockoon.com/download — it never
        // downloads or swaps the bundle (only the Windows installer build does).
        // The `app-update.yml` in the bundle is electron-builder's publish
        // config; `app.asar` carries no electron-updater. The four nested
        // `Mockoon Helper*.app` are Electron's child processes and exit with it.
        //
        // The repo is a monorepo, but only the desktop app makes GitHub
        // releases: `libs-v*` (npm libraries, CLI), `web-v*` and the older
        // `cli-v*` / `cloud-v*` are bare tags,
        // so /releases/latest is always a `v*` desktop release. Tags read
        // `v9.9.0`; the bundle says 9.9.0. Every release since v9.5.0 carries
        // `mockoon.setup.<version>.universal.dmg` (com.mockoon.app, Team
        // 8443RQQKK6, notarized); releases up to v9.4.0 no longer have assets.
        GitHubReleaseRule(
            bundleID: "com.mockoon.app",
            owner: "mockoon", repo: "mockoon",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^mockoon\.setup\.[0-9]+(?:\.[0-9]+)+\.universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
