import Foundation

enum org_alacritty {
    static let set = AppRecipeSet(
        family: "org-alacritty",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // MARK: Detection-only — the published build can't pass the install gate
        //
        // Each of these seven — this file, `Recipes/org-flameshot-Flameshot.swift`,
        // `Recipes/com-github-marktext-marktext.swift`, `Recipes/org-darktable.swift`,
        // `Recipes/org-zaproxy-zap-ZAP.swift`, `Recipes/com-BlueBubbles-BlueBubbles-Server.swift`
        // and `Recipes/org-winehq-wine-staging-wine.swift` — resolves a correct version,
        // but its macOS artifact is NOT a
        // notarized Developer ID build (ad-hoc signed or unsigned), so
        // `VendorInstaller` would refuse the swap anyway. Leaving
        // `installAssetPattern` nil states that up front: we surface the version and
        // send the user to the releases page. Verified 2026-08-16 by running
        // `codesign`/`spctl` on the downloaded artifact.

        // Alacritty — ad-hoc signed, no Team ID.
        GitHubReleaseRule(
            bundleID: "org.alacritty",
            owner: "alacritty", repo: "alacritty"),
        ])
}
