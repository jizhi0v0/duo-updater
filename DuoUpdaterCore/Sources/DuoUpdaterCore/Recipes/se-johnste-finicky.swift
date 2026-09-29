import Foundation

enum se_johnste_finicky {
    static let set = AppRecipeSet(
        family: "se-johnste-finicky",
        githubRules: [
        // Finicky — Go menu-bar browser router. No SUFeedURL; its own update
        // check GETs finicky.johnste.se/update-check?version=<CFBundleVersion>,
        // which answers the GitHub release's tag and a download URL pointing at
        // that release's `Finicky.dmg` (no device id in the request). v-tags;
        // stable releases are plain `vX.Y.Z`, alpha/beta tracks are GitHub
        // prereleases with a `-alpha`/`-beta` suffix, which the anchored pattern
        // and usePrereleases=false both keep out. short == tag == CFBundleVersion.
        // One unversioned `Finicky.dmg` per release since v4.0.0 (the v3 line
        // shipped `Finicky.zip`, which the pattern skips), universal; Team C3XWNKDP3M,
        // notarized.
        GitHubReleaseRule(
            bundleID: "se.johnste.finicky",
            owner: "johnste", repo: "finicky",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Finicky\.dmg$"#,
            installerKind: .dmg),
        ])
}
