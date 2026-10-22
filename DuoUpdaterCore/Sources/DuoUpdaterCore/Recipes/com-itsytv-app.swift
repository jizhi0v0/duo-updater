import Foundation

enum com_itsytv_app {
    static let set = AppRecipeSet(
        family: "com-itsytv-app",
        githubRules: [
        // Itsytv — menu bar Apple TV remote (nickustinov/itsytv-macos). Its own
        // "Check for updates..." menu item only reads /releases/latest and offers
        // to open the release page in the browser: no download, no staging, no
        // swap, and nothing runs it at launch. The Mac App Store edition shares
        // com.itsytv.app on its own version line; store copies never reach a
        // GitHub rule (`answersAppStoreCopies`).
        //
        // Tags read `v1.6.2`, equal to CFBundleShortVersionString. One dmg per
        // release, universal, Team R892A93W42, notarized. Assets were named
        // `itsytv-<version>.dmg` up to 1.4.1 and `Itsytv-<version>.dmg` since
        // 1.4.2; the pattern takes both. Copies of 1.0.0, 1.0.3, 1.1.0 and 1.2.1
        // are signed by Team 6484NTXXS4, so the Team gate refuses one-click for
        // them (detection still shows the update).
        GitHubReleaseRule(
            bundleID: "com.itsytv.app",
            owner: "nickustinov", repo: "itsytv-macos",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^[Ii]tsytv-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
