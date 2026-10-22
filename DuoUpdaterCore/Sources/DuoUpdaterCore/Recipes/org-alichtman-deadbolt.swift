import Foundation

enum org_alichtman_deadbolt {
    static let set = AppRecipeSet(
        family: "org-alichtman-deadbolt",
        githubRules: [
        // Deadbolt — file encryption, Electron (alichtman/deadbolt). No updater
        // runs: the bundle carries electron-builder's `app-update.yml`, but the
        // `autoUpdater` call in `src/main/main.ts` is commented out at every
        // v2 tag, electron-updater is not packaged, and no release publishes a
        // `latest-mac.yml`. GitHub Releases is the route.
        //
        // Tags: `v2.1.1` style since 2.0, bare `1.0.0` / `0.1.0` before. Both
        // are the same product and bundle id (real packages read), so the
        // pattern takes an optional `v`; `v2.0.0-alpha` (a prerelease) stays out.
        // Each release ships an arm64 dmg and an x86_64 one (`Deadbolt-<v>.dmg`);
        // no universal build, so the arm64 dmg is the one installed.
        // One-click: `Deadbolt-2.1.1-arm64.dmg` is org.alichtman.deadbolt, Team
        // BF3UMC9FSZ, notarized. 2.1.1 is the first such release: 2.1.0 is
        // ad-hoc (linker-signed) and 1.0.0 unsigned, and the Team gate refuses
        // those copies; 0.1.0 carries the same Team.
        GitHubReleaseRule(
            bundleID: "org.alichtman.deadbolt",
            owner: "alichtman", repo: "deadbolt",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Deadbolt-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
