import Foundation

enum ru_starmel_OpenSuperWhisper {
    static let set = AppRecipeSet(
        family: "ru-starmel-OpenSuperWhisper",
        githubRules: [
        // OpenSuperWhisper — bare tags (no `v`), and the dmg asset name is
        // versionless (`OpenSuperWhisper.dmg` on every release), so the version
        // pattern must anchor `$` and the asset pattern must be the literal
        // filename. All releases are stable so far; `$` keeps a future
        // `0.2.0-beta.1` from reading as stable. arm64-only dmg (the cask is
        // `depends_on arch: :arm64`), Team 8LLDD7HWZK, notarized. Mounted
        // 0.1.0: ru.starmel.OpenSuperWhisper, short == tag, build 13.
        GitHubReleaseRule(
            bundleID: "ru.starmel.OpenSuperWhisper",
            owner: "starmel", repo: "OpenSuperWhisper",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenSuperWhisper\.dmg$"#,
            installerKind: .dmg),
        ])
}
