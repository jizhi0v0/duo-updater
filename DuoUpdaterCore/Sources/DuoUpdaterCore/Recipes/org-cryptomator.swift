import Foundation

enum org_cryptomator {
    static let set = AppRecipeSet(
        family: "org-cryptomator",
        githubRules: [
        // Cryptomator — JavaFX/jpackage app, no SUFeedURL. Its own updater reads
        // api.cryptomator.org/connect/apps/desktop/latest-version, a hand-updated
        // per-OS version file whose asset list points at this repo's release
        // assets with the same sha256, so the GitHub release is the source.
        // Bare tags (`1.19.3`); `-alphaN`/`-betaN`/`-rcN` tags are prereleases
        // and not followed (stable only). The CI stamps CFBundleShortVersionString
        // with the Major.Minor.Patch part only, so short == tag on stable.
        // Releases are cut per platform: some carry no dmg (`1.18.1` Windows
        // only, `1.15.3` Linux only), so the install pattern is also the macOS
        // gate that walks back past them. arm64 and x64 dmgs ship separately;
        // pin arm64. Team YZQJQUHA3L, notarized.
        GitHubReleaseRule(
            bundleID: "org.cryptomator",
            owner: "cryptomator", repo: "cryptomator",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Cryptomator-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
