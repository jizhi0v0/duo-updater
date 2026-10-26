import Foundation

enum com_paulthetall_portingkit {
    static let set = AppRecipeSet(
        family: "com-paulthetall-portingkit",
        changelogs: [
        // Porting Kit — the release body is only the tag (`v6.7.0`); the notes
        // live in the `changelog.html` asset every release since 5.0.4 carries,
        // the whole history newest first, one block per version:
        // `Porting Kit 6.7.0 (19/11/2025):` then a `<ul>` of `<li>` lines.
        // `/releases/latest/download/` follows the stable release, so the top
        // entry is the stable version; the versions between two stable
        // releases (6.6.x) were published only on the experimental repo and
        // stay listed here as the vendor wrote them. The date is day/month/year,
        // kept verbatim. Two blocks (a repeated 6.1.2, 4.2.30) have an empty
        // `<ul>` and yield no entry.
        ChangelogRecipe(
            bundleID: "com.paulthetall.portingkit",
            source: URL(string: "https://github.com/vitor251093/porting-kit-releases/releases/latest/download/changelog.html")!,
            entryPattern:
                #"Porting Kit (?<version>[0-9]+(?:\.[0-9]+)+) \((?<date>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4})\):\s*"#
                + #"<ul>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ],
        githubRules: [
        // Porting Kit — installs and manages Wine wrappers for Windows games
        // and apps (Electron). Its own updater is electron-updater: the main
        // process points it at this repo (provider github) unless the
        // `experimentalFeatures` preference is on, in which case it keeps the
        // bundle's `app-update.yml`, which names `porting-kit-releases-dev`
        // (see "Other tracks" in the audit). By default it downloads on its
        // own and swaps the bundle on quit (ShipIt). The four `Porting Kit
        // Helper*.app` under Frameworks are Electron's GPU / renderer / plugin
        // processes; there is no login item or launchd job.
        //
        // Tags read `v6.7.0`; the bundle says 6.7.0. The vendor has spelled
        // the asset both `Porting-Kit-<v>` and `Porting.Kit-<v>` (GitHub's
        // rendering of the space in "Porting Kit"), so the pattern takes
        // either. Only 6.7.0 ships an arm64 dmg on this repo; the dmg with no
        // arch word is x86_64-only, not universal, so it is left out rather
        // than installed over a native copy. Every release back to v4.1.6 is
        // com.paulthetall.portingkit, Team 45WEPZ3433, notarized.
        GitHubReleaseRule(
            bundleID: "com.paulthetall.portingkit",
            owner: "vitor251093", repo: "porting-kit-releases",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Porting[.-]Kit-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
