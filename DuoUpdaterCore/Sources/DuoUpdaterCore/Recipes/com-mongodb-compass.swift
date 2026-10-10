import Foundation

enum com_mongodb_compass {
    static let set = AppRecipeSet(
        family: "com-mongodb-compass",
        probes: [
        // History: docs/app-audits/com-mongodb-compass.md#历史与实测
        // MongoDB Compass — the vendor's own download-center JSON
        // (`s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json`).
        // `versions` is newest-first with the plain stable entry leading; when
        // checked (2026-09-14) the entries after it were that release's readonly
        // and isolated editions and a beta, whose `_id`s (`1.50.0-readonly`,
        // `1.50.0-beta.0`, …) carry a suffix the version pattern's closing quote
        // refuses. `versions[0]._id` matched BOTH `CFBundleShortVersionString` and
        // `CFBundleVersion` of a mounted arm64 dmg when verified (2026-08-16,
        // History) — no `versionIsBuild` needed.
        // The same entry's `platform` array carries a `download_link` per
        // arch/os; the arm64/darwin one is captured directly (no template
        // needed, unlike GIMP). No checksum is published in this feed.
        VendorProbeRecipe(
            bundleID: "com.mongodb.compass",
            url: URL(string: "https://s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json")!,
            mode: .responseBody,
            versionPattern: #""_id"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.mongodb.com/try/download/compass"),
            changelogURL: URL(string: "https://www.mongodb.com/docs/compass/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""arch"\s*:\s*"arm64"\s*,\s*"os"\s*:\s*"darwin"\s*,\s*"name"\s*:\s*"[^"]*"\s*,\s*"download_link"\s*:\s*"([^"]+)""#),
                kind: .dmg)),
        ],
        changelogs: [
        // History: docs/app-audits/com-mongodb-compass.md#历史与实测
        // MongoDB Compass — the docs release-notes page (the probe's
        // `changelogURL`), server-rendered HTML, one `<h2>` "MongoDB Compass
        // <version>" per release, newest first, then `<em>Released <date></em>`
        // and `<li>` items until the next `<h2>` or the section's end.
        //
        // Chosen over mongodb-js/compass's GitHub releases. Those are not a
        // monorepo list (only `v<version>` and `v<version>-beta.N` tags), but the
        // bodies are commit subjects (`feat(compass-indexes): …`, `fix(ci): …`)
        // where the page has edited sentences, and the page lists only releases
        // that shipped stable, in the same `1.52.0` shape the download-center
        // JSON offers.
        //
        // Anchored on the heading text and the `headerlink` anchor, not on the
        // hashed CSS-module class names, which change with every docs build. The
        // date group is optional so an entry without the `Released` line still
        // parses.
        ChangelogRecipe(
            bundleID: "com.mongodb.compass",
            source: URL(string: "https://www.mongodb.com/docs/compass/release-notes/")!,
            entryPattern:
                #"<h2[^>]*>MongoDB Compass(?:<!-- -->)?\s*(?<version>[0-9]+\.[0-9]+\.[0-9]+)<a[^>]*class="headerlink.*?</h2>\s*"#
                + #"(?:<p[^>]*><em>Released (?<date>[^<]+)</em></p>)?"#
                + #"(?<body>.*?)(?=<h2|</section>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 20),
        ])
}
