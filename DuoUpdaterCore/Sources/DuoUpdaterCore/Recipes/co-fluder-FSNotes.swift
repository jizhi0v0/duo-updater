import Foundation

enum co_fluder_FSNotes {
    static let set = AppRecipeSet(
        family: "co-fluder-FSNotes",
        githubRules: [
        // FSNotes (glushchenko/fsnotes) — a plain-text/Markdown notes app. The
        // GitHub build has no updater of its own (no Sparkle, no SUFeedURL, no
        // nested helper or login item), so GitHub Releases is its update route.
        // The Mac App Store sells the same bundle id (Team 866P6MTE92 in the
        // project's MAS config); store copies carry a receipt and the source's
        // `isMASApp` gate leaves them to the store. The iOS app is
        // `co.fluder.mobile.FSNotes-iOS`, a different id.
        //
        // Tags: `v7.x` since v7.0.0, bare `6.10.2`…`1.1.2` before that (one
        // `v6.6.0`), every one a FSNotes_<version>.zip of this same bundle id and
        // Team (6.10.2 read on the real package). `v?` reads both schemes so the
        // list walk-back and history keep working if the vendor drops the `v`
        // again. Prereleases (`7.0.0b6`, `6.0.0beta5`) are flagged `prerelease`
        // and fall outside the anchored pattern anyway; there is no beta toggle
        // in the app.
        //
        // The asset name drops the `v` as well, independently of the tag:
        // v7.3.4 ships `FSNotes_7.3.4.zip`, so the asset pattern takes `v?` too
        // (without it, 7.3.4 read as "no macOS build").
        // One-click: universal zip, co.fluder.FSNotes, Team 866P6MTE92,
        // notarized; 7.3.4/7.3.5/7.3.6 all the same Team.
        GitHubReleaseRule(
            bundleID: "co.fluder.FSNotes",
            owner: "glushchenko", repo: "fsnotes",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^FSNotes_v?[0-9]+(?:\.[0-9]+)+\.zip$"#,
            installerKind: .zip),
        ])
}
