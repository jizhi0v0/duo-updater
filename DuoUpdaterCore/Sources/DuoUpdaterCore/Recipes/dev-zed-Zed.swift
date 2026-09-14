import Foundation

enum dev_zed_Zed {
    static let set = AppRecipeSet(
        family: "dev-zed-Zed",
        changelogs: [
        // History: docs/app-audits/dev-zed-Zed.md#历史与实测
        // Zed Preview and Stable — read from the GitHub Releases API list we
        // already fetch for version detection (the `githubRules` in this file,
        // bundle ids `dev.zed.Zed` / `dev.zed.Zed-Preview`): one JSON response
        // instead of the two multi-megabyte zed.dev/releases/{preview,stable} HTML
        // pages this replaced on 2026-08-21 (History has the old scrape and its
        // equivalence check; see `StructuredFormat.zedGitHubReleases`). The two
        // recipes below, one per channel, share one URL; `StructuredChangelogDecoder`
        // splits on `channel` the same way it does for Warp.
        ChangelogRecipe(
            bundleID: "dev.zed.Zed-Preview",
            source: URL(
                string: "https://api.github.com/repos/zed-industries/zed/releases?per_page=40")!,
            maxEntries: 15,
            channel: .preview,
            structuredFormat: .zedGitHubReleases),

        ChangelogRecipe(
            bundleID: "dev.zed.Zed",
            source: URL(
                string: "https://api.github.com/repos/zed-industries/zed/releases?per_page=40")!,
            maxEntries: 15,
            channel: .stable,
            structuredFormat: .zedGitHubReleases),
        ],
        githubRules: [
        // Zed Stable — same repo, but stable ships as non-prerelease tags
        // (`vX.Y.Z`, no `-pre`). `usePrereleases: false` (default) reads
        // `/releases/latest`, which GitHub computes excluding prereleases, so it
        // returns the newest stable (e.g. `v1.5.3`) and never a `-pre` build; the
        // default pattern strips the `v` → `1.5.3`, matching the installed
        // `dev.zed.Zed`'s `CFBundleShortVersionString`. Channel-gated to `.stable`
        // (default) so it can't be served to the Preview install that ships under
        // a different bundle id anyway. Closes the stable-channel version gap the
        // 2026-06-04 audit surfaced (Homebrew `auto_updates` falls through, no
        // `SUFeedURL`).
        //
        // Best-effort one-click: the stable `/releases/latest` ships `Zed-aarch64.dmg`,
        // whose `Zed.app` is a notarized Developer ID build (Team MQ55VZLNZQ, Zed
        // Industries) with bundle id dev.zed.Zed — verified 2026-06-06 to match the
        // install, so the swap passes the VendorInstaller gate. Zed has a robust
        // built-in updater, so this is a fallback for when that hasn't kept up, not a
        // replacement for it. arm64 only (a `Zed-x86_64.dmg` also ships).
        GitHubReleaseRule(
            bundleID: "dev.zed.Zed",
            owner: "zed-industries", repo: "zed",
            installAssetPattern: #"^Zed-aarch64\.dmg$"#,
            installerKind: .dmg),

        // Zed Preview — the Preview channel ships as prereleases (`vX.Y.Z-pre`).
        // MUST declare `channel: .preview`: the Preview install detects as
        // `.preview`, and the source's channel gate refuses any rule whose channel
        // doesn't match the install. Without this the rule defaults to `.stable`
        // and the gate skips it, leaving a real Preview install with no source
        // (regressed when the channel gate landed; caught by the live `--check`).
        //
        // Best-effort one-click, same as stable: the Preview prerelease ships its own
        // `Zed-aarch64.dmg` whose `Zed Preview.app` is the same Team MQ55VZLNZQ build,
        // bundle id dev.zed.Zed-Preview — verified 2026-06-06 to match the install.
        // The rule resolves the right tag (prerelease), so each channel gets its own
        // dmg/bundle id; the gate enforces the Team match. arm64 only.
        // listPageSize: runs of non-`-pre` tags sit between `-pre` releases. 5 was
        // sized for ~67% headroom over the widest such run measured on 2026-09-04,
        // and a 2026-09-14 recheck found the same run (History has the positions
        // and the page sizes).
        GitHubReleaseRule(
            bundleID: "dev.zed.Zed-Preview",
            owner: "zed-industries", repo: "zed",
            usePrereleases: true,
            listPageSize: 5,
            versionPattern: #"v([0-9]+\.[0-9]+\.[0-9]+)-pre"#,
            installAssetPattern: #"^Zed-aarch64\.dmg$"#,
            installerKind: .dmg,
            channel: .preview),
        ],
        githubChannelProofs: [
        // `Zed-aarch64.dmg` is byte-identical in name to stable's — the tag is
        // the only discriminator, and it is in the path:
        // e.g. `…/download/v1.18.0-pre/Zed-aarch64.dmg`.
        ChannelProofKey("dev.zed.Zed-Preview", .preview): .artifact(#"/download/v[0-9.]+-pre/"#),
        ])
}
