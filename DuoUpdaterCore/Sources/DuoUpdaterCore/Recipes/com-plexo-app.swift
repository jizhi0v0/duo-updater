import Foundation

enum com_plexo_app {
    static let set = AppRecipeSet(
        family: "com-plexo-app",
        githubRules: [
        // Plexo (anmolkapil/plexo, Team 8YNW6SHRQ8) — an Electron download
        // accelerator. electron-updater reads `latest-mac.yml` with
        // `provider: github`, which the generic electron source cannot build an
        // address from (`electronProviderNeedsConstruction`), so this rule reads
        // the same releases.
        //
        // One track: `src/main/updater.ts` pins `allowPrerelease = false` with no
        // setting to change it, so every install follows the release GitHub marks
        // Latest — what `/releases/latest` returns. The 1.0 candidates are tagged
        // `v1.0.0-rc.N` and the marketing version is `1.0.0-rc.N`, so the pattern
        // keeps the suffix: the default one would read every candidate as `1.0.0`.
        // An unsigned install has no Team ID to match, so the gate refuses its
        // one-click; see the audit for which releases that is.
        GitHubReleaseRule(
            bundleID: "com.plexo.app",
            owner: "anmolkapil", repo: "plexo",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+(?:-[A-Za-z]+\.[0-9]+)?)$"#,
            installAssetPattern: #"^plexo-[0-9][0-9A-Za-z.-]*-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg),
        ])
}
