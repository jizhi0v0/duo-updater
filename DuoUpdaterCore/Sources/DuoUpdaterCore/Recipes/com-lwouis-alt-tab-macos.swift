import Foundation

enum com_lwouis_alt_tab_macos {
    static let set = AppRecipeSet(
        family: "com-lwouis-alt-tab-macos",
        githubRules: [
        // AltTab — open-source window switcher (lwouis/alt-tab-macos), a
        // menu-bar app (LSUIElement). It updates itself with Sparkle 2, and since
        // v11.0.0 its Info.plist has no `SUFeedURL`: `SparkleDelegate` returns
        // `https://<Domain>/appcast.xml`, `Domain` (= alt-tab.app) being a custom
        // Info.plist key, so no literal feed URL is in the binary and the generic
        // Sparkle source never sees one. Copies up to 10.12.0 still declare a
        // `SUFeedURL` (raw.githubusercontent …/master/appcast.xml through 10.11.0,
        // alt-tab.app/appcast.xml in 10.12.0); `SparkleAppcastSource` answers for
        // those before this rule is asked.
        //
        // GitHub, not a `sparkleFeeds` fill-in, for the 11.x copies. Both feeds
        // serve the same bytes (the appcast is what semantic-release commits to
        // master), it lists exactly the tagged versions, its enclosures are these
        // GitHub assets, and it carries no channels, deltas or phased rollout. It
        // answered the same body whatever `tier`/`license` the app sends
        // (2026-10-26). The fill-in would put Sparkle ahead of this rule and turn
        // the structured release notes into its `releaseNotesLink`, a 277 KB HTML
        // page of every release.
        //
        // Tags read `v11.10.1`; the bundle says 11.10.1 (short and build). One
        // `AltTab-<version>.zip` per release, universal; the two `*.dSYM.zip`
        // assets are debug symbols. Releases before v11.0.0 were deleted from
        // GitHub (their tags remain). com.lwouis.alt-tab-macos, Team QXD7GW8FHY,
        // notarized; the same id since v1 and the same signing identity since
        // v3.0.0 (ad-hoc before that).
        //
        // No helper or login item in the bundle. "Start at login" (on by default)
        // writes ~/Library/LaunchAgents/com.lwouis.alt-tab-macos.plist with
        // `RunAtLoad` and no `KeepAlive`, so launchd does not restart it when it
        // is quit for the swap.
        GitHubReleaseRule(
            bundleID: "com.lwouis.alt-tab-macos",
            owner: "lwouis", repo: "alt-tab-macos",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^AltTab-[0-9]+(?:\.[0-9]+)+\.zip$"#,
            installerKind: .zip),
        ])
}
