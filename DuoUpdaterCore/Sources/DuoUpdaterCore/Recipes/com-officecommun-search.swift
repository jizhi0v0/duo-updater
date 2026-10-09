import Foundation

enum com_officecommun_search {
    static let set = AppRecipeSet(
        family: "com-officecommun-search",
        githubRules: [
        // Search (Office Commun, Team 7BYKA895MC) — a WebKit browser. No Sparkle:
        // its own updater reads a signed `appcast.json` on officecommun.com, one
        // per chip from 1.0.5 (`/search/` for Apple silicon, `/search/intel/` for
        // Intel). The same build goes on the GitHub release under `v1.0.4`-style
        // tags, with matching bytes: the feed's `dmgSha256` is the release
        // asset's `digest` (checked 2026-10-09 on 1.0.4).
        //
        // `Search.dmg` is Apple silicon only (arm64 slice, no marker in the
        // name); `Search-Intel.dmg` joins it from 1.0.5. The asset selector reads
        // `Intel` as the x86_64 marker, so an Intel Mac gets that one and Apple
        // silicon gets the unmarked one. One-click installs the notarised,
        // stapled DMG; no nested apps or helpers in the bundle.
        GitHubReleaseRule(
            bundleID: "com.officecommun.search",
            owner: "driceroland", repo: "Search",
            installAssetPattern: #"^Search(-Intel)?\.dmg$"#,
            installerKind: .dmg),
        ])
}
