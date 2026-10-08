import Foundation

enum com_obsproject_obs_studio {
    static let set = AppRecipeSet(
        family: "com-obsproject-obs-studio",
        changelogs: [
        // History: docs/app-audits/com-obsproject-obs-studio.md#历史与实测
        // OBS Studio — the appcast inlines no notes. The newest item of each
        // channel links one pandoc-rendered fragment per channel,
        // `…/osx_update/notes_stable.html` and `…/notes_beta.html`, so the page
        // is whichever the feed resolved for this copy (`feedPagePattern`) and
        // follows the channel with no logic of its own. `source` is the arm64
        // appcast, read only by `duo verify`.
        //
        //   * A page is the whole minor series, newest first: one `<h1>` naming
        //     the newest build ("OBS Studio 32.2.2", "OBS Studio 33.0.0 Beta 6"),
        //     then an `<h2>` + `<ul>` per hotfix, beta and category. One entry,
        //     with the `<h2>`s kept as headings.
        //   * The version is the numeric part of the `<h1>`, because that is what
        //     the feed's `shortVersionString` says: beta builds drop the suffix
        //     (33.0.0-beta6 is `33.0.0`).
        //   * Sub-bullets are nested `<ul>`; the item pattern stops at the next
        //     `<li>`/`<ul>`, so a parent and its first child stay two lines.
        //   * A page can open with `<p>Important: …</p>` notices under the `<h1>`
        //     (a dropped macOS version, a driver floor). One pattern takes `<p>`
        //     and `<li>` together, in document order, so they lead the entry; as
        //     a second pattern they would never run, since the first one that
        //     yields anything wins.
        //   * The page is a fragment — no `<html>`/`<body>` — so the body runs to
        //     the end of the text.
        ChangelogRecipe(
            bundleID: "com.obsproject.obs-studio",
            source: URL(string: "https://obsproject.com/osx_update/updates_arm64_v2.xml")!,
            entryPattern:
                #"<h1[^>]*>\s*OBS Studio (?<version>[0-9]+(?:\.[0-9]+){1,3})[^<]*</h1>(?<body>.*)"#,
            itemPatterns: [
                #"<(?:li|p)>(?<item>.*?)(?=<li>|</li>|<ul>|<ol>|</p>)"#,
            ],
            maxEntries: 1,
            headingPattern: #"<h2[^>]*>(?<heading>.*?)</h2>"#,
            feedPagePattern:
                #"^https://obsproject\.com/osx_update/notes_(?:stable|beta)\.html$"#),
        ])
}
