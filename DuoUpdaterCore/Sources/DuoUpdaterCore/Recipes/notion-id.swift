import Foundation

enum notion_id {
    static let set = AppRecipeSet(
        family: "notion-id",
        probes: [
        // Notion desktop — public "latest" download redirect. www.notion.so/
        // desktop/mac/download 307s straight to the versioned installer
        // (…/Notion-<ver>-universal.dmg); the version is in that `Location`
        // filename. It redirects on BOTH HEAD and GET, but the target is a
        // ~203 MB dmg, so don't follow — read the small 307 Location. Use the
        // `.so` host: it's a single hop, whereas `.com/desktop/mac/download`
        // bounces through app.notion.com first. ChangelogRecipe(notion.id) renders
        // notes. One-click: the very same `/desktop/mac/download` 307 IS the
        // installer link — the install spec HEAD-follows it to the versioned
        // universal dmg and swaps in place (on top of Notion's own self-updater).
        VendorProbeRecipe(
            bundleID: "notion.id",
            url: URL(string: "https://www.notion.so/desktop/mac/download")!,
            mode: .redirectFilename,
            versionPattern: #"Notion-([0-9]+\.[0-9]+\.[0-9]+)-"#,
            downloadURL: URL(string: "https://www.notion.com/desktop")!,
            // The desktop what's-new page, NOT www.notion.com/releases: that one is
            // the product announcement feed whose "versions" are post titles with no
            // build number, which is the mismatch the changelog recipe moved away
            // from. This is the WebView fallback, so pointing it at the old page put
            // the user right back on the feed that doesn't match their install.
            changelogURL: URL(
                string: "https://notion.notion.site/What-s-New-Mac-Windows-5936dabc8dd6497895786c91b9d6f12a")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://www.notion.so/desktop/mac/download")!),
                kind: .dmg),
            followRedirects: false),
        ],
        changelogs: [
        // Notion — the DESKTOP app's real "What's New" page,
        // `notion.notion.site/What-s-New-Mac-Windows-5936dabc8dd6497895786c91b9d6f12a`.
        // This is the recipe wired up for `notion.id`; see `NOT REGISTERED` below
        // for the *other* Notion recipe this replaces and why.
        //
        // The rendered HTML is a 19 KB empty Next.js shell — zero content. The real
        // notes come from Notion's own internal, unauthenticated page-rendering API,
        // which only answers a POST:
        //   POST https://notion.notion.site/api/v3/loadPageChunk
        //   {"pageId":"5936dabc-8dd6-4978-9578-6c91b9d6f12a","limit":50,
        //    "cursor":{"stack":[]},"chunkNumber":0,"verticalColumns":false}
        // (`source` below is set to that API URL directly — there is nothing
        // useful to fetch at the human-facing page URL itself.) See
        // `StructuredChangelogDecoder.decodeNotionPageChunk` for the response shape
        // (`recordMap.block`, double-`value` wrapping, and the page block's
        // `content` array as the true reading order) and how the header/text/
        // bulleted_list blocks are grouped into releases.
        //
        // Verified live 2026-08-22: the header text is "v7.31.0" (`v` stripped so
        // the rail label reads "7.31.0", matching the installed build the vendor
        // probe's `.redirectFilename` reports) and the release order runs
        // v7.31.0 → v7.29.0 → v7.28.0 → … — newest first, real desktop builds, not
        // the product-announcement post titles the old recipe surfaced.
        //
        // `acknowledgedStaleEntry` (#493): read live 2026-09-11, the page's newest
        // header is still v7.32.0 ("Released" 2026-08-31; the page block was last
        // edited 2026-09-01 01:22 UTC), while `www.notion.so/desktop/mac/download` already
        // 307s to `Notion-7.33.0-universal.dmg`. The decoder reads the page
        // correctly — Notion has not written the 7.33.0 notes — so the sweep's
        // "a whole release behind" is the vendor's lag, not ours. Named rather than
        // switched off: once the page moves, to 7.33.0 or anywhere else, the check
        // runs again.
        ChangelogRecipe(
            bundleID: "notion.id",
            source: URL(string: "https://notion.notion.site/api/v3/loadPageChunk")!,
            maxEntries: 20,
            structuredFormat: .notionPageChunk,
            httpMethod: .post,
            requestBody: Data(
                (#"{"pageId":"5936dabc-8dd6-4978-9578-6c91b9d6f12a","limit":50,"#
                    + #""cursor":{"stack":[]},"chunkNumber":0,"verticalColumns":false}"#
                ).utf8),
            acknowledgedStaleEntry: "7.32.0"),
        ])
}
