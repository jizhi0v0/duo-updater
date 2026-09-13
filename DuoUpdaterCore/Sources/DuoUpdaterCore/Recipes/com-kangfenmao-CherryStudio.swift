import Foundation

enum com_kangfenmao_CherryStudio {
    static let set = AppRecipeSet(
        family: "com-kangfenmao-CherryStudio",
        githubRules: [
        // Shared rationale for 2026-08-16, second pass: Recipes/io-rancherdesktop-app.swift.

        // Cherry Studio — com.kangfenmao.CherryStudio, Team 87242QY66T, notarized.
        // The release carries Linux and Windows artifacts with `arm64` in their
        // names too, so the pattern is anchored on the dmg extension.
        GitHubReleaseRule(
            bundleID: "com.kangfenmao.CherryStudio",
            owner: "CherryHQ", repo: "cherry-studio",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Cherry-Studio-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
