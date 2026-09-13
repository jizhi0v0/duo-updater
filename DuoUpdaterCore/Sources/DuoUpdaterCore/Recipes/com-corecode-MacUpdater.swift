import Foundation

enum com_corecode_MacUpdater {
    static let set = AppRecipeSet(
        family: "com-corecode-MacUpdater",
        probes: [
        // MacUpdater — version is in an HTML comment marker on the product page.
        // NOTE: HTML scrape — more brittle than an API; refresh if it stops
        // matching.
        //
        // One-click verified 2026-08-09 on 3.5.0: `macupdater_latest.dmg` is an
        // unversioned "latest" URL holding `MacUpdater.app` — bundle id
        // com.corecode.MacUpdater, Team 9D78DG5ACV, spctl "Notarized Developer ID".
        // Fixed rather than scraped: the page's only download href is that same
        // stable path.
        VendorProbeRecipe(
            bundleID: "com.corecode.MacUpdater",
            url: URL(string: "https://www.corecode.io/macupdater/")!,
            mode: .responseBody,
            versionPattern: #"<!--BEGINVERSION-->([0-9.]+)<!--ENDVERSION-->"#,
            changelogURL: URL(string: "https://www.corecode.io/macupdater/history3.html"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://www.corecode.io/downloads/macupdater_latest.dmg")!),
                kind: .dmg)),
        ],
        changelogs: [
        // TablePro — deliberately NO recipe. The app ships a Sparkle feed
        // (`SUFeedURL` = raw.githubusercontent.com/TableProApp/TablePro/main/
        // appcast.xml) whose every `<item>` carries the full release notes inline
        // in `<description>` (21 KB of `<h3>` + `<ul><li>` for 0.67.0, 137 items
        // deep), so `SparkleAppcastSource` already hands the pane a changelog we
        // fetched for the version check anyway — a recipe here would only preempt
        // it (recipe beats `structuredChangelog`/`releaseNotesHTML` in the
        // workbench) and cost a second request.
        //
        // The recipe this replaces scraped docs.tablepro.app and broke TWICE on
        // pure vendor churn: once when Mintlify swapped the label element to a
        // `<button>` (2026-08-09, fixed by moving to the `.md` twin), then again
        // when TablePro flipped the `<Update>` attributes to `label="v0.67.0"
        // description="August 21, 2026"` — the reverse of what the `.md` pattern
        // required, and now the same order Claude's Mintlify page uses. Two breaks
        // in two weeks on a source we did not need is why this is gone rather than
        // re-patched.

        // MacUpdater — corecode.io/macupdater/history3.html is a single static
        // page of every release newest-first (no hydration). 3.5.0 is the final
        // release (the product is discontinued), so the page is effectively
        // frozen. Each version block is:
        //   <p><b>3.5.0</b> (Jan 2026):</p>
        //   <p>• item…</p>
        //   <p>• item…</p>
        // Version and date are in the <p><b>…</b> (…)</p> header; each change is a
        // bullet <p>• …</p> until the next version header. The bullet is a literal
        // U+2022, so the item pattern anchors on it to skip non-bullet paragraphs.
        ChangelogRecipe(
            bundleID: "com.corecode.MacUpdater",
            source: URL(string: "https://www.corecode.io/macupdater/history3.html")!,
            entryPattern:
                #"<p><b>(?<version>[0-9][0-9.]*)</b>\s*\((?<date>[^)]*)\):</p>"#
                + #"(?<body>.*?)"#
                + #"(?=<p><b>[0-9][0-9.]*</b>\s*\(|$)"#,
            itemPatterns: [#"<p>\s*•\s*(?<item>.*?)</p>"#],
            maxEntries: 20),
        ])
}
