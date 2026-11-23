import Foundation

enum com_treesoop_mycel {
    static let set = AppRecipeSet(
        family: "com-treesoop-mycel",
        githubRules: [
            // The signed public desktop app. The same release also carries
            // an Office Mac server kit and Linux server bundles.
            GitHubReleaseRule(
                bundleID: "com.treesoop.mycel",
                owner: "trina-app", repo: "trina-ax",
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                installAssetPattern: #"^Trina-AX-[0-9]+\.[0-9]+\.[0-9]+-mac-universal\.dmg$"#,
                installerKind: .dmg),
        ])
}
