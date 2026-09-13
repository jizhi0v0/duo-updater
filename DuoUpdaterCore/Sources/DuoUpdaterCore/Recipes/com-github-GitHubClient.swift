import Foundation

enum com_github_GitHubClient {
    static let set = AppRecipeSet(
        family: "com-github-GitHubClient",
        changelogs: [
        // ── GitHub Desktop — one bundle id (`com.github.GitHubClient`), TWO channels
        // distinguished only by the install's `-betaN` version suffix (see
        // ReleaseChannel.detect / the GitHubReleaseRule pair). The desktop.github.com
        // /release-notes page is a client-rendered SPA; its data is a JSONP-ish feed
        // at central.github.com/deployments/desktop/desktop/changelog.json, and the
        // page's `?env=beta` maps to a `?env=beta` query on that feed (read from
        // desktop-releases.js). Fetched without the `callback` param it returns a
        // plain JSON array, newest-first, each element:
        //   {"name":"","notes":["[Fixed] …- #22219", …],
        //    "pub_date":"2026-06-01T17:43:05Z","version":"3.5.12"}
        // `notes` is already an array of one-line strings (each keeping the vendor's
        // own `[Fixed]`/`[Added]`/`[Improved]` prefix and trailing `- #issue`) — this
        // feed was structured JSON all along, so it's decoded by
        // `StructuredChangelogDecoder.decodeGitHubDesktop` rather than regex-scraped;
        // see `.gitHubDesktopChangelog` for the shape. Stable feed carries bare
        // `3.5.12`; beta carries `3.5.12-beta2`. A parse miss just falls back to
        // embedding the SPA. `channel` here is only for the recipe-registry lookup
        // (`ChangelogRecipeRegistry.recipe(forBundleID:channel:)` picks stable vs.
        // beta by it) — the decoder itself takes no channel, since stable and beta
        // are two different URLs, not one document split by a channel key.
        ChangelogRecipe(
            bundleID: "com.github.GitHubClient",
            source: URL(string: "https://central.github.com/deployments/desktop/desktop/changelog.json")!,
            channel: .stable,
            structuredFormat: .gitHubDesktopChangelog),

        // GitHub Desktop Beta — same feed with `?env=beta`, matched by `channel:
        // .beta` so a `-betaN`-detected install gets beta notes (`3.5.12-beta2`)
        // instead of the stable train. Identical structured decoder.
        ChangelogRecipe(
            bundleID: "com.github.GitHubClient",
            source: URL(string: "https://central.github.com/deployments/desktop/desktop/changelog.json?env=beta")!,
            channel: .beta,
            structuredFormat: .gitHubDesktopChangelog),
        ],
        githubRules: [
        // GitHub Desktop — TWO channels share ONE bundle id (com.github.GitHubClient)
        // AND one app name ("GitHub Desktop"): Stable ships `release-X.Y.Z` tags,
        // Beta ships `release-X.Y.Z-betaN` prereleases, interleaved AHEAD of
        // production in the list (`release-3.5.12-beta2` sits above `release-3.5.12`).
        // Unlike Zed (separate bundle ids per channel), the ONLY channel signal is
        // the installed version string's `-betaN` suffix — `ReleaseChannel.detect`'s
        // step-5 `-beta[0-9]+` shape flips a `3.5.12-beta2` install to `.beta`, and
        // the channel gate then serves it the beta rule below, never this stable one.
        // Both verified end-to-end 2026-06-06: stable `GitHub.Desktop-arm64.zip`
        // (3.5.12) and beta (3.5.12-beta2) are the same notarized Developer ID build
        // (Team VEKTX9H2N7, GitHub), same bundle id; the beta is the copy installed
        // on this machine. Squirrel self-updater, so one-click is a best-effort
        // fallback. arm64 only (a `-x64.zip` also ships), swapped in place.
        //
        // Stable: `/releases/latest` resolves to the production tag (betas are
        // prerelease=true), so usePrereleases=false; the `$`-anchored pattern
        // captures only the bare X.Y.Z and refuses any `-beta`/`-test` suffix.
        GitHubReleaseRule(
            bundleID: "com.github.GitHubClient",
            owner: "desktop", repo: "desktop",
            usePrereleases: false,
            versionPattern: #"release-([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^GitHub\.Desktop-arm64\.zip$"#,
            installerKind: .zip),

        // GitHub Desktop Beta — same repo/asset, `channel: .beta` so the gate serves
        // it only to a `-betaN`-detected install. usePrereleases scans the list and
        // takes the first `release-X.Y.Z-betaN` tag (newest beta, since GitHub
        // returns newest-first); the pattern KEEPS the `-betaN` so the captured
        // `3.5.12-beta2` equals the installed CFBundleShortVersionString (no phantom
        // update/downgrade against the stable 3.5.12). Same `GitHub.Desktop-arm64.zip`
        // one-click as stable.
        // listPageSize: not installed on the measuring machine, so measured
        // directly against the live endpoint (2026-09-04, newest 100 releases):
        // first-match index 1 (the newest release is often the stable
        // `release-…` tag one spot above), worst run between two `-betaN` tags
        // is 4 (`release-3.4.16-beta1`→`release-3.4.13-beta2`). 8 keeps 2x
        // headroom over that.
        GitHubReleaseRule(
            bundleID: "com.github.GitHubClient",
            owner: "desktop", repo: "desktop",
            usePrereleases: true,
            listPageSize: 8,
            versionPattern: #"release-([0-9]+\.[0-9]+\.[0-9]+-beta[0-9]+)$"#,
            installAssetPattern: #"^GitHub\.Desktop-arm64\.zip$"#,
            installerKind: .zip,
            channel: .beta),
        ],
        githubChannelProofs: [
        // Likewise, as for Zed Preview (`Recipes/dev-zed-Zed.swift`), `GitHub.Desktop-arm64.zip`:
        // `…/download/release-3.6.5-beta1/GitHub.Desktop-arm64.zip`.
        ChannelProofKey("com.github.GitHubClient", .beta):
            .artifact(#"/download/release-[0-9.]+-beta[0-9]+/"#),
        ])
}
