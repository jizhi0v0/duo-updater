import Foundation

enum ad_neko_mithka {
    static let set = AppRecipeSet(
        family: "ad-neko-mithka",
        githubRules: [
            // GitHub desktop copies use an ad-hoc seal and a published asset
            // digest. Stable and nightly bundles expose the same local channel
            // signals, so the GitHub rule follows the public stable release.
            // The universal ZIP was used through 1.10.3.
            GitHubReleaseRule(
                bundleID: "ad.neko.mithka",
                owner: "iebb", repo: "mithka",
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                installAssetPattern: #"^mithka-[0-9]+\.[0-9]+\.[0-9]+-[0-9]{8}-macos-(?:arm64|universal)\.zip$"#,
                installerKind: .zip,
                installTrust: .publishedDigestOnly),
        ])
}
