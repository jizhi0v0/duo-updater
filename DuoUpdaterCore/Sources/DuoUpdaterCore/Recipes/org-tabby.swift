import Foundation

enum org_tabby {
    static let set = AppRecipeSet(
        family: "org-tabby",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Tabby — terminal. macOS arm64/x86_64 dmgs and zips plus "portable" zips
        // ship together; pin the arm64 dmg.
        // One-click: org.tabby, Team V4JSMC46SY, notarized.
        GitHubReleaseRule(
            bundleID: "org.tabby",
            owner: "Eugeny", repo: "tabby",
            installAssetPattern: #"^tabby-[0-9.]+-macos-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
