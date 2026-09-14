import Foundation

enum org_inkscape_Inkscape {
    static let set = AppRecipeSet(
        family: "org-inkscape-Inkscape",
        probes: [
        // History: docs/app-audits/org-inkscape-Inkscape.md#历史与实测
        // Shared rationale for 2026-08-16 vendor batch: Recipes/dev-commandline-waveterm.swift.

        // Inkscape — `/release/` 302s to `/release/inkscape-1.4.4/`, a clean
        // version signal.
        //
        // ONE-CLICK via `.versionTemplate`. The download PAGE hands the file out
        // through an HTML `<meta http-equiv="Refresh">` to `/gallery/item/<id>/…`
        // with a per-release id that no template can predict, but the same file
        // also sits at a plain version-named path on the media host, no gallery id
        // involved — `media.inkscape.org/dl/resources/file/Inkscape-<ver>_arm64.dmg`
        // (checked 2026-08-16; History has the responses, and the earlier note
        // that called the dmg unreachable).
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
        // artifact, which is every host DuoUpdater runs on (`App/project.yml`,
        // `ARCHS: arm64`).
        // snapshot-lint:allow — this dated verification stays in code: `Recipes/dev-commandline-waveterm.swift`'s batch block names this file and relies on it.
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
        // navigation into "changes" (History has the counts on the 1.4.4 page).
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
