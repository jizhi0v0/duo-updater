import Foundation

enum com_extraheadroom_headroom {
    static let set = AppRecipeSet(
        family: "com-extraheadroom-headroom",
        githubRules: [
        // Headroom — a Tauri menu-bar app that routes Claude Code and Codex
        // through a local compression proxy (gglucass/headroom-desktop). No
        // SUFeedURL: its own updater is Tauri's, reading
        // `releases/latest/download/latest.json` in this same repo, so this
        // rule reads exactly what the stable updater is offered. The release
        // workflow publishes every release as a prerelease and flips it to
        // latest only once every platform's manifest entry is in.
        //
        // Tags read `v0.9.46`, the bundle's short and build version alike.
        // Excluded on purpose: `-rc.N` (beta channel, served from the
        // `staging-rolling` release), `-gt.N` (a signing-migration test signed
        // by another Team), the rolling pointer releases, and
        // `vendor-wheels-v1`, which carries Python wheels the app downloads at
        // runtime, not the app.
        //
        // One-click: `Headroom_<version>_mac.dmg` is universal,
        // com.extraheadroom.headroom, Team ZA6LNF9PF9, notarized; the anchored
        // asset pattern keeps `-rc`/`-gt` dmgs out.
        GitHubReleaseRule(
            bundleID: "com.extraheadroom.headroom",
            owner: "gglucass", repo: "headroom-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Headroom_[0-9]+(?:\.[0-9]+)+_mac\.dmg$"#,
            installerKind: .dmg),
        ])
}
