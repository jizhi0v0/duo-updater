import Foundation

enum com_github_GitHubClient {
    static let set = AppRecipeSet(
        family: "com-github-GitHubClient",
        probes: [
        // The official Apple silicon download redirects to the production ZIP.
        // Read and validate its Location once, then install that exact archive.
        VendorProbeRecipe(
            bundleID: "com.github.GitHubClient",
            url: URL(string: "https://central.github.com/deployments/desktop/desktop/latest/darwin-arm64")!,
            mode: .redirectFilename,
            versionPattern: #"^https://desktop\.githubusercontent\.com/releases/([0-9]+\.[0-9]+\.[0-9]+)-[0-9a-f]+/GitHubDesktop-arm64\.zip$"#,
            downloadURL: URL(string: "https://desktop.github.com/download/"),
            changelogURL: URL(string: "https://desktop.github.com/release-notes/"),
            install: VendorInstallSpec(urlSource: .bodyPattern(#"^(.+)$"#), kind: .zip),
            followRedirects: false,
            hostRequirement: VendorHostRequirement(architectures: [.arm64])),
        ],
        changelogs: [
        // History: docs/app-audits/com-github-GitHubClient.md#历史与实测
        // ── GitHub Desktop — one bundle id (`com.github.GitHubClient`), TWO channels
        // distinguished only by the install's `-betaN` version suffix (see
        // ReleaseChannel.detect). The desktop.github.com
        // /release-notes page is a client-rendered SPA; its data is a JSONP-ish feed
        // at central.github.com/deployments/desktop/desktop/changelog.json, and the
        // page's `?env=beta` maps to a `?env=beta` query on that feed (read from
        // desktop-releases.js). Fetched without the `callback` param it returns a
        // plain JSON array, newest-first, each element e.g.:
        //   {"name":"","notes":["[Fixed] …- #22219", …],
        //    "pub_date":"2026-06-01T17:43:05Z","version":"3.5.12"}
        // `notes` is already an array of one-line strings (each keeping the vendor's
        // own `[Fixed]`/`[Added]`/`[Improved]` prefix and trailing `- #issue`) — this
        // feed was structured JSON all along, so it's decoded by
        // `StructuredChangelogDecoder.decodeGitHubDesktop` rather than regex-scraped;
        // see `.gitHubDesktopChangelog` for the shape. Stable feed carries bare
        // versions (e.g. `3.5.12`); beta carries e.g. `3.5.12-beta2`. A parse miss
        // just falls back to embedding the SPA. `channel` here is only for the recipe-registry lookup
        // (`ChangelogRecipeRegistry.recipe(forBundleID:channel:)` picks stable vs.
        // beta by it) — the decoder itself takes no channel, since stable and beta
        // are two different URLs, not one document split by a channel key.
        ChangelogRecipe(
            bundleID: "com.github.GitHubClient",
            source: URL(string: "https://central.github.com/deployments/desktop/desktop/changelog.json")!,
            channel: .stable,
            structuredFormat: .gitHubDesktopChangelog),

        // GitHub Desktop Beta — same feed with `?env=beta`, matched by `channel:
        // .beta` so a `-betaN`-detected install gets beta notes (e.g. `3.5.12-beta2`)
        // instead of the stable train. Identical structured decoder.
        ChangelogRecipe(
            bundleID: "com.github.GitHubClient",
            source: URL(string: "https://central.github.com/deployments/desktop/desktop/changelog.json?env=beta")!,
            channel: .beta,
            structuredFormat: .gitHubDesktopChangelog),
        ],
        githubRules: [
        // GitHub Desktop Beta stays on the Releases list. The same bundle id
        // and name as stable make the installed `-betaN` version suffix the
        // channel discriminator. Keep that suffix in the extracted version.
        // The arm64 ZIP is signed by GitHub (Team VEKTX9H2N7).
        // listPageSize: the newest release is often the stable `release-…` tag one
        // spot above the newest beta, and consecutive `-betaN` tags can sit several
        // releases apart; 8 keeps 2x headroom over the widest run measured between
        // two of them (History has the dated counts).
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
        // e.g. `…/download/release-3.6.5-beta1/GitHub.Desktop-arm64.zip`.
        ChannelProofKey("com.github.GitHubClient", .beta):
            .artifact(#"/download/release-[0-9.]+-beta[0-9]+/"#),
        ])
}
