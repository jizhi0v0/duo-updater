import Foundation

enum app_yaak_desktop {
    static let set = AppRecipeSet(
        family: "app-yaak-desktop",
        changelogs: [
        // History: docs/app-audits/app-yaak-desktop.md#历史与实测
        // Yaak — official GitHub release bodies, fetched 2026-09-06. Decoded as
        // JSON + Markdown through the existing structured path; the stable
        // recipe excludes beta and draft releases.
        //
        // `per_page=40` with `maxEntries: 20` is the registry's house shape
        // (CotEditor's and Cline's channel-split pairs are identical), and 20 is a
        // CEILING, not a target: this repo's newest 40 releases are mostly beta, so
        // the stable rail renders fewer than 20 entries while the beta rail fills its
        // 20 (History has the counts).
        //
        // `includesPromotedStable` is deliberately absent (false) on the beta
        // recipe, and this is not the same decision UTM's pair makes. Yaak's beta
        // rule cannot resolve a stable artifact — `installAssetPattern` requires
        // `-beta.<N>` in the asset name and the channel proof requires it in the
        // download path — so a promoted-stable entry would describe a build this
        // channel never offers.
        // `ActiveAppsIntegrationTests.releaseHistoriesRespectEveryRegisteredChannel`
        // pins the value as a literal.
        ChangelogRecipe(
            bundleID: "app.yaak.desktop",
            source: URL(string: "https://api.github.com/repos/mountain-loop/yaak/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),

        ChangelogRecipe(
            bundleID: "app.yaak.desktop",
            source: URL(string: "https://api.github.com/repos/mountain-loop/yaak/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            structuredFormat: .gitHubReleases),
        ],
        githubRules: [
        // Yaak — real stable and beta DMGs retain their full tag version in
        // both plist version fields; same app.yaak.desktop and Team 7PU3P6ELJ8.
        // Pin arm64 DMGs, excluding updater
        // tarballs, detached signatures, Intel and Windows/Linux packages.
        GitHubReleaseRule(
            bundleID: "app.yaak.desktop",
            owner: "mountain-loop", repo: "yaak",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^Yaak_[0-9.]+_aarch64\.dmg$"#,
            installerKind: .dmg),
        GitHubReleaseRule(
            bundleID: "app.yaak.desktop",
            owner: "mountain-loop", repo: "yaak",
            usePrereleases: true,
            // Keep the default 20-row window above the measured 6-row floor (see History).
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+)$"#,
            installAssetPattern: #"^Yaak_[0-9.]+-beta\.[0-9]+_aarch64\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),
        ],
        githubChannelProofs: [
        ChannelProofKey("app.yaak.desktop", .beta):
            .artifact(#"/download/v[0-9.]+-beta\.[0-9]+/"#),
        ])
}
