import Foundation

enum info_marcel_dierkes_KeepingYouAwake {
    static let set = AppRecipeSet(
        family: "info-marcel-dierkes-KeepingYouAwake",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // KeepingYouAwake — tags are bare, e.g. `1.6.8`, one zip per release.
        // One-click: info.marcel-dierkes.KeepingYouAwake, Team 5KESHV9W85, notarized.
        GitHubReleaseRule(
            bundleID: "info.marcel-dierkes.KeepingYouAwake",
            owner: "newmarcel", repo: "KeepingYouAwake",
            installAssetPattern: #"^KeepingYouAwake-[0-9.]+\.zip$"#,
            installerKind: .zip),
        ])
}
