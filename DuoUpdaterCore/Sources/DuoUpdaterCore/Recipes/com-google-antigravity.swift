import Foundation

enum com_google_antigravity {
    static let set = AppRecipeSet(
        family: "com-google-antigravity",
        probes: [
        // Antigravity — its own electron-builder feed, on the Cloud Run service the
        // app's updater polls (found by capturing that request, 2026-08-16; there
        // is no Omaha entry — six plausible appids answered
        // `error-unknownApplication` while Gemini's returned `ok`).
        //
        // Preferred over the download page, which was the first thing that worked
        // and is a far worse source: it advertises two products at once (the IDE,
        // under `.../antigravity/stable/`, at its own version) and prints this one
        // as `2.8.1-6512087774658560` while the shipped bundle reports a plain
        // `2.8.1`. The feed states the bundle's own string directly.
        //
        // Verified 2026-08-16 on the mounted artifact: com.google.antigravity,
        // `CFBundleShortVersionString` 2.8.1, Team EQHXZ8M8AV, notarized, and no
        // SUFeedURL (so nothing else covers it). The app sends an
        // `x-user-staging-id` header for its staged rollout; we deliberately do
        // not — the feed answers the same manifest without it, and that header is
        // a per-machine identifier. The consequence is that a release still
        // rolling out (`stagingPercentage` below 100) would be offered here
        // before the app itself takes it.
        //
        // The feed's `sha512` is verifiable: the served zip's Content-Length is
        // exactly the `size` it states (165926585 on 2026-08-16), so the hash was
        // taken on the bytes we will actually download — unlike Signal's feed,
        // where a size delta gave away a hash computed before stapling.
        VendorProbeRecipe(
            bundleID: "com.google.antigravity",
            url: URL(string: "https://antigravity-hub-auto-updater-974169037036"
                + ".us-central1.run.app/manifest/latest-arm64-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*([0-9][0-9.]*)\s*$"#,
            changelogURL: URL(string: "https://antigravity.google/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"url:\s*(https://storage\.googleapis\.com/\S+\.zip)"#),
                kind: .zip,
                checksumPattern: #"sha512:\s*([A-Za-z0-9+/=]+)"#)),

        // Antigravity IDE — a SECOND, separate app from the one above. Different
        // bundle id (`com.google.antigravity-ide`), different version line (2.5.5
        // against the other's 2.9.1), different binary (Electron — it is a VS Code
        // fork, the Windsurf/Codeium lineage Google acquired). It was installed and
        // scanned but matched no recipe, so its row had no source and no notes at
        // all. The sibling recipe's own comment had already noticed this product
        // existed ("the IDE, under `.../antigravity/stable/`") without covering it.
        //
        // Nothing else covers it either: no `SUFeedURL`, no electron-updater
        // `app-update.yml`, and its VS Code `product.json` sets `updateUrl` to the
        // literal `https://example.com`, so the built-in update channel is inert.
        // The real endpoint is in `out/main.js` — a sibling Cloud Run service under
        // the same GCP project number as the hub updater above:
        //   /api/update/{platform}/{quality}/{commit}/{sha256(hostname)}
        //
        // Two deliberate choices in the URL:
        //
        // The last path component is a per-machine identifier (the app sends a
        // SHA-256 of the hostname). We send `no_hostname` — the app's OWN fallback
        // literal from the same code, so it is a value the service already handles
        // rather than something invented, and no machine fingerprint leaves here.
        // Same reasoning as the `x-user-staging-id` header the sibling omits.
        //
        // The commit slot is all zeroes. This is VS Code's update API: it answers
        // 204 No Content when the commit you name is already current, and the
        // update JSON otherwise. Naming the installed commit would therefore return
        // nothing to compare against — and we cannot name it anyway, since it lives
        // in `product.json` inside the bundle, which the scanner does not read. A
        // well-formed hash that can never be a real commit always gets the latest.
        // Verified 2026-08-22: the real commit → 204, all-zeroes → 200 with the
        // manifest.
        //
        // The version comes from the download URL, NOT from any version field in
        // that response — every one of those is the VS Code base (`productVersion`
        // and `name` are both 1.107.0, `version` is a commit hash), while the
        // shipped bundle reports 2.5.5. Comparing 1.107.0 against 2.5.5 would be a
        // permanent phantom update. The URL path carries the real one:
        //   .../antigravity/stable/2.5.5-4923483625488384/darwin-arm/...
        // and the pattern stops at the `-`, so the build id does not ride along —
        // the exact trap the sibling recipe documents for the hub feed.
        //
        // Detection only for now: the artifact is a zip on Google's edgedl CDN with
        // a `sha256hash` beside it, so an install spec is plausible, but it has not
        // been downloaded and signature-checked yet, and the URL is arm64-specific.
        VendorProbeRecipe(
            bundleID: "com.google.antigravity-ide",
            url: URL(string: "https://antigravity-ide-auto-updater-974169037036"
                + ".us-central1.run.app/api/update/darwin-arm64/stable/"
                + "0000000000000000000000000000000000000000/no_hostname")!,
            mode: .responseBody,
            versionPattern: #"/antigravity/stable/([0-9][0-9.]*)-"#,
            // Detection-only rows have no install action, so the page link is the
            // only thing the row can offer — a recipe without one is a dead end
            // (`PageURLTests.detectionOnlyRecipesCarryAPage` enforces it, and
            // caught this omission).
            //
            // No `changelogURL`: the hub's points at `antigravity.google/changelog`,
            // but that page is JS-rendered — 88 KB with zero version strings in the
            // served HTML — so there is no way to confirm from here that it even
            // describes the IDE rather than only the hub. Linking it would be a
            // guess dressed up as coverage.
            downloadURL: URL(string: "https://antigravity.google/download")),
        ],
        changelogs: [
        // Antigravity — antigravity.google/changelog, which the hub's
        // `VendorProbeRecipe` already links as its `changelogURL`.
        //
        // That recipe's sibling (the IDE) says the page is "JS-rendered — 88 KB
        // with zero version strings in the served HTML". That reading was of a
        // *compressed* body: the server answers gzip even for
        // `Accept-Encoding: identity`, and the 88/99 KB it counted is the gzip
        // stream. Decoded it is 401 KB of fully server-rendered Astro markup
        // carrying every release for all four products (2026-09-03) — which is
        // also why both apps can be covered from the one page.
        //
        // One page, four products, one panel each (`data-list-panel`), so the two
        // recipes must not read each other's releases. They anchor on the release
        // link instead of the panel wrapper, because the wrapper is an ancestor a
        // flat regex cannot scope to: every row's version link carries the product
        // in its own href — `/releases?tab=hub&version=2.12.0`. 18 hub entries and
        // 30 IDE entries on the live page, versions matching what the two probe
        // recipes detect (hub 2.12.0, IDE 2.5.5).
        //
        // `body` stops at the next row, the next panel, or the section close, so a
        // row can never absorb the one after it — and the run up to the `<h3>` is
        // fenced by the same two markers, because it is otherwise the one
        // unbounded part of the match: a row shipped without a heading would pair
        // its version with the NEXT row's notes, and the last hub row would reach
        // into the IDE panel. Every row on the live page has a heading today, which
        // is exactly why nothing would have noticed. Items are the lead paragraph
        // (`div.changes`) followed by every `li.caption` in the "Improvements" /
        // "Fixes" / "Patches" disclosure groups — the group labels themselves are
        // dropped, as everywhere else. `<code>/boost</code>` survives as `/boost`
        // through `stripTags`.
        ChangelogRecipe(
            bundleID: "com.google.antigravity",
            source: URL(string: "https://antigravity.google/changelog")!,
            entryPattern:
                #"href="/releases\?tab=hub&amp;version=[^"]*"[^>]*>(?<version>[^<]+)</a>"#
                + #"<br[^>]*>(?<date>[^<]*)</p>"#
                + #"(?:(?!section-row-wrapper|grid-body).)*?"#
                + #"<h3[^>]*data-h3-pin[^>]*>(?<title>.*?)</h3>"#
                + #"(?<body>.*?)(?=<div class="section-row-wrapper|<div class="grid-body|</section>)"#,
            itemPatterns: [
                #"(?:<div class="changes[^"]*"[^>]*><p>|<li[^>]*class="caption[^"]*"[^>]*>)"#
                + #"(?<item>.*?)(?:</p>|</li>)"#
            ],
            maxEntries: 20),

        // Antigravity IDE — the `ide` panel of the same page, for the second,
        // separate app (`com.google.antigravity-ide`, a VS Code fork) whose probe
        // recipe deliberately carried NO `changelogURL` because it could not
        // confirm the page described the IDE at all. It does: the page's own tab
        // strip has an "Antigravity IDE" panel, and its newest entry is 2.5.5 —
        // the exact version that recipe detects. See the hub recipe above for the
        // shape; this differs only in the `tab=ide` anchor.
        ChangelogRecipe(
            bundleID: "com.google.antigravity-ide",
            source: URL(string: "https://antigravity.google/changelog")!,
            entryPattern:
                #"href="/releases\?tab=ide&amp;version=[^"]*"[^>]*>(?<version>[^<]+)</a>"#
                + #"<br[^>]*>(?<date>[^<]*)</p>"#
                + #"(?:(?!section-row-wrapper|grid-body).)*?"#
                + #"<h3[^>]*data-h3-pin[^>]*>(?<title>.*?)</h3>"#
                + #"(?<body>.*?)(?=<div class="section-row-wrapper|<div class="grid-body|</section>)"#,
            itemPatterns: [
                #"(?:<div class="changes[^"]*"[^>]*><p>|<li[^>]*class="caption[^"]*"[^>]*>)"#
                + #"(?<item>.*?)(?:</p>|</li>)"#
            ],
            maxEntries: 20),
        ])
}
