import Foundation

enum co_zeit_hyper {
    static let set = AppRecipeSet(
        family: "co-zeit-hyper",
        githubRules: [
        // Hyper — Electron terminal (vercel/hyper). Its own updater is
        // Electron's `autoUpdater` (Squirrel.Mac) on a Hazel feed,
        // `releases.hyper.is/update/darwin_arm64/<version>`, not GitHub and
        // not electron-builder's (the bundled `app-update.yml` is unused, and
        // feed-discover can't construct its github provider). Both Homebrew
        // casks (`hyper`, `hyper@canary`) are `auto_updates`, so this rule is
        // the only source.
        //
        // Stable reads `/releases/latest`, which GitHub never points at a
        // prerelease; every `-canary.N` tag is flagged prerelease and the
        // anchored pattern rejects it anyway. A canary install shares the
        // bundle id, name and Team, and `ReleaseChannel.detect` reads
        // `4.0.0-canary.5` as stable (no step matches `-canary.N`), so this
        // rule does serve it: 4.0.0-canary.N compares above 3.4.1 and reads
        // up to date; a 3.x canary older than 3.4.1 is offered 3.4.1. The
        // gate below keeps one-click off every canary copy, so a stable
        // build never replaces one. Canary itself is not tracked (its last
        // release is 2023-07, 4.0.0-canary.5).
        //
        // Tags before 3.1.0 have no `v` (`3.0.2` … `0.8.0`); they are this
        // same app's stable releases (no other product or track publishes
        // here), so `v?` reads all 41 rather than 13. Nothing a user sees
        // depends on it today: detection and the changelog read only
        // `/releases/latest`, and the list fallback's 20-row page never
        // reaches 2019.
        //
        // One-click: `Hyper-<version>-mac-arm64.dmg`, co.zeit.hyper, Team
        // JW6Y669B67 (3.4.1, 3.4.0, and 3.0.2), notarized. No GitHub digest
        // on these 2023 assets, so the Team-ID gate alone.
        GitHubReleaseRule(
            bundleID: "co.zeit.hyper",
            owner: "vercel", repo: "hyper",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Hyper-[0-9]+(?:\.[0-9]+)+-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ],
        oneClickGates: [
            OneClickGate(
                bundleID: "co.zeit.hyper",
                requirement: .installedVersion(pattern: #"^[0-9]+(?:\.[0-9]+)+$"#),
                reason: "this is a Hyper canary build; one-click installs only stable over stable"),
        ])
}
