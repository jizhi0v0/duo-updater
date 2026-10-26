import Foundation

enum com_rlxone_equinox {
    static let set = AppRecipeSet(
        family: "com-rlxone-equinox",
        githubRules: [
        // Equinox — dynamic-wallpaper maker (rlxone/Equinox), sandboxed. No
        // updater of its own: no SUFeedURL, no Sparkle, no URLSession anywhere in
        // its source; the GitHub links in its menus only open the browser.
        // Nothing nested beyond its own three frameworks.
        //
        // Tags read `v7.0`, equal to CFBundleShortVersionString (build 20). One
        // dmg per release: `Equinox.dmg` up to v4.0, `Equinox-Installer.dmg` from
        // v5.0; the pattern takes both. v6.0 and v7.0 are Team ANWX99972B,
        // notarized. v5.0 and older are ad-hoc, so the Team gate refuses
        // one-click from them (detection still shows the update); not
        // `.publishedDigestOnly`, because the new build has a Team.
        //
        // The Mac App Store edition (id1591510203) shares com.rlxone.equinox and
        // the version line; it differs only in the build configuration
        // (`AppDistribution` = `app_store` vs `installer`, StoreKit tips vs a
        // donation link). Store copies never reach a GitHub rule
        // (`answersAppStoreCopies`).
        GitHubReleaseRule(
            bundleID: "com.rlxone.equinox",
            owner: "rlxone", repo: "Equinox",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Equinox(?:-Installer)?\.dmg$"#,
            installerKind: .dmg),
        ])
}
