import Foundation

enum com_crystalidea_macsfancontrol {
    static let set = AppRecipeSet(
        family: "com-crystalidea-macsfancontrol",
        githubRules: [
        // Macs Fan Control — tags carry a `v` prefix (stripped by the pattern).
        // One-click installs `macsfancontrol.zip`, which wraps `Macs Fan Control.app`:
        // verified 2026-06-06 it's a notarized Developer ID build (Team ACC5R6RH47,
        // Ilya Parniuk) reporting version 1.5.21 == tag, bundle id
        // com.crystalidea.macsfancontrol matching the install → passes the gate. Two
        // other zips ship (`_legacy` for old macOS, the Windows `_setup.exe`); the
        // bare `macsfancontrol.zip` is the current-macOS app. Swapped in place like
        // the other zip recipes. No Sparkle, so a plain one-click.
        GitHubReleaseRule(
            bundleID: "com.crystalidea.macsfancontrol",
            owner: "crystalidea", repo: "macs-fan-control",
            installAssetPattern: #"^macsfancontrol\.zip$"#,
            installerKind: .zip),
        ])
}
