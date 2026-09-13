import Foundation

enum org_alacritty {
    static let set = AppRecipeSet(
        family: "org-alacritty",
        githubRules: [
        // MARK: Detection-only — the published build can't pass the install gate
        //
        // Each of these resolves a correct version, but its macOS artifact is NOT a
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
