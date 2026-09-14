import Foundation

enum com_google_antigravity {
    static let set = AppRecipeSet(
        family: "com-google-antigravity",
        probes: [
        // History: docs/app-audits/com-google-antigravity.md#历史与实测
        // Antigravity — its own electron-builder feed, on the Cloud Run service the
        // app's updater polls (there is no Omaha entry).
        //
        // Preferred over the download page, which was the first thing that worked
        // and is a far worse source: it advertises two products at once (the IDE,
        // under `.../antigravity/stable/`, at its own version) and prints this one
        // with a build id appended (e.g. `2.8.1-6512087774658560`) while the shipped
        // bundle reports the plain `2.8.1`. The feed states the bundle's own string
        // directly.
        //
        // The artifact is com.google.antigravity, Team EQHXZ8M8AV, notarized, with
        // no SUFeedURL (so nothing else covers it). The app sends an
        // `x-user-staging-id` header for its staged rollout; we deliberately do
        // not — the feed answers the same manifest without it, and that header is
        // a per-machine identifier. The consequence is that a release still
        // rolling out (`stagingPercentage` below 100) would be offered here
        // before the app itself takes it.
        //
        // The feed's `sha512` is verifiable: the served zip's Content-Length is
        // exactly the `size` it states, so the hash was
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
        // bundle id (`com.google.antigravity-ide`), different version line,
        // different binary (Electron — it is a VS Code fork, the Windsurf/Codeium
        // lineage Google acquired). The sibling recipe's comment above names it too
        // ("the IDE, under `.../antigravity/stable/`").
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
        //
        // The version comes from the download URL, NOT from any version field in
        // that response — every one of those is the VS Code base (`productVersion`
        // and `name` carry the base, e.g. 1.107.0; `version` is a commit hash),
        // while the shipped bundle reports its own version (e.g. 2.5.5). Comparing
        // the two would be a permanent phantom update. The URL path carries the
        // real one, e.g.:
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
            // No `changelogURL`, and no `ChangelogCatalog` entry either, so
            // `ChangelogRecipeSelection.fallbackPage` has no web page to offer for
            // this app; its notes come from the IDE `ChangelogRecipe` below, which
            // reads the `tab=ide` panel of `antigravity.google/changelog`.
            downloadURL: URL(string: "https://antigravity.google/download")),
        ],
        changelogs: [
        // Antigravity — antigravity.google/changelog, which the hub's
        // `VendorProbeRecipe` already links as its `changelogURL`.
        //
        // Read the DECODED body: the server answers gzip even for
        // `Accept-Encoding: identity`, and counting the compressed stream is how
        // this page was once misread as a JS-rendered shell with no versions.
        // Decoded it is fully server-rendered Astro markup carrying every release
        // for all four products — which is also why both apps can be covered from
        // the one page.
        //
        // One page, four products, one panel each (`data-list-panel`), so the two
        // recipes must not read each other's releases. They anchor on the release
        // link instead of the panel wrapper, because the wrapper is an ancestor a
        // flat regex cannot scope to: every row's version link carries the product
        // in its own href — e.g. `/releases?tab=hub&version=2.12.0`.
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
        // separate app (`com.google.antigravity-ide`, a VS Code fork), whose probe
        // recipe carries no `changelogURL`. The page does describe the IDE: its own
        // tab strip has an "Antigravity IDE" panel. See the hub recipe above for the
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
