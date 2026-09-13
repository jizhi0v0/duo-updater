import Foundation

enum com_eusoft_eudic {
    static let set = AppRecipeSet(
        family: "com-eusoft-eudic",
        changelogs: [
        // Eudic (欧路词典) — `source` is its Sparkle 1 appcast, not a web page,
        // because the appcast IS the changelog: the vendor keeps the app's entire
        // history inside the NEWEST item's `<description>` CDATA — 10,253
        // characters, one `<h2>` for the current release and 34 `<h3>` sections
        // running back to 2.5.0 (measured 2026-09-01). Every older `<item>` in the
        // feed is a 2010-era stub. So without a recipe the row rendered sixteen
        // years of notes under the heading "26.9.0".
        //
        // It cannot reach the appcast's own structured path either:
        // `AppcastHTMLChangelogParser.isStructured` requires at least one `<li>`
        // and this body has ZERO — 29 `<p>` and 154 `<br>` instead — so
        // `SparkleAppcastSource` leaves `structuredChangelog` nil and the pane fell
        // to raw-HTML rendering of the whole blob.
        //
        // The headings are not a clean version list, which is what rules out
        // teaching the generic parser this shape:
        //   * 7 of the 34 are the literal label "更新内容", not a version;
        //   * several carry a suffix — "3.6.0 改进", and "2.5.2改进" with no space.
        // So the entry pattern keys on a heading that CONTAINS a dotted number
        // rather than on the heading tag, and `body` runs to the next such heading
        // — stepping over the label rows, which is exactly why the lookahead
        // demands a digit. The CDATA close is the other terminator, so the last
        // section cannot swallow the 2010 stubs that follow it.
        //
        // Items are `- text<br>` lines inside a `<p>`, and the leading dash is
        // consumed because the renderer draws its own bullet. The capture is
        // `.*?` to the next `<br>`/`</p>` rather than `[^<]+`: the pre-3.7 sections
        // wrap whole lines in `<b>`, and a no-tag capture silently dropped every
        // one of them. Yields 29 entries, validated against the live feed.
        //
        // No dates: the per-version sections carry none (the feed's single
        // `<pubDate>` describes only the newest release), so every entry renders
        // date-less rather than borrowing a wrong one.
        ChangelogRecipe(
            bundleID: "com.eusoft.eudic",
            source: URL(string: "https://static.eudic.net/pkg/eudic_mac.xml")!,
            entryPattern:
                #"<h[23]>[^<]*?(?<version>\d+(?:\.\d+)+)[^<]*</h[23]>"#
                + #"(?<body>.*?)(?=<h[23]>[^<]*\d|\]\]></description>|\z)"#,
            itemPatterns: [
                #"(?:<p[^>]*>|<br\s*/?>)\s*(?:[-–]\s*)?(?<item>.*?)\s*(?=<br\s*/?>|</p>)"#
            ],
            minItemLength: 2),
        ])
}
