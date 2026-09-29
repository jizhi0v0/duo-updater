import Foundation

enum wang_jianing_app_OpenInTerminal {
    static let set = AppRecipeSet(
        family: "wang-jianing-app-OpenInTerminal",
        githubRules: [
        // OpenInTerminal — no SUFeedURL, no in-app updater. The repo also ships
        // OpenInTerminal-Lite / OpenInEditor-Lite from the SAME tag namespace
        // (`v1.2.x` beside the main app's `v2.3.x`, usually published together,
        // so nothing guarantees `/releases/latest` is the main app's). Tags
        // cannot tell them apart;
        // the asset name can: only main-app releases carry `OpenInTerminal.zip`,
        // so a Lite release reaching this rule has no matching asset and the
        // missing-asset walk-back skips it. Keep `installAssetPattern` set for
        // that reason as much as for one-click. short == tag; CFBundleVersion
        // is always `1`. Universal zip. Team C8VX3ZLX5U from 2.3.9, notarized;
        // 2.3.8 was signed by Q33U8R4U57, so the Team-ID gate refuses the
        // one-click from that team's builds.
        GitHubReleaseRule(
            bundleID: "wang.jianing.app.OpenInTerminal",
            owner: "Ji4n1ng", repo: "OpenInTerminal",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenInTerminal\.zip$"#,
            installerKind: .zip),
        ])
}
