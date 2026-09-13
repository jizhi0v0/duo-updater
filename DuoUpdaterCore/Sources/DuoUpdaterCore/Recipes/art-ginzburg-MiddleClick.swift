import Foundation

enum art_ginzburg_MiddleClick {
    static let set = AppRecipeSet(
        family: "art-ginzburg-MiddleClick",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // MiddleClick — the asset name carries no version (`MiddleClick.zip`).
        // One-click: art.ginzburg.MiddleClick, Team R2294BC6J8, notarized.
        GitHubReleaseRule(
            bundleID: "art.ginzburg.MiddleClick",
            owner: "artginzburg", repo: "MiddleClick",
            installAssetPattern: #"^MiddleClick\.zip$"#,
            installerKind: .zip),
        ])
}
