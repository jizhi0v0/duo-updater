import Foundation

enum com_alienator88_Pearcleaner {
    static let set = AppRecipeSet(
        family: "com-alienator88-Pearcleaner",
        githubRules: [
        // History: docs/app-audits/com-alienator88-Pearcleaner.md#历史与实测
        // Pearcleaner — tags have no `v` prefix. One-click installs the universal
        // `Pearcleaner.dmg`, whose `Pearcleaner.app` reports the tag as its
        // `CFBundleShortVersionString` and is a notarized Developer ID build (Team
        // BK8443AXLU) with the same bundle id as the install, so the in-place swap
        // passes the VendorInstaller gate. The universal dmg avoids the arch-specific
        // `-arm`/`-intel` zips. Pearcleaner has its own in-app updater (not Sparkle),
        // so this one-click is a best-effort fallback beside it.
        GitHubReleaseRule(
            bundleID: "com.alienator88.Pearcleaner",
            owner: "alienator88", repo: "Pearcleaner",
            installAssetPattern: #"^Pearcleaner\.dmg$"#,
            installerKind: .dmg),
        ])
}
