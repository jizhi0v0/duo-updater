import Foundation

enum com_aone_keka {
    static let set = AppRecipeSet(
        family: "com-aone-keka",
        changelogs: [
        // History: docs/app-audits/com-aone-keka.md#历史与实测
        // Keka — GitHub release bodies, not the appcast's notes link.
        //
        // Detection is the generic Sparkle route (`SUFeedURL` = `u.keka.io`); the
        // feed inlines no notes and only links `changelog.php` (the newest version
        // alone) and `changelog.keka.io` (the full history, one flat `<ul>` per
        // version). Neither page has sections. The GitHub release body for the
        // same version carries the same change lines under the vendor's own
        // `## Fixes` / `## Formats` / `## Translations` / `## Features` headings,
        // which `GitHubMarkdownParser` keeps as heading blocks.
        //
        // What the decoder drops without a recipe field: the two `👉` promo lines
        // and the one-line prose summary at the top of every body are not bullets,
        // so the strict pass never reads them.
        //
        // `tagPattern`: the dev / beta / rc builds are GitHub prereleases on the
        // same list (`v1.5.2-dev.r5614`, `dev-test-builds`, …), which the
        // decoder's stable filter already skips. One older dev release,
        // `v1.2.0-dev.3742`, is published with `prerelease: false`, so the
        // flag alone is not a guarantee; the `$`-anchored pattern accepts only a
        // plain dotted version.
        //
        // A hot-fix body restates the previous release under
        // `# Changes in version X.Y.Z` (1.6.7 carries 1.6.6's notes, 1.6.3
        // carries 1.6.2's). `GitHubMarkdownParser` drops a section like that when
        // X is older than the release, so the hot-fix entry is its own fix alone;
        // the restated release keeps its own entry.
        ChangelogRecipe(
            bundleID: "com.aone.keka",
            source: URL(string: "https://api.github.com/repos/aonez/Keka/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+){1,3})$"#),
        ])
}
