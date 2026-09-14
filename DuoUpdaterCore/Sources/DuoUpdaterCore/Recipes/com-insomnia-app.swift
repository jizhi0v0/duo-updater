import Foundation

enum com_insomnia_app {
    static let set = AppRecipeSet(
        family: "com-insomnia-app",
        githubRules: [
        // History: docs/app-audits/com-insomnia-app.md#历史与实测
        // Insomnia (stable) — Kong/insomnia is a monorepo whose Releases are tagged
        // per package (`core@X.Y.Z` is the Insomnia desktop app; `lib@…`/`inso@…`
        // are sibling packages). `/releases/latest` could resolve to a non-core
        // release, so scan the list (usePrereleases) and take the first tag the
        // pattern matches — lib@/inso@ yield no capture and are skipped.
        //
        // The `$` anchor is load-bearing: Kong publishes prerelease tags
        // (e.g. `core@13.0.0-beta.0`) BEFORE the matching stable, and a prerelease of
        // a *new* line sorts newest — first in the list. An unanchored
        // `core@(X.Y.Z)` captures `13.0.0` out of `core@13.0.0-beta.0` and reports that
        // beta to stable users as "13.0.0". With
        // `$`, only suffix-free stable tags (e.g. `core@12.6.0`) match; the beta channel,
        // if/when added, is a separate `channel: .beta` rule.
        //
        // Best-effort one-click: the `Insomnia.Core-<ver>.dmg` (universal) wraps
        // `Insomnia.app` — a notarized Developer ID build (Team FX44YY62GV, Kong Inc.)
        // reporting version == tag, bundle id
        // com.insomnia.app. The sibling `inso-macos-*` assets are the CLI, not the
        // desktop app — the `Insomnia.Core-` anchor excludes them. Electron app with
        // its own updater, so a fallback; the Team-ID gate (`VendorInstaller`)
        // enforces the match at install time.
        // listPageSize: measured directly against the live endpoint (2026-09-04,
        // newest 100 releases):
        // first-match index 0, worst run of non-`core@` tags between two
        // `core@` releases is 9 (`core@11.0.0`→`core@10.3.1`, the Design/CLI
        // trains publish in between). 15 keeps ~67% headroom over that.
        GitHubReleaseRule(
            bundleID: "com.insomnia.app",
            owner: "Kong", repo: "insomnia",
            usePrereleases: true,
            listPageSize: 15,
            versionPattern: #"core@([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^Insomnia\.Core-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
