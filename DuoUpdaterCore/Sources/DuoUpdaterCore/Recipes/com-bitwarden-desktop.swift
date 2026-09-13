import Foundation

enum com_bitwarden_desktop {
    static let set = AppRecipeSet(
        family: "com-bitwarden-desktop",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Bitwarden — the ONLY rule here that can't read `/releases/latest`: the
        // monorepo tags every client, and the newest release is usually `web-…` or
        // `cli-…`, not the desktop app (on 2026-08-16 `/releases/latest` was
        // `web-v2026.7.1` while the desktop app sat at `desktop-v2026.7.0`). Reading
        // the list and taking the first tag matching `desktop-v` is what keeps the
        // desktop version from tracking the web client's. The `$` anchor is
        // defensive rather than observed: every `desktop-v` tag in the newest 100
        // releases is bare and non-prerelease, and the anchor keeps a future
        // suffixed one (a release candidate, say) from reading as stable.
        //
        // Depends on a window the RULE now controls via `listPageSize` (it used
        // to be a source-wide constant). Measured over the newest 100 releases,
        // consecutive `desktop-v` tags are at most 7 apart (re-verified
        // 2026-09-04: same 7, `desktop-v2026.6.0`→`desktop-v2026.5.0` and three
        // other pairs), so the desktop tag sits well inside a page of 10 today
        // — chosen over the observed 7 to leave margin rather than trim to the
        // minimum, per the same logic as every other rule in `GitHubReleaseRegistry` — but a long
        // burst of web/cli/browser releases would still push it off the page,
        // and the rule would then resolve nothing, which surfaces as the row
        // going quiet rather than as an error.
        //
        // One-click: the universal dmg is com.bitwarden.desktop, Team LTZ2PFU5D6,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.bitwarden.desktop",
            owner: "bitwarden", repo: "clients",
            usePrereleases: true,
            listPageSize: 10,
            versionPattern: #"desktop-v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Bitwarden-[0-9.]+-universal\.dmg$"#,
            installerKind: .dmg,
            // The newest release of this monorepo is a web/CLI/browser tag far
            // more often than the desktop one (measured 2026-09-05: the one-row
            // page was `web-v…`, and the same shape held across the newest 100
            // releases, `desktop-v` tags at most 7 apart), so a one-row probe
            // here would fall back to the full page most rounds and only add a
            // request. Every other prerelease rule in this registry probes.
            probesNewestFirst: false),
        ])
}
