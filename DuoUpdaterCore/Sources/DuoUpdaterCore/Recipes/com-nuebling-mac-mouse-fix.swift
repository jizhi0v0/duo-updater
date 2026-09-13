import Foundation

enum com_nuebling_mac_mouse_fix {
    static let set = AppRecipeSet(
        family: "com-nuebling-mac-mouse-fix",
        changelogs: [
        // Mac Mouse Fix — both appcasts (stable and `appcast-pre.xml`) inline no
        // notes; every item links one pandoc-rendered page per language,
        // `…/update-notes-html/<version>/<lang>.html`, 12 languages and no `en`.
        // So the page is whatever the feed resolved for this reader
        // (`feedPagePattern`, #557); `source` is the stable appcast, read only by
        // `duo verify` to resolve a page of its own.
        //
        // Measured 2026-09-13 against both live feeds: all 360 links match the
        // page pattern. Of the 63 linked pages fetched (every version's `de`,
        // plus all 12 languages of 3.0.8, 3.1.0 Beta 1 and 2.0.0), all 63 extract
        // one entry whose `<title>` equals that item's
        // `sparkle:shortVersionString` (`3.1.0 Beta 1` included). The 31 unlinked
        // `en` pages were fetched too and all extract with no notice text.
        // Checked independently in Python.
        //
        //   * A translated page opens with a "translated by AI" notice
        //     (`<p><strong>ℹ️ …`) ending at the first `<hr />`, and the body
        //     starts after it. Keyed on the notice, not on the first `<hr />`:
        //     `en.html` is published but has no notice (and no feed links it
        //     today), and its first `<hr />` is the one before the "previous
        //     release" footer. Skipping to it left 16 of the 31 English pages
        //     with only that footer as their notes.
        //   * Sub-bullets are nested `<ul>`; the item pattern stops at the next
        //     `<li>`/`<ul>`, so a parent and its first child stay two lines
        //     rather than one merged line. 60 of the 63 pages use lists.
        //   * The other three (2.1.0, 3.0.0 Beta 2 and Beta 3) are prose only,
        //     and fall through to `<p>`.
        ChangelogRecipe(
            bundleID: "com.nuebling.mac-mouse-fix",
            source: URL(string: "https://raw.githubusercontent.com/noah-nuebling/mac-mouse-fix/update-feed/appcast.xml")!,
            entryPattern:
                #"<title>(?<version>[^<]+)</title>.*?<body>\s*(?:<p><strong>\x{2139}.*?<hr\s*/?>)?(?<body>.*)</body>"#,
            itemPatterns: [
                #"<li>(?<item>.*?)(?=<li>|</li>|<ul>|<ol>)"#,
                #"<p>(?<item>.*?)</p>"#,
            ],
            maxEntries: 1,
            headingPattern: #"<h[2-4][^>]*>(?<heading>.*?)</h[2-4]>"#,
            feedPagePattern:
                #"^https://raw\.githack\.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/[^/?#]+/[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*\.html$"#),
        ],
        bindingProofs: [
        // Mac Mouse Fix: same feed-swap shape as IINA, and the same reasoning —
        // stable and beta share host, path prefix and repo, differing only in
        // the trailing filename (`appcast.xml` vs `appcast-pre.xml`), which is
        // exactly what the anchor targets.
        ChannelProofKey("com.nuebling.mac-mouse-fix", .beta):
            .recipeAnchor(#"appcast-pre\.xml"#, in: ["feedOverride"]),
        ])
}
