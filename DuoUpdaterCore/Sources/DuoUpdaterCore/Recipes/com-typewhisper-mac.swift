import Foundation

enum com_typewhisper_mac {
    static let set = AppRecipeSet(
        family: "com-typewhisper-mac",
        changelogs: [
        // TypeWhisper — no notes in the appcast either. The official changelog
        // page is the vendor's own, and it interleaves **macOS and Windows**
        // releases in one list (203 mac cards, 167 Windows ones), so the entry
        // pattern is anchored on the platform badge that precedes the version
        // heading. Getting that wrong shows Windows notes under a Mac version.
        //
        //   …</svg>macOS</span><h3 class="font-display …">v1.7.0-daily.20260826</h3>
        //   …<p class="mt-1 text-xs text-muted-foreground">August 26, 2026</p>
        //   <div class="prose …"><h2>Bug Fixes</h2><ul><li>…</li></ul></div>
        //
        // The gap between the heading and the date is a TEMPERED lazy scan
        // (`(?:(?!>macOS</span><h3|>Windows</span><h3).)*?`), not a plain `.*?`:
        // a handful of old cards carry no prose block, and a plain lazy scan ran
        // past them into the NEXT card and filed its notes under the wrong
        // version — two entries did exactly that (0.6.1, 0.5.1) before this was
        // tempered. With it: 194 entries, none spanning a card boundary.
        //
        // Every train lands in one list, so a stable install sees the daily
        // entries above its own release. That is the vendor's page as published;
        // each entry is labelled with its version, and the daily notes are
        // cumulative (successive dailies repeat the same bullets), which is why
        // `maxEntries` is cut to 20 — 40 would be four weeks of near-duplicates.
        ChangelogRecipe(
            bundleID: "com.typewhisper.mac",
            source: URL(string: "https://www.typewhisper.com/en/changelog/")!,
            entryPattern:
                #">macOS</span><h3[^>]*>v?(?<version>[^<]+)</h3>"#
                + #"(?:(?!>macOS</span><h3|>Windows</span><h3).)*?"#
                + #"<p class="mt-1 text-xs text-muted-foreground">(?<date>[^<]*)</p>"#
                + #"<div class="prose[^"]*"[^>]*>(?<body>.*?)</div>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#, #"<p[^>]*>(?<item>.*?)</p>"#],
            maxEntries: 20),
        ])
}
