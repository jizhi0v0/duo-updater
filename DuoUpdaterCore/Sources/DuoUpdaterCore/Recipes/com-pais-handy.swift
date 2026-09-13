import Foundation

enum com_pais_handy {
    static let set = AppRecipeSet(
        family: "com-pais-handy",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Handy — aarch64 and x64 dmgs ship together; pin aarch64.
        // One-click: com.pais.handy, Team UWFLB4GC25, notarized.
        GitHubReleaseRule(
            bundleID: "com.pais.handy",
            owner: "cjpais", repo: "Handy",
            installAssetPattern: #"^Handy_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
