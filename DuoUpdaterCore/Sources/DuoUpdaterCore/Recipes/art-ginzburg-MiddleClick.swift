import Foundation

enum art_ginzburg_MiddleClick {
    static let set = AppRecipeSet(
        family: "art-ginzburg-MiddleClick",
        githubRules: [
        // MiddleClick — the asset name carries no version (`MiddleClick.zip`).
        // One-click: art.ginzburg.MiddleClick, Team R2294BC6J8, notarized.
        GitHubReleaseRule(
            bundleID: "art.ginzburg.MiddleClick",
            owner: "artginzburg", repo: "MiddleClick",
            installAssetPattern: #"^MiddleClick\.zip$"#,
            installerKind: .zip),
        ])
}
