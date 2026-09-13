import Foundation

enum app_yaak_desktop {
    static let set = AppRecipeSet(
        family: "app-yaak-desktop",
        changelogs: [
        // Yaak — official GitHub release bodies, fetched 2026-09-06. Decoded as
        // JSON + Markdown through the existing structured path; the stable
        // recipe excludes beta and draft releases.
        //
        // `per_page=40` with `maxEntries: 20` is the registry's house shape (Zed
        // and UTM's channel-split pairs are identical), and 20 is a CEILING, not
        // a target: measured 2026-09-06, the newest 40 releases hold 12 stable
        // and 28 beta, so the stable rail renders 12 entries and the beta rail
        // fills its 20. Raising the page to reach 20 stable would mean fetching
        // ~72 releases on every changelog read, which no other entry here does.
        //
        // `includesPromotedStable` is deliberately absent (false) on the beta
        // recipe, and this is not the same decision UTM's pair makes. Yaak's beta
        // rule cannot resolve a stable artifact — `installAssetPattern` requires
        // `-beta.<N>` in the asset name and the channel proof requires it in the
        // download path — so a promoted-stable entry would describe a build this
        // channel never offers. `yaakBetaNotesDoNotPromiseAStableWeCannotInstall`
        // pins the value against the shape of the rule.
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
        // Verified notarized 2026-09-06. Pin arm64 DMGs, excluding updater
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
            // Latest 100 releases: 72 beta tags, worst gap 5 (2026-09-06).
            // Keep the default 20-row window above the measured 6-row floor.
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
