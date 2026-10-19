import Foundation

enum dev_pennybar_PennyBar {
    static let set = AppRecipeSet(
        family: "dev-pennybar-PennyBar",
        githubRules: [
        // PennyBar (anxndsgn/pennybar, Team 9FX2RB5LD6) — a menu-bar app that
        // shows cloud billing (Cloudflare, Vercel, Neon, …). No SUFeedURL and no
        // updater of its own; no Homebrew cask. Its release workflow publishes
        // one asset, `PennyBar-<version>.dmg`, where `scripts/release.sh` stamps
        // `CFBundleShortVersionString` from the tag with the `v` stripped, so the
        // tag and the installed version agree by construction (0.1.0 checked on
        // the real dmg). No prereleases; the anchored pattern leaves any future
        // `-suffix` tag unread.
        //
        // One-click: notarized Developer ID dmg, arm64, root holds `PennyBar.app`
        // beside an /Applications link; no nested helpers.
        GitHubReleaseRule(
            bundleID: "dev.pennybar.PennyBar",
            owner: "anxndsgn", repo: "pennybar",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^PennyBar-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
