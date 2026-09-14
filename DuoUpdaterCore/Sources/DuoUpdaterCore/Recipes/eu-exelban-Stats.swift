import Foundation

enum eu_exelban_Stats {
    static let set = AppRecipeSet(
        family: "eu-exelban-Stats",
        githubRules: [
        // History: docs/app-audits/eu-exelban-Stats.md#历史与实测
        // Stats — macOS menu-bar system monitor. Tags carry a `v` prefix
        // (stripped by the default pattern). Stable channel, no prereleases.
        //
        // One-click: the single `Stats.dmg` asset has `Stats.app` at the dmg root
        // (beside the usual /Applications symlink), bundle id eu.exelban.Stats,
        // notarized Developer ID build signed by Team RP2S87B72W (Serhiy
        // Mytrovtsiy), matching the installed copy, so the swap passes the
        // VendorInstaller gate. Its `CFBundleShortVersionString` equals the tag, so
        // the probed version is the marketing version we compare against — no
        // build-number trap (checked 2026-08-08; History has the version). Stats
        // has its own in-app updater but ships no Sparkle feed, so this is a plain
        // one-click.
        GitHubReleaseRule(
            bundleID: "eu.exelban.Stats",
            owner: "exelban", repo: "stats",
            installAssetPattern: #"^Stats\.dmg$"#,
            installerKind: .dmg),
        ])
}
