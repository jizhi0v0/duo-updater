import Foundation

enum info_marcel_dierkes_KeepingYouAwake {
    static let set = AppRecipeSet(
        family: "info-marcel-dierkes-KeepingYouAwake",
        githubRules: [
        // KeepingYouAwake — tags are bare `1.6.8`, one zip per release.
        // One-click: info.marcel-dierkes.KeepingYouAwake, Team 5KESHV9W85, notarized.
        GitHubReleaseRule(
            bundleID: "info.marcel-dierkes.KeepingYouAwake",
            owner: "newmarcel", repo: "KeepingYouAwake",
            installAssetPattern: #"^KeepingYouAwake-[0-9.]+\.zip$"#,
            installerKind: .zip),
        ])
}
