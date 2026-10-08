import Foundation

enum com_colliderli_iina {
    static let set = AppRecipeSet(
        family: "com-colliderli-iina",
        changelogs: [
        // History: docs/app-audits/com-colliderli-iina.md#历史与实测
        // IINA — neither appcast (`appcast.xml`, `appcast-beta.xml`; `IINAChannel`
        // picks one) inlines notes. Every item links one page of its own under
        // `https://www.iina.io/release-note/`, named after the version, and for a
        // re-spun build after the build too (`1.4.2-build164.html`), which a
        // `{version}` template cannot produce. So the page is the one the feed
        // resolved for this copy (`feedPagePattern`), which follows the channel
        // with no logic of its own. `source` is the stable appcast, read only by
        // `duo verify`.
        //
        //   * One version per page: `<h2>IINA <version></h2>` (the earliest pages
        //     drop the "IINA "), then an optional intro `<p>`, then an `<h3>` per
        //     section, each over a `<ul class="fl">` of `<li class="n|f|e|u|p">`.
        //     Older pages append previous releases under further `<h2>`s, so the
        //     body ends at the next `<h2>`.
        //   * The version is the `<h2>`'s, suffix included (`1.5.0-beta2`), which
        //     is the feed's `shortVersionString`. Trailing words ("Build 68") are
        //     not part of it.
        //   * Sub-bullets are nested `<ul>`; the item pattern stops at the next
        //     `<li>`/`<ul>`, so a parent and its first child stay two lines.
        //   * `<p>` and `<li>` are one pattern, in document order, so the intro
        //     leads the entry. A trailing `<p><strong>Deprecation Notice</strong><br>`
        //     (`<b>` on older pages) is a section of its own: its bold lead is
        //     the heading and the item pattern skips it, so the heading text is
        //     not repeated in the note. The heading's match starts at the `<p>`
        //     and the note's just after it: blocks are ordered by match position,
        //     and two at the same position have no defined order.
        ChangelogRecipe(
            bundleID: "com.colliderli.iina",
            source: URL(string: "https://www.iina.io/appcast.xml")!,
            entryPattern:
                #"<h2[^>]*>\s*(?:IINA\s+)?(?<version>[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z.]+)?)[^<]*</h2>"#
                + #"(?<body>.*?)(?=<h2[\s>]|</body>)"#,
            itemPatterns: [
                #"(?:<li(?:\s[^>]*)?>"#
                    + #"|<p>(?!\s*<(?:b|strong)>[^<]*</(?:b|strong)>\s*<br)"#
                    + #"|(?<=<p>)\s*<(?:b|strong)>[^<]*</(?:b|strong)>\s*<br\s*/?>)"#
                    + #"(?<item>.*?)(?=<li[\s>]|</li>|<ul[\s>]|<ol[\s>]|</p>)"#,
            ],
            maxEntries: 1,
            headingPattern:
                #"(?:<h3[^>]*>|<p>\s*<(?:b|strong)>)(?<heading>[^<]*?)(?:</h3>|</(?:b|strong)>\s*<br\s*/?>)"#,
            feedPagePattern: #"^https://www\.iina\.io/release-note/[^/?#]+\.html$"#),
        ],
        bindingProofs: [
        ChannelProofKey("com.colliderli.iina", .beta):
            .recipeAnchor(#"appcast-beta\.xml"#, in: ["feedOverride"]),
        ])
}
