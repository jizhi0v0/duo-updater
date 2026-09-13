import Foundation

enum org_inkscape_Inkscape {
    static let set = AppRecipeSet(
        family: "org-inkscape-Inkscape",
        probes: [
        // Inkscape — `/release/` 302s to `/release/inkscape-1.4.4/`, a clean
        // version signal.
        //
        // ONE-CLICK via `.versionTemplate`. An earlier note here said the dmg was
        // unreachable, because the download PAGE hands the file out through an
        // HTML `<meta http-equiv="Refresh">` to `/gallery/item/<id>/…` with a
        // per-release id (59498 for 1.4.4_arm64) that no template can predict.
        // That was the wrong place to look: the same file also sits at a plain
        // version-named path on the media host, no gallery id involved —
        // `media.inkscape.org/dl/resources/file/Inkscape-<ver>_arm64.dmg`
        // (2026-08-16: 1.4.4 → 200, 156,920,591 B; 1.4.3 → 200).
        //
        // The naming does NOT reach back forever — 1.4.2 is a 404 under every
        // variant tried — but that costs nothing here: the URL is only ever built
        // for the version the probe just resolved, i.e. the current release. A
        // future rename fails the download loudly (the row stays red) rather than
        // installing something else.
        //
        // Verified 2026-08-16 by mounting the 1.4.4 dmg: `Inkscape.app`,
        // org.inkscape.Inkscape, CFBundleShortVersionString `1.4.4` — same scheme
        // the redirect publishes — Team SW3D6BB6A6 (Rene de Hesselle, who also
        // signs Meld, `Recipes/org-gnome-Meld.swift`), notarized Developer ID, spctl accepted. arm64-only
        // artifact, so an Intel Mac is refused by the runnable-arch gate rather
        // than handed a build it can't run.
        VendorProbeRecipe(
            bundleID: "org.inkscape.Inkscape",
            url: URL(string: "https://inkscape.org/release/")!,
            mode: .redirectFilename,
            versionPattern: #"inkscape-([0-9]+\.[0-9]+(?:\.[0-9]+)?)"#,
            downloadURL: URL(string: "https://inkscape.org/release/"),
            changelogURL: URL(string: "https://inkscape.org/news/"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://media.inkscape.org/dl/resources/file/Inkscape-{version}_arm64.dmg"),
                kind: .dmg),
            followRedirects: false),
        ],
        changelogs: [
        // Inkscape — the project's own wiki carries one release-notes page per
        // version: `wiki.inkscape.org/wiki/Release_notes/1.4.4`. inkscape.org's
        // release page has no notes at all (it is a download page), and the news
        // feed mixes releases with everything else, so the wiki is the only
        // per-version source. Version-templated for the same reason as
        // Thunderbird: each page is exactly one release, so `maxEntries: 1`.
        //
        // The item pattern matches a BARE `<li>` on purpose. MediaWiki's table of
        // contents is a nested list whose items all carry
        // `class="toclevel-N tocsection-N"`, and the page footer's are
        // `<li id="footer-info-…">` — allowing attributes would turn the whole
        // navigation into "changes" (35 TOC entries against 116 real ones on the
        // 1.4.4 page, captured 2026-08-16).
        ChangelogRecipe(
            bundleID: "org.inkscape.Inkscape",
            source: URL(string: "https://wiki.inkscape.org/wiki/Release_notes/1.4")!,
            entryPattern:
                #"<h1 id="firstHeading"[^>]*>Release notes/(?<version>[0-9]+(?:\.[0-9]+)*)</h1>"#
                + #".*?<h2[^>]*>\s*<span[^>]*id="Changes_and_Bug_Fixes""#
                + #"(?<body>.*?)<h2[^>]*>\s*<span[^>]*id="Other_releases""#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            maxEntries: 1,
            channel: .stable,
            sourceTemplate: "https://wiki.inkscape.org/wiki/Release_notes/{version}"),
        ])
}
