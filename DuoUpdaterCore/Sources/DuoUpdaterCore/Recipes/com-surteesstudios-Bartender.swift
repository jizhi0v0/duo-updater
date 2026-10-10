import Foundation

enum com_surteesstudios_Bartender {
    static let set = AppRecipeSet(
        family: "com-surteesstudios-Bartender",
        probes: [
        // History: docs/app-audits/com-surteesstudios-Bartender.md#历史与实测
        // Bartender — Sparkle appcast (ascending, oldest-first). Version lives in
        // sparkle:shortVersionString on each <item>. selectHighest because the feed
        // lists items oldest-first.
        //
        // DEAD FOR DETECTION, kept as a sweep anchor. The app's bundle declares
        // `SUFeedURL = https://www.macbartender.com/B2/updates/AppcastB6.xml`, the
        // same address as below (read from a real bundle on 2026-08-31; History
        // has the hedge that settled), so `SparkleAppcastSource` answers first and
        // this recipe never runs in production. It stays because `duo verify`
        // sweeps the recipe registries and nothing sweeps Sparkle feeds — deleting
        // the row would leave the endpoint unwatched. Do not "fix" this by
        // re-pointing it.
        VendorProbeRecipe(
            bundleID: "com.surteesstudios.Bartender",
            url: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+\.[0-9]+\.[0-9]+)</sparkle:shortVersionString>"#,
            // The human release-notes page (every Bartender 6 build, newest
            // first), not the appcast: this URL is what the pane embeds when no
            // recipe produces notes. It does not match the changelog recipe's
            // `feedPagePattern` on purpose, so it is only ever embedded.
            changelogURL: URL(string: "https://www.macbartender.com/Bartender6/release_notes/")!,
            selectHighest: true,
            // `bodyPatternLast`, not `bodyPattern`: this appcast is ASCENDING, so the
            // first enclosure is 6.0.0 and the newest is the final one — the same
            // reason `selectHighest` is set for the version. Taking the first match
            // would install a two-year-old build over a current one.
            //
            // (Note the older entries are served from macbartender.com and the
            // recent ones from downloads.macbartender.com — the pattern accepts
            // either host.)
            install: VendorInstallSpec(
                urlSource: .bodyPatternLast(
                    #"<enclosure[^>]*url="(https://[^"]*macbartender\.com/[^"]+\.zip)""#),
                kind: .zip)),
        ],
        changelogs: [
        // Bartender — the appcast inlines no notes; each item links one page of
        // its own, `…/B2/updates/<6-6-2>/rnotes.html` (dots as dashes). Older
        // items link `macbartender.com`, newer ones `downloads.macbartender.com`,
        // and the feed address itself redirects to the latter. So the page is the
        // one the Sparkle check resolved (`feedPagePattern`); `source` is the
        // appcast, read only by `duo verify` to resolve a page of its own.
        // Several older items' pages are gone (404), which this cannot fix: those
        // fall back to the embedded page.
        //
        //   * The page names its version in `<h2>Bartender 6.6.2</h2>` (the 6.0.0
        //     page says just "Bartender 6"); everything up to `</table>` is the
        //     body.
        //   * Changes are `<li>` under `<h3>`/`<h4>` category headings ("Fixes",
        //     "New", and on some pages a product heading like "Top Shelf"); the
        //     intro and the closing "reach out to us" are `<p>` and stay out
        //     whenever there is a list.
        ChangelogRecipe(
            bundleID: "com.surteesstudios.Bartender",
            source: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            entryPattern:
                #"<h2[^>]*>\s*Bartender\s+(?<version>[0-9]+(?:\.[0-9]+){0,3})\s*</h2>(?<body>.*?)</table>"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<p[^>]*>(?<item>.*?)</p>"#,
            ],
            maxEntries: 1,
            headingPattern: #"<h[34][^>]*>(?<heading>.*?)</h[34]>"#,
            feedPagePattern:
                #"^https://(?:www\.|downloads\.)?macbartender\.com/B2/updates/[0-9]+(?:-[0-9]+){1,3}/rnotes\.html$"#),
        ])
}
