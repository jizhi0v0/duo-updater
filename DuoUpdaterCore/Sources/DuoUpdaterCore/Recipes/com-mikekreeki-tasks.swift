import Foundation

enum com_mikekreeki_tasks {
    static let set = AppRecipeSet(
        family: "com-mikekreeki-tasks",
        githubRules: [
        // Lunatask — task / habit / journal app, Electron (lunatask/lunatask is
        // releases-only, no source). It updates itself with electron-updater
        // (^5.3.0, provider github on this same repo, `updaterCacheDirName`
        // `@lunataskelectron-updater`): it checks once at launch with
        // `autoDownload = false`, asks, downloads only on "Yes!", then
        // `quitAndInstall()` through Squirrel.Mac. No beta channel is ever set.
        // Nothing resident besides the main app: the four nested apps are
        // Electron's own helpers under Contents/Frameworks, no LoginItems.
        //
        // Tags read `v2.1.29`, equal to CFBundleShortVersionString and
        // CFBundleVersion; all 118 releases are stable. `Lunatask-<v>-
        // universal.dmg` exists from v1.5.1 (before that `Lunatask-<v>.dmg`,
        // x86_64 only); the `-universal-mac.zip` beside it is what
        // electron-updater downloads. v2.1.29, v2.1.28, v1.5.0 and v0.4.0 are
        // all com.mikekreeki.tasks, Team 24KNYM7WQY, notarized.
        //
        // The App Store listing (id1583719331) is a universal purchase on the
        // same bundle id: a Mac build on the 2.1.x line plus the iPad/iPhone
        // build (2.36.x). Store copies never reach a GitHub rule
        // (`answersAppStoreCopies`).
        GitHubReleaseRule(
            bundleID: "com.mikekreeki.tasks",
            owner: "lunatask", repo: "lunatask",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Lunatask-[0-9]+(?:\.[0-9]+)+-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
