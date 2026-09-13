import Foundation

enum com_tinyapp_tableplus {
    static let set = AppRecipeSet(
        family: "com-tinyapp-tableplus",
        changelogs: [
        // TablePlus — Jekyll blog post at /osx/changelog. Each version block:
        //   <h3 id="…">Version 7.1.0 (710) - Liquid Glass</h3>
        //   <h4 id="…">Release date: 26 May 2026.</h4>
        //   <h5>…SHA / Download…</h5>
        //   <ul><li>…</li>…</ul>
        // `title` captures the release name after the build number (e.g. "Liquid Glass").
        ChangelogRecipe(
            bundleID: "com.tinyapp.tableplus",
            source: URL(string: "https://tableplus.com/osx/changelog")!,
            entryPattern:
                #"<h3[^>]*>Version (?<version>\d+\.\d+(?:\.\d+)?) \(\d+\)(?:\s*-\s*(?<title>[^<]+))?</h3>\s*"#
                + #"<h4[^>]*>Release date:\s*(?<date>[^.<]+)[^<]*</h4>"#
                + #".*?"#
                + #"<ul>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li>\s*(?<item>.*?)\s*</li>"#]),
        ],
        bindingProofs: [
        // TablePlus is the sharpest case in the population and the only
        // header-keyed one. Stable and beta share ONE feed URL; the server decides
        // which builds to return from a request header, and the VALUE is
        // load-bearing — the app sends the literal `true` and the server treats
        // `1`/`yes` as stable (`TablePlusChannel`). So the anchor covers the value,
        // not just the field name, which is why `ResolvedChannel.anchorLines`
        // renders a header as one `key: value` line instead of two.
        //
        // Right-anchored, because without the `$` it also accepted `trueX` — a
        // value this comment's own model of the server says would be treated as
        // stable. Case is NOT pinned: the shared matcher runs case-insensitively
        // for every proof, so this asserts the token and its boundary, not the
        // letter case.
        ChannelProofKey("com.tinyapp.tableplus", .beta):
            .recipeAnchor(#"X-Tiny-Beta-Update:\s*true\s*$"#, in: ["feedHTTPHeaders"]),
        ])
}
