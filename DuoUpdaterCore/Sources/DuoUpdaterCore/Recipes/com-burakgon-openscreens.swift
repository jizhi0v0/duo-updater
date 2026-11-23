import Foundation

enum com_burakgon_openscreens {
    static let bundleID = "com.burakgon.openscreens"

    static let set = AppRecipeSet(
        family: "com-burakgon-openscreens",
        githubRules: [
            // History: docs/app-audits/com-burakgon-openscreens.md#历史与实测
            // The Mac DMG and its checksum share a release with iOS release notes.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "burakgon", repo: "OpenScreens",
                versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                installAssetPattern: #"^OpenScreens-[0-9]+\.[0-9]+\.[0-9]+\.dmg$"#,
                installerKind: .dmg),
        ])
}
