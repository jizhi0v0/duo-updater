import Foundation

enum com_dwarvesv_minimalbar {
    static let set = AppRecipeSet(
        family: "com-dwarvesv-minimalbar",
        githubRules: [
        // History: docs/app-audits/com-dwarvesv-minimalbar.md#历史与实测
        // Hidden Bar's older downloads have no usable Sparkle feed, so use the
        // canonical GitHub repository as their update source. Downloads with the
        // signed GitHub appcast can use the normal Sparkle source.
        //
        // One-click: the `Hidden-Bar-v<ver>-macos.zip` asset holds `Hidden Bar.app`,
        // com.dwarvesv.minimalbar, universal, Team W777S7V8TN (Dwarves Foundation
        // Company Limited), notarized Developer ID.
        GitHubReleaseRule(
            bundleID: "com.dwarvesv.minimalbar",
            owner: "consolelabs", repo: "hidden",
            installAssetPattern: #"^Hidden-Bar-v[0-9.]+-macos\.zip$"#,
            installerKind: .zip),
        ])
}
