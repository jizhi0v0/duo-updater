import Foundation

enum com_alienator88_Sentinel {
    static let set = AppRecipeSet(
        family: "com-alienator88-Sentinel",
        githubRules: [
        // Sentinel — a GUI for Gatekeeper, quarantine removal and re-signing
        // (alienator88/Sentinel, same author as Pearcleaner). No Sparkle; its
        // in-app updater is AlinFoundation's `Updater`, which only downloads
        // when the user clicks Update and then swaps the bundle at once
        // (rm + ditto), so nothing is left staged. Tags have no `v` prefix
        // (`3.1.4`, also two-part `2.2`) and equal CFBundleShortVersionString.
        // One-click installs the universal `Sentinel.zip`, the one asset every
        // release since 1.0 carries (the dmg starts at 2.2, the `-arm` /
        // `-intel` zips at 3.1.3): Team BK8443AXLU, notarized, from 1.5 on.
        GitHubReleaseRule(
            bundleID: "com.alienator88.Sentinel",
            owner: "alienator88", repo: "Sentinel",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Sentinel\.zip$"#,
            installerKind: .zip),
        // 1.0–1.4 shipped as `com.alienator88.sentinel` (lower-case s), ad-hoc
        // signed with no Team, so neither `BundleIDMigration` (needs one Team
        // on both ids) nor the install gate can vouch for the swap: detection
        // only, the user updates by hand once. `variant` keeps its health row
        // and verify baseline apart from the rule above (same repo, same channel).
        GitHubReleaseRule(
            bundleID: "com.alienator88.sentinel",
            owner: "alienator88", repo: "Sentinel",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            variant: "lowercase-id"),
        ])
}
