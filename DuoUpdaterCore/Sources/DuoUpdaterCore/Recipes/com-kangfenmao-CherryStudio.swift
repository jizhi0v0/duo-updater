import Foundation

enum com_kangfenmao_CherryStudio {
    static let set = AppRecipeSet(
        family: "com-kangfenmao-CherryStudio",
        githubRules: [
        // Shared rationale for 2026-08-16, second pass: Recipes/io-rancherdesktop-app.swift.

        // Cherry Studio — com.kangfenmao.CherryStudio, Team 87242QY66T, notarized.
        // The release carries Linux and Windows artifacts with `arm64` in their
        // names too, so the pattern is anchored on the dmg extension.
        //
        // BOTH macOS spellings. v2.0.10 renamed the artifacts from
        // `Cherry-Studio-<ver>-arm64.dmg` to `Cherry-Studio-<ver>-mac-arm64.dmg`
        // (live release list, 2026-09-17), so the old spelling stopped matching at
        // exactly that release: the walk back past asset-less releases — bounded at
        // five, `GitHubReleasesSource.maxReleasesWithoutMacOSAsset` — then answered
        // **2.0.9** for a repo whose newest release was 2.0.14, and offered that
        // 2.0.9 dmg as the one-click, while every copy on 2.0.10–2.0.13 read "up to
        // date". Admitting both keeps a pre-rename release installable too.
        //
        // The China edition ships `Cherry-Studio-CN-<ver>-mac-arm64.dmg` and must
        // stay excluded: `[0-9.]` right after `Cherry-Studio-` cannot match `CN-`.
        GitHubReleaseRule(
            bundleID: "com.kangfenmao.CherryStudio",
            owner: "CherryHQ", repo: "cherry-studio",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Cherry-Studio-[0-9.]+-(?:mac-)?arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
