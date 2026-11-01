import Foundation

enum no_mifi_losslesscut_mac {
    static let set = AppRecipeSet(
        family: "no-mifi-losslesscut-mac",
        changelogs: [
        // LosslessCut — the release body is a plain bullet list of fixes
        // ("- (Windows) …", "- Fix …") with no headings, sometimes closing with
        // a "See <previous release> for the full list" line. `.gitHubReleases`
        // reads the page newest-first; the stable tag pattern keeps prereleases
        // out of the history.
        ChangelogRecipe(
            bundleID: "no.mifi.losslesscut-mac",
            source: URL(string: "https://api.github.com/repos/mifi/lossless-cut/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ],
        githubRules: [
        // LosslessCut — Electron video cutter (MIT). electron-builder writes an
        // `app-update.yml` (provider github) and ships `Squirrel.framework`, but
        // the shipped `app.asar` calls no updater API (`checkForUpdates`,
        // `setFeedURL`, `electron-updater` all absent), and the Homebrew cask is
        // not `auto_updates`: neither bundle observed downloads or stages an
        // update by itself.
        //
        // Tags read `v3.70.2`; the bundle says 3.70.2 in both version keys. The
        // macOS artefacts are `LosslessCut-mac-arm64.dmg` and `-x64.dmg` (a
        // universal pkg is marked "DONT-USE-THIS-FILE"); this rule installs the
        // arm64 dmg — no.mifi.losslesscut-mac, Team 46F6T3M669, notarized.
        //
        // Prereleases share the tag shape and the asset names (v3.70.0 is
        // `prerelease: true`) and the bundle keeps a plain version (3.70.0), so a
        // copy installed from one reads as stable. That is safe by version
        // comparison: every prerelease so far was followed by a HIGHER stable
        // release (3.70.0 → 3.70.1, 3.65.0 → 3.66.1), so such a copy is offered
        // its graduation and never anything older; a prerelease ahead of stable
        // reads up to date. No beta rule: the list is newest-first and a
        // same-shaped tag pattern cannot select prereleases, and nothing local
        // names the track.
        GitHubReleaseRule(
            bundleID: "no.mifi.losslesscut-mac",
            owner: "mifi", repo: "lossless-cut",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^LosslessCut-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
