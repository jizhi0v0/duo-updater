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
        //
        // `installedVersionPattern` pins it to Bartender 6. Bartender 7 keeps the
        // same bundle id, Team and EdDSA key, but it is a separate paid upgrade
        // with its own feed (`…/Bartender7/updates/AppcastB7.xml`, declared in its
        // bundle), and this feed tops out at 6.x. Unpinned, a 7.x install whose
        // Sparkle check failed would be answered here with "latest 6.6.2" and a
        // Bartender 6 zip and release-notes page. There is deliberately no
        // Bartender 7 row: its declared feed answers it, and offering 7 to a 6
        // install would sell an upgrade the user has not bought.
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
                kind: .zip),
            installedVersionPattern: #"^6\."#),
        ],
        changelogs: [
        // Bartender 6 — the appcast inlines no notes; each item links one page of
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
        //
        // The two recipes share a bundle id, so the version windows (`<7` here,
        // `7+` below) are what pick one. Without them the group's first recipe
        // would be chosen for a 7.x install too, and its `feedPagePattern` would
        // refuse the 7.x page.
        ChangelogRecipe(
            bundleID: "com.surteesstudios.Bartender",
            source: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            entryPattern: entryPattern,
            itemPatterns: itemPatterns,
            maxEntries: 1,
            headingPattern: headingPattern,
            belowAppVersion: "7",
            feedPagePattern:
                #"^https://(?:www\.|downloads\.)?macbartender\.com/B2/updates/[0-9]+(?:-[0-9]+){1,3}/rnotes\.html$"#),

        // Bartender 7 — same shape, its own appcast
        // (`downloads.macbartender.com/Bartender7/updates/AppcastB7.xml`, which
        // the 7.x bundle declares as `SUFeedURL`) and its own pages,
        // `…/Bartender7/updates/<7-0-5>/rnotes.html`. The markup is the 6.x
        // pages' markup, so the patterns are shared.
        //
        // Some items link `rnotes-stable.html` instead (7.0.4). That is the
        // cumulative notes since the previous stable release; the same folder's
        // `rnotes.html` holds only the delta since the last test build. Both
        // file names are accepted, because the feed is what picks between them.
        ChangelogRecipe(
            bundleID: "com.surteesstudios.Bartender",
            source: URL(string: "https://downloads.macbartender.com/Bartender7/updates/AppcastB7.xml")!,
            entryPattern: entryPattern,
            itemPatterns: itemPatterns,
            maxEntries: 1,
            headingPattern: headingPattern,
            minimumAppVersion: "7",
            feedPagePattern:
                #"^https://(?:www\.|downloads\.)?macbartender\.com/Bartender7/updates/7(?:-[0-9]+){1,3}/rnotes(?:-stable)?\.html$"#),
        ])

    // Shared by the Bartender 6 and 7 changelog recipes: both trains' pages
    // come off the same template.
    private static let entryPattern =
        #"<h2[^>]*>\s*Bartender\s+(?<version>[0-9]+(?:\.[0-9]+){0,3})\s*</h2>(?<body>.*?)</table>"#
    private static let itemPatterns = [
        #"<li[^>]*>(?<item>.*?)</li>"#,
        #"<p[^>]*>(?<item>.*?)</p>"#,
    ]
    private static let headingPattern = #"<h[34][^>]*>(?<heading>.*?)</h[34]>"#
}
