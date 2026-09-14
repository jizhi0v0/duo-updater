import Foundation

enum com_nuebling_mac_mouse_fix {
    static let set = AppRecipeSet(
        family: "com-nuebling-mac-mouse-fix",
        changelogs: [
        // History: docs/app-audits/com-nuebling-mac-mouse-fix.md#历史与实测
        // Mac Mouse Fix — both appcasts (stable and `appcast-pre.xml`) inline no
        // notes; every item links one pandoc-rendered page per language,
        // `…/update-notes-html/<version>/<lang>.html`, 12 languages and no `en`.
        // So the page is whatever the feed resolved for this reader
        // (`feedPagePattern`, #557); `source` is the stable appcast, read only by
        // `duo verify` to resolve a page of its own.
        //
        //   * A translated page opens with a "translated by AI" notice
        //     (`<p><strong>ℹ️ …`) ending at the first `<hr />`, and the body
        //     starts after it. Keyed on the notice, not on the first `<hr />`:
        //     `en.html` is published but has no notice (and no feed links it
        //     today), and its first `<hr />` is the one before the "previous
        //     release" footer. Skipping to it can leave an English page with
        //     only that footer as its notes.
        //   * Sub-bullets are nested `<ul>`; the item pattern stops at the next
        //     `<li>`/`<ul>`, so a parent and its first child stay two lines
        //     rather than one merged line.
        //   * A page with no list is prose only, and falls through to `<p>`.
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
