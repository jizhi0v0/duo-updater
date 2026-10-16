import Foundation

enum com_generalarcade_flycut {
    static let set = AppRecipeSet(
        family: "com-generalarcade-flycut",
        githubRules: [
        // Flycut (TermiT/Flycut, Team S8JLSG5ES7, notarized) — a menu bar
        // clipboard manager with no SUFeedURL and no in-app updater. Tags so far
        // are the bare version (`1.9.6`, `1.8`), equal to
        // CFBundleShortVersionString in every release checked (1.8 … 1.9.6);
        // the release.yml added on master in 2026-08 cuts a release from a `v*`
        // tag (`v1.9.7`), hence `v?`. One universal zip per release so far,
        // `Flycut.<v>.zip` (1.8.x: `Flycut.app.<v>.zip`); release.yml uploads a
        // single `Flycut.dmg` instead, which the pattern also admits so that
        // release is not walked past. The installer kind is `.zip` for the
        // releases published today: a `Flycut.dmg` release is detected, but its
        // one-click fails at extraction until this kind is switched to `.dmg`.
        // The Mac App Store copy shares the bundle id and is left to the MAS
        // source. `Contents/Library/LoginItems/FlycutHelper.app` is an
        // LSBackgroundOnly launcher that opens the outer app and terminates.
        GitHubReleaseRule(
            bundleID: "com.generalarcade.flycut",
            owner: "TermiT", repo: "Flycut",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Flycut(?:\.app)?(?:\.[0-9][0-9A-Za-z.-]*)?\.(?:zip|dmg)$"#,
            installerKind: .zip),
        ])
}
