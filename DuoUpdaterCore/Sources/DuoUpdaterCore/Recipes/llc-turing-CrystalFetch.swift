import Foundation

enum llc_turing_CrystalFetch {
    static let set = AppRecipeSet(
        family: "llc-turing-CrystalFetch",
        githubRules: [
        // CrystalFetch — Windows ISO downloader. No SUFeedURL and no
        // updater framework in the bundle. v-tags, all releases non-prerelease; short == tag (CFBundleVersion
        // is a small build counter). One asset per release, always named
        // `CrystalFetch.dmg`, a universal binary (x86_64 + arm64). The same CI run
        // uploads the App Store build under the same bundle id; that copy is left
        // to the store by the isMASApp gate. Team WDNLXAD4W8, notarized.
        GitHubReleaseRule(
            bundleID: "llc.turing.CrystalFetch",
            owner: "TuringSoftware", repo: "CrystalFetch",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^CrystalFetch\.dmg$"#,
            installerKind: .dmg),
        ])
}
