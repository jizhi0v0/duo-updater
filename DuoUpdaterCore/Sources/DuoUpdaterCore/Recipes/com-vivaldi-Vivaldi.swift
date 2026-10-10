import Foundation

enum com_vivaldi_Vivaldi {
    static let set = AppRecipeSet(
        family: "com-vivaldi-Vivaldi",
        probes: [
        // History: docs/app-audits/com-vivaldi-Vivaldi.md#历史与实测
        // Vivaldi — Snapshot (preview) track. Sparkle appcast on the `snapshot`
        // channel. Independent bundle id (`com.vivaldi.Vivaldi.snapshot`) so the
        // channel gate routes it automatically. `sparkle:shortVersionString` carries
        // the marketing version (e.g. "8.1.4063.3"), and here it equals the bundle's
        // CFBundleShortVersionString exactly — no scheme mismatch to work around,
        // unlike the Brave feeds (`Recipes/com-brave-Browser.swift`).
        //
        // One-click: the enclosure is a universal `.tar.xz` holding `Vivaldi
        // Snapshot.app`, bundle id com.vivaldi.Vivaldi.snapshot, Team 4XF3XNRN6Y,
        // spctl "Notarized Developer ID" (checked 2026-08-09; History has the
        // build). `.tarGz` covers xz — see the ImageOptim note.
        //
        // DEAD FOR DETECTION, kept as a sweep anchor — same as Bartender and
        // ImageOptim. When checked on a real Snapshot bundle (2026-08-31; History
        // has the build), it declared `SUFeedURL = https://update.vivaldi.com/
        // update/1.0/snapshot/mac/appcast.xml`, this exact address, so Sparkle
        // answers first.
        VendorProbeRecipe(
            bundleID: "com.vivaldi.Vivaldi.snapshot",
            url: URL(string: "https://update.vivaldi.com/update/1.0/snapshot/mac/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)</sparkle:shortVersionString>"#,
            changelogURL: URL(string: "https://vivaldi.com/blog/desktop/")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://downloads\.vivaldi\.com/[^"]+\.tar\.xz)""#),
                kind: .tarGz),
            channel: .preview),
        ],
        changelogs: [
        // Vivaldi (Stable) — the appcast (`public/mac/appcast.xml`) inlines no
        // notes; each item links one page of its own,
        // `update.vivaldi.com/update/1.0/relnotes/<version>.html`, named after the
        // item's `sparkle:shortVersionString`. So the page is templated on the
        // offered (else installed) version, and every past build keeps its page.
        //
        //   * A page is cumulative: an intro `<h2>` and `<p>`, then one
        //     `<h2>Changelog since Vivaldi 8.2 (4133.83)</h2>` + `<ul>` per earlier
        //     build of the series, newest first (the first `<ul>` also carries
        //     `class="latestchanges"`). Only that first list is this build's
        //     changes, so one entry, the first "Changelog since" section, with its
        //     `<h2>` kept as a heading — it names the build the list is measured
        //     FROM, never this one.
        //   * The page does not reliably name its own version (most intros say
        //     only "Vivaldi 8.2 has arrived!"), so the version is the one in the
        //     URL (`versionFromTemplate`). A missing version is an nginx 404.
        //   * Each `<li>` ends with a `<span>` (a `VB-…` ticket, or the Chromium
        //     security note); stripping tags keeps its text after the change.
        //
        // Vivaldi Snapshot is `com.vivaldi.Vivaldi.snapshot`, so this recipe never
        // reaches it; it has its own recipe below.
        ChangelogRecipe(
            bundleID: "com.vivaldi.Vivaldi",
            // Never parsed: with no version there is nothing to name the entry, so
            // only the templated page is ever read.
            source: URL(string: "https://update.vivaldi.com/update/1.0/public/mac/appcast.xml")!,
            entryPattern:
                #"(?<body><h2[^>]*>\s*Changelog since\b[^<]*</h2>\s*<ul[^>]*>.*?</ul>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 1,
            sourceTemplate: "https://update.vivaldi.com/update/1.0/relnotes/{version}.html",
            versionFromTemplate: true,
            headingPattern: #"<h2[^>]*>(?<heading>\s*Changelog since\b[^<]*)</h2>"#),

        // Vivaldi Snapshot — the same scheme on its own pages: the snapshot
        // appcast inlines no notes and each item links
        // `relnotes/snapshot/<version>.html`, named after the item's
        // `sparkle:shortVersionString` (the bundle's own version, e.g. 8.3.4185.3),
        // so the page is templated on the offered (else installed) version exactly
        // as for Stable. A snapshot page has no intro and one section,
        // `<h2>Changelog since version 4175.3</h2>` + `<ul>`: the changes since the
        // previous snapshot build, which the heading names (never this one). The
        // version therefore comes from the URL, and the Stable patterns read it
        // unchanged.
        ChangelogRecipe(
            bundleID: "com.vivaldi.Vivaldi.snapshot",
            // Never parsed, as for Stable.
            source: URL(string: "https://update.vivaldi.com/update/1.0/snapshot/mac/appcast.xml")!,
            entryPattern:
                #"(?<body><h2[^>]*>\s*Changelog since\b[^<]*</h2>\s*<ul[^>]*>.*?</ul>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 1,
            sourceTemplate: "https://update.vivaldi.com/update/1.0/relnotes/snapshot/{version}.html",
            versionFromTemplate: true,
            headingPattern: #"<h2[^>]*>(?<heading>\s*Changelog since\b[^<]*)</h2>"#),
        ],
        channelProofs: [
        ChannelProofKey("com.vivaldi.Vivaldi.snapshot", .preview): .artifact(#"/snapshot-auto/"#),
        ])
}
