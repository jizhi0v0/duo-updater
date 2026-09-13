import Foundation

enum com_alienator88_Pearcleaner {
    static let set = AppRecipeSet(
        family: "com-alienator88-Pearcleaner",
        githubRules: [
        // Pearcleaner — tags have no `v` prefix. One-click installs the universal
        // `Pearcleaner.dmg`: verified 2026-06-06 the dmg's `Pearcleaner.app` is a
        // notarized Developer ID build (Team BK8443AXLU, Marius Lupascu) reporting
        // CFBundleShortVersionString 5.4.3 == tag, bundle id com.alienator88.Pearcleaner
        // matching the install — so the in-place swap passes the VendorInstaller gate.
        // The universal dmg avoids the arch-specific `-arm`/`-intel` zips. No self-
        // updater (a Sparkle-less menu utility), so a plain one-click, not best-effort.
        GitHubReleaseRule(
            bundleID: "com.alienator88.Pearcleaner",
            owner: "alienator88", repo: "Pearcleaner",
            installAssetPattern: #"^Pearcleaner\.dmg$"#,
            installerKind: .dmg),
        ])
}
