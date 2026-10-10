import Foundation

enum com_sublimemerge {
    static let set = AppRecipeSet(
        family: "com-sublimemerge",
        probes: [
        // History: docs/app-audits/com-sublimemerge.md#历史与实测
        // Sublime Merge — self-updates, so it reaches us here. NOTE: HTML scrape
        // (mirrors the Sublime Text 4 recipe in
        // `Recipes/com-sublimetext-4.swift` — same vendor, same page shape, and
        // the same bare-number JSON update check, here
        // `sublimemerge.com/updates/stable_update_check`). The /download page's
        // latest marker (e.g. `<p class="latest"><i>Version:</i> Build 2125</p>`)
        // precedes the descending history, so the anchored "Build NNNN" is newest.
        // CRITICAL: capture the FULL "Build NNNN" string — the app's
        // CFBundleShortVersionString has the form "Build NNNN" (e.g. "Build 2125"),
        // and a bare "2125" would read as a perpetual phantom update
        // (VersionComparator ranks a number above adjacent text). Builds are 2xxx
        // (not 4xxx like Sublime Text); the class="latest" anchor already makes it
        // single-match.
        VendorProbeRecipe(
            bundleID: "com.sublimemerge",
            url: URL(string: "https://www.sublimemerge.com/download")!,
            mode: .responseBody,
            versionPattern: #"class="latest"><i>Version:</i>\s*(Build\s+[0-9]+)"#,
            changelogURL: URL(string: "https://www.sublimemerge.com/download"),
            // Same shape as Sublime Text: the page ships the download link as the
            // literal template `sublime_merge_build_${version}_mac.zip` for JS to
            // fill, so it's rebuilt from the same "latest" marker, taking the BARE
            // build number (the version keeps its "Build " prefix to match what the
            // bundle reports; a URL can't carry it).
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.sublimetext.com/sublime_merge_build_{0}_mac.zip",
                    fields: [#"class="latest"><i>Version:</i>\s*Build\s+([0-9]{4})"#]),
                kind: .zip)),
        ],
        changelogs: [
        // History: docs/app-audits/com-sublimemerge.md#历史与实测
        // Sublime Merge — the same /download page the probe reads carries the
        // changelog inline, server-rendered, newest first (same shape as Sublime
        // Text's page):
        //   <article class="current"><h3>Build 2132</h3><div class="release-date">18 September 2026</div>
        //   <h3>New Features and Improvements</h3>   ← section names, larger builds only
        //   <ul class="topic"><li>…</li></ul> … </article>
        // The version is the FULL "Build NNNN", the same string the probe offers and
        // the bundle reports as CFBundleShortVersionString; a bare number would
        // never equal either. Only 4-digit builds directly in the article's first
        // `<h3>` are entries, so the section `<h3>`s inside a body are headings,
        // not versions. The page lists stable builds only; dev builds have their
        // own page (/dev).
        ChangelogRecipe(
            bundleID: "com.sublimemerge",
            source: URL(string: "https://www.sublimemerge.com/download")!,
            entryPattern:
                #"<article[^>]*>\s*<h3>\s*(?<version>Build\s+[0-9]{4})\s*</h3>\s*"#
                + #"(?:<div class="release-date">(?<date>[^<]*)</div>)?"#
                + #"(?<body>.*?)</article>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            headingPattern: #"<h3[^>]*>(?<heading>[^<]*)</h3>"#),
        ])
}
