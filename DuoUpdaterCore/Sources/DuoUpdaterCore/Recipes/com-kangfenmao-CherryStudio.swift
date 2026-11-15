import Foundation

enum com_kangfenmao_CherryStudio {
    static let set = AppRecipeSet(
        family: "com-kangfenmao-CherryStudio",
        githubRules: [
        // Shared rationale for 2026-08-16, second pass: Recipes/io-rancherdesktop-app.swift.

        // Cherry Studio — com.kangfenmao.CherryStudio, Team 87242QY66T, notarized.
        // The arm64 macOS ZIP is distinct from Linux/Windows artifacts and from
        // the China edition. The numeric version immediately after the product
        // name excludes `Cherry-Studio-CN-…`; keep the `mac-arm64` suffix pinned.
        // History: docs/app-audits/com-kangfenmao-CherryStudio.md#历史与实测
        GitHubReleaseRule(
            bundleID: "com.kangfenmao.CherryStudio",
            owner: "CherryHQ", repo: "cherry-studio",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Cherry-Studio-[0-9.]+-mac-arm64\.zip$"#,
            installerKind: .zip),
        ])
}
