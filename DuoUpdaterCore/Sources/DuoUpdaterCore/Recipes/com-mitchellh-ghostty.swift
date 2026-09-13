import Foundation

enum com_mitchellh_ghostty {
    static let set = AppRecipeSet(
        family: "com-mitchellh-ghostty",
        changelogs: [
        // Ghostty — two-stage, same shape as VLC. `source` is the newest-first
        // release-notes index; `indexLinkPattern` follows its first per-version link
        // (currently /docs/install/release-notes/1-3-1) to that version's page. This
        // replaces the old version-pinned URL, so a new release is picked up with no
        // re-run of the fragile-recipe skill. The detail page is unchanged in shape:
        // version and date live in the <meta name="description"> tag near the top:
        //   content="Release notes for Ghostty 1.3.1, released on March 13, 2026."
        // Items are <li class="...weightRegular..."> in the Full Changelog section,
        // which follows the Highlights prose. That heading's generated id changed
        // from `full-changelog-2` to `full-changelog` in August 2026; accept the
        // stable slug plus an optional numeric suffix rather than pinning either
        // build artifact.
        ChangelogRecipe(
            bundleID: "com.mitchellh.ghostty",
            source: URL(string: "https://ghostty.org/docs/install/release-notes")!,
            entryPattern:
                #"<meta name="description" content="Release notes for Ghostty (?<version>[^,]+), released on (?<date>[^.]+)\."[^>]*>"#
                + #".*?"#
                + #"id="full-changelog(?:-\d+)?">.*?</div></div>\s*(?<body>.*?)</main>"#,
            itemPatterns: [
                #"<li class="[^"]*weightRegular[^"]*">(?<item>.*?)</li>"#,
            ],
            indexLinkPattern: #"href="(?<link>/docs/install/release-notes/\d[^"]*)""#),
        ],
        changelogPages: [
        // Ghostty — auto_updates cask, no Sparkle feed; official release notes.
        "com.mitchellh.ghostty": URL(string: "https://ghostty.org/docs/install/release-notes")!,
        ])
}
