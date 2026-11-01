import Foundation

enum com_super_productivity_app {
    static let set = AppRecipeSet(
        family: "com-super-productivity-app",
        changelogs: [
        // Super Productivity — the release body opens with a wiki link, then
        // carries `### Improvements` / `### Fixes` / `### Desktop fixes` bullet
        // lists, then a `### Contributors` roll call and `**Full Changelog**`.
        // The parser keeps the real headings and drops the Full Changelog line;
        // Contributors is the same boilerplate every release, so it is skipped.
        ChangelogRecipe(
            bundleID: "com.super-productivity.app",
            source: URL(string: "https://api.github.com/repos/super-productivity/super-productivity/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            skipSections: ["Contributors"],
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ],
        githubRules: [
        // Super Productivity — Electron time-tracking / to-do app. Its own
        // updater reads `api.github.com/repos/…/releases/latest`, then calls
        // `autoUpdater.quitAndInstall()`, and `app-update.yml` names provider
        // github with `updaterCacheDirName: superproductivity-updater`; the
        // Homebrew cask is `auto_updates true`, so the own updater is the one
        // that applies updates when it runs. Nothing stays resident.
        //
        // Tags read `v19.3.1`; the bundle keeps 19.3.1 in both version keys. The
        // macOS artefacts are `superProductivity-arm64.dmg` / `-x64.dmg`; this
        // rule installs the arm64 dmg — com.super-productivity.app, Team
        // 363FAFK383, notarized.
        //
        // Every prerelease tag carries a suffix (`v18.0.0-rc.0`, `v17.0.0-RC.13`,
        // `v15.1.3-rc.0`) that the anchored pattern rejects, and the bundle keeps
        // that suffix in both version keys, so no such copy is mistaken for a
        // plain release and none of them can be offered as "latest".
        GitHubReleaseRule(
            bundleID: "com.super-productivity.app",
            owner: "super-productivity", repo: "super-productivity",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^superProductivity-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
