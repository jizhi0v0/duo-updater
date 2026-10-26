import Foundation

enum com_nabocorp_witsy {
    static let set = AppRecipeSet(
        family: "com-nabocorp-witsy",
        changelogs: [
        // The release bodies are a bare `[CHANGELOG.md](CHANGELOG.md)` link (every
        // release from v3.2.1 to v3.5.2), so the GitHub notes say nothing. The
        // repo's CHANGELOG.md is Keep a Changelog: `## [3.5.2] - 2026-03-04`, then
        // `### Added` / `### Changed` / `### Fixed` / `### Removed`, each a `- `
        // list, and a section with nothing in it reads `- N/A`.
        //
        //  * The date must be `yyyy-MM-dd`, which skips the top `## [3.6.0] - WIP`
        //    section for a release that does not exist yet.
        //  * `- N/A` is not an item, and a heading whose only item is `- N/A` is
        //    not a heading.
        //  * `## [2.12.5 / 2.12.6]` has two versions in one bracket and is
        //    skipped; the file starts at 2.10.0, older releases have no notes.
        ChangelogRecipe(
            bundleID: "com.nabocorp.witsy",
            source: URL(string: "https://raw.githubusercontent.com/Kochava-Studios/witsy/main/CHANGELOG.md")!,
            entryPattern:
                #"(?:^|\n)##\s+\[(?<version>[0-9]+(?:\.[0-9]+)+)\]\s*-\s*(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})[ \t]*\n(?<body>.*?)(?=\n##\s|\z)"#,
            itemPatterns: [#"\n-\s+(?!N/A[ \t]*(?:\n|\z))(?<item>.+?)(?=\n-\s|\n###\s|\n##\s|\n\[|\z)"#],
            markdownSource: true,
            headingPattern: #"\n###\s+(?<heading>[^\n]+)(?=\n+-\s+(?!N/A[ \t]*(?:\n|\z)))"#),
        ],
        githubRules: [
        // Witsy — Electron AI desktop assistant (Kochava-Studios/witsy; the repo
        // was nbonamy/witsy until 2026-04, and that name is now an unrelated
        // empty repository, so GitHub no longer redirects it).
        //
        // Its own updater is Electron's `autoUpdater` (Squirrel.Mac) on
        // update.electronjs.org. Every released build, 3.5.2 included, asks
        // `update.electronjs.org/nbonamy/witsy/darwin-<arch>/<version>`, which
        // answered 404 "No updates found" on 2026-10-26 (the same query on
        // Kochava-Studios answered 3.5.2), so those copies no longer update
        // themselves. The source on `main` already names
        // Kochava-Studios; a release built from it downloads the next zip in the
        // background (no prompt) and hands it to Squirrel's ShipIt. No helper,
        // login item or launch agent ships in the bundle; the four
        // `Witsy Helper*.app` are Electron's child-process hosts.
        //
        // Tags read `v3.5.2`; the bundle says 3.5.2 (build 1445).
        // `Witsy-<v>-darwin-arm64.dmg` is com.nabocorp.witsy, Team TP8BYQ64C4,
        // notarized; same id and Team back to v1.4.2. The `-darwin-x64` build is
        // the same app (same Info.plist, same `app.asar` but for three native
        // modules); there is no universal build. Prereleases (`v3.4.1`,
        // `v3.0.1`, …) carry plain version tags and stable-shaped versions;
        // /releases/latest skips them.
        GitHubReleaseRule(
            bundleID: "com.nabocorp.witsy",
            owner: "Kochava-Studios", repo: "witsy",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Witsy-[0-9]+(?:\.[0-9]+)+-darwin-arm64\.dmg$"#,
            installerKind: .dmg),
        // A copy of `v2.0.0-beta1` or `v2.0.0-rc1` (2025-03) reports
        // `2.0.0-beta1` / `2.0.0-rc1`, which `ReleaseChannel.detect` reads as
        // non-stable, and the stable rule refuses it. No beta has shipped since
        // (2.0.0 was stable a week later), so such a copy moves to the newest
        // stable release: same tags as the stable rule. Detection-only: a
        // non-stable install needs a channel proof, and only the installed
        // version tells the tracks apart.
        GitHubReleaseRule(
            bundleID: "com.nabocorp.witsy",
            owner: "Kochava-Studios", repo: "witsy",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            channel: .beta),
        ])
}
