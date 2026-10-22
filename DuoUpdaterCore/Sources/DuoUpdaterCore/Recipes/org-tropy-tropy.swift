import Foundation

enum org_tropy_tropy {
    static let set = AppRecipeSet(
        family: "org-tropy-tropy",
        githubRules: [
        // Tropy — research photo management, Electron (tropy/tropy). Its own
        // updater is Electron's built-in `autoUpdater` (Squirrel.Mac), not
        // electron-updater and not Sparkle: `src/main/updater.js` points it at
        // `https://tropy.org/update/<channel>/darwin/<arch>/<version>`, which
        // answers with this repo's `tropy-<v>-darwin-arm64.zip`, downloads it
        // into `~/Library/Caches/org.tropy.tropy.ShipIt/` and swaps on quit
        // (`SelfUpdaterStaging` reads that ShipIt state already). No
        // `app-update.yml`, no `SUFeedURL`, so no generic source covers it.
        //
        // Stable and beta are SEPARATE apps: `scripts/build.js` sets
        // `appBundleId` to `org.tropy.tropy` for a release version and to
        // `org.tropy.tropy-beta` ("Tropy Beta.app") for a `-beta.N` one, so the
        // two rules below never see each other's copies.
        //
        // Stable tags read `v1.17.3`; up to 1.9.0 (2021) they had no `v`
        // (`1.9.0`, `1.8.2` … `1.0.0`). Those are the same app with the same
        // `tropy-<v>.dmg` assets, so `v?` reads them rather than leaving them
        // out. `daedalus` is a bare tag with no release, and the anchors keep
        // `-beta.N` tags out.
        //
        // One-click: the `-darwin-arm64.zip` — the exact archive Tropy's own
        // updater installs (the feed's `url`). There is no universal build: the
        // release workflow builds x64 and arm64 separately and `tropy-<v>.dmg`
        // / `-darwin.zip` are x64. The zip rather than `tropy-<v>-arm64.dmg`
        // because v1.16.2 shipped without its arm64 dmg (only the
        // `.integrity` file) but with the zip. Real 1.17.2 and 1.17.3 zips:
        // org.tropy.tropy, Team 8LAYR367YV, notarized.
        GitHubReleaseRule(
            bundleID: "org.tropy.tropy",
            owner: "tropy", repo: "tropy",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^tropy-[0-9]+(?:\.[0-9]+)+-darwin-arm64\.zip$"#,
            installerKind: .zip),

        // Tropy Beta — `org.tropy.tropy-beta`, whose CFBundleShortVersionString
        // keeps the suffix verbatim ("1.18.0-beta.6" on the real artifact), so
        // the captured version keeps it too. Only beta tags: a stable release
        // is a different app, never what a beta copy becomes. Its own updater
        // reads `tropy.org/update/beta/…`, which answered 204 (nothing) for
        // 1.17.3-beta.1, 1.18.0-beta.5 and 1.18.0-beta.6 on 2026-10-22, so
        // this rule is the only thing that tells a beta copy it is behind.
        //
        // listPageSize 8: worst run between two beta tags in the newest 100
        // releases is 2 (2026-10-22), floor 3, pinned in
        // `GitHubListPageSizeTests`. Real 1.18.0-beta.5 and beta.6 zips:
        // org.tropy.tropy-beta, Team 8LAYR367YV, notarized.
        GitHubReleaseRule(
            bundleID: "org.tropy.tropy-beta",
            owner: "tropy", repo: "tropy",
            usePrereleases: true,
            listPageSize: 8,
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+-beta\.[0-9]+)$"#,
            installAssetPattern: #"^tropy-[0-9]+(?:\.[0-9]+)+-beta\.[0-9]+-darwin-arm64\.zip$"#,
            installerKind: .zip,
            channel: .beta),
        ],
        // The beta asset URL carries its `-beta.N` tag in the path (and in the
        // file name), which no stable release's URL does.
        githubChannelProofs: [
        ChannelProofKey("org.tropy.tropy-beta", .beta):
            .artifact(#"/download/v[0-9.]+-beta\.[0-9]+/tropy-[0-9.]+-beta\.[0-9]+-darwin-arm64\.zip$"#),
        ])
}
