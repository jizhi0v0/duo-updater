import Foundation

enum org_musicbrainz_Picard {
    static let set = AppRecipeSet(
        family: "org-musicbrainz-Picard",
        changelogs: [
        // History: docs/app-audits/org-musicbrainz-Picard.md#历史与实测
        // The vendor's "What's New" page, rendered from the repo's NEWS.md: one
        // `<h3 id="release-…">Version <strong>X</strong> <span>date</span></h3>`
        // per release, newest first, then `<h4>` sections (Bugfixes,
        // Improvements, New Features, Tasks) each over a `<ul>`. The body runs to
        // the next `<h3 ` or the end of `<div id="log">`. Pre-releases
        // (`3.0.0rc4`, `2.9.0b1`) are on the same page as their own entries; they
        // stay, because a .0 release lists only the fixes since its last rc.
        ChangelogRecipe(
            bundleID: "org.musicbrainz.Picard",
            source: URL(string: "https://picard.musicbrainz.org/changelog/")!,
            entryPattern:
                #"<h3 id="release-[^"]*">\s*Version\s*<strong>(?<version>[^<]+)</strong>\s*"#
                + #"(?:<span>(?<date>[^<]*)</span>\s*)?</h3>(?<body>.*?)(?=<h3 |</div>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            headingPattern: #"<h4[^>]*>(?<heading>[^<]*)</h4>"#),
        ],
        githubRules: [
        // MusicBrainz Picard (metabrainz/picard, Team 8D89TSJ88H, notarized).
        // No SUFeedURL: the app's own checker reads
        // picard.musicbrainz.org/api/v2/releases and only opens the download page.
        // Every release since 2.0.0 is tagged `release-<version>` and pre-releases
        // carry GitHub's `prerelease` bit; the tag is the marketing string, equal
        // to both Info.plist version fields (`3.0.2`, two-part `3.0` for a .0
        // release). Anchored, so `release-2.6.0b3` — a beta left without the
        // bit — never reads as stable.
        // The release assets are the same files as the vendor's
        // data.musicbrainz.org mirror (same SHA-256), one dmg per arch, named
        // `MusicBrainz-Picard-<version>-macOS-<floor>-<arch>.dmg`; the floor is
        // left open because it moved from 11.0 to 13.0 during the 3.0 betas.
        GitHubReleaseRule(
            bundleID: "org.musicbrainz.Picard",
            owner: "metabrainz", repo: "picard",
            versionPattern: #"^release-([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^MusicBrainz-Picard-[0-9][0-9A-Za-z.]*-macOS-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
