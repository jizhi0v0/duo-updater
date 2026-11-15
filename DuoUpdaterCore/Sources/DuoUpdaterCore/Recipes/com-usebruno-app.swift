import Foundation

enum com_usebruno_app {
    // History: docs/app-audits/com-usebruno-app.md#历史与实测
    static let set = AppRecipeSet(
        family: "com-usebruno-app",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Bruno — API client, Electron, no Sparkle. Each release ships BOTH
        // `bruno_<ver>_arm64_mac.zip` and `bruno_<ver>_x64_mac.zip`, so the pattern
        // pins arm64 rather than relying on ordering. One-click verified: the arm64
        // ZIP holds com.usebruno.app, Team W7LPPWA48L, notarized.
        GitHubReleaseRule(
            bundleID: "com.usebruno.app",
            owner: "usebruno", repo: "bruno",
            installAssetPattern: #"^bruno_[0-9.]+_arm64_mac\.zip$"#,
            installerKind: .zip),
        ])
}
