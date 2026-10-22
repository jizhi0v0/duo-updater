import Foundation

enum com_nickustinov_itsypad {
    static let set = AppRecipeSet(
        family: "com-nickustinov-itsypad",
        githubRules: [
        // Itsypad — scratchpad and clipboard manager (nickustinov/itsypad-macos).
        // Its own "Check for updates..." menu item only reads /releases/latest and
        // offers to open the release page in the browser: no download, no staging,
        // no swap, and nothing runs it at launch. No nested apps or login-item
        // helpers; "Open at login" registers the app itself (SMAppService.mainApp).
        // The Mac App Store edition shares com.nickustinov.itsypad on its own
        // version line; store copies never reach a GitHub rule
        // (`answersAppStoreCopies`).
        //
        // Tags read `v1.18.0`, equal to CFBundleShortVersionString. One universal
        // dmg per release, notarized. Assets were named `itsypad-<version>.dmg`
        // up to 1.6.0 and `Itsypad-<version>.dmg` since 1.8.2; the pattern takes
        // both. v1.0.2, v1.8.0 and v1.8.1 carry no asset at all (walked back).
        // Every release is Team R892A93W42 except 1.0.1 (6484NTXXS4), whose
        // copies the Team gate refuses for one-click (detection still shows).
        GitHubReleaseRule(
            bundleID: "com.nickustinov.itsypad",
            owner: "nickustinov", repo: "itsypad-macos",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^[Ii]tsypad-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
