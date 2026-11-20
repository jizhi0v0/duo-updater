import Foundation

enum com_bitwarden_desktop {
    private static let ossDMG = #"(?:oss-)?Bitwarden-[0-9.]+-universal\.dmg"#

    static let set = AppRecipeSet(
        family: "com-bitwarden-desktop",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // History: docs/app-audits/com-bitwarden-desktop.md#历史与实测
        // Bitwarden — the ONLY rule here that can't read `/releases/latest`: the
        // monorepo tags every client, and the newest release is usually `web-…` or
        // `cli-…`, not the desktop app. Reading
        // the list and taking the first tag matching `desktop-v` is what keeps the
        // desktop version from tracking the web client's. The `$` anchor is
        // defensive rather than observed: every `desktop-v` tag in the newest 100
        // releases is bare and non-prerelease, and the anchor keeps a future
        // suffixed one (a release candidate, say) from reading as stable.
        //
        // Depends on a window the RULE now controls via `listPageSize` (it used
        // to be a source-wide constant). Measured over the newest 100 releases,
        // consecutive `desktop-v` tags are at most 7 apart, so the desktop tag sits
        // well inside a page of 10 today
        // — chosen over the observed 7 to leave margin rather than trim to the
        // minimum, per the same logic as every other rule in `GitHubReleaseRegistry` — but a long
        // burst of web/cli/browser releases would still push it off the page,
        // and the rule would then resolve nothing, which surfaces as the row
        // going quiet rather than as an error.
        //
        // The GitHub rule follows the OSS desktop build: older DMGs have no
        // license prefix and newer ones start with `oss-`. The commercial build
        // publishes beside it at the same version with its own prefix.
        GitHubReleaseRule(
            bundleID: "com.bitwarden.desktop",
            owner: "bitwarden", repo: "clients",
            usePrereleases: true,
            listPageSize: 10,
            versionPattern: #"desktop-v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: "^\(ossDMG)$",
            installerKind: .dmg,
            // The newest release of this monorepo is a web/CLI/browser tag far
            // more often than the desktop one, so a one-row probe
            // here would fall back to the full page most rounds and only add a
            // request. Every other prerelease rule in this registry probes.
            probesNewestFirst: false),
        ],
        oneClickGates: [
            // Both editions share the signed bundle identifier, Team and
            // versions. The packed preload names its edition's source entry.
            OneClickGate(
                bundleID: "com.bitwarden.desktop",
                requirement: .asarEntry(
                    path: "preload.js",
                    pattern: #"(?ms)\A(?!.*bitwarden_license/bit-desktop/src/preload\.ts).*^;// \./src/preload\.ts$"#),
                reason: "the installed copy was not identified as open-source Bitwarden; update it from Bitwarden itself",
                offering: "^(?:GitHub:\(ossDMG)|Homebrew:bitwarden)$"),
            // The native Mac App Store copy uses this same bundle ID. Its own
            // store product can update without the direct-download marker.
            OneClickGate(
                bundleID: "com.bitwarden.desktop",
                requirement: .installedVersion(pattern: ".+"),
                reason: "the Mac App Store copy has no readable version",
                offering: "^App Store:id1352778147$"),
        ])
}
