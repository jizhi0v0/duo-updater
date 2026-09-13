import Foundation

enum me_qii404_another_redis_desktop_manager {
    static let set = AppRecipeSet(
        family: "me-qii404-another-redis-desktop-manager",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Another Redis Desktop Manager — mac arm64/x64 dmgs plus Windows/Linux
        // artifacts; pin the mac arm64 dmg.
        // One-click: me.qii404.another-redis-desktop-manager, Team 68JN8DV835,
        // notarized.
        GitHubReleaseRule(
            bundleID: "me.qii404.another-redis-desktop-manager",
            owner: "qishibo", repo: "AnotherRedisDesktopManager",
            installAssetPattern: #"^Another-Redis-Desktop-Manager-mac-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
