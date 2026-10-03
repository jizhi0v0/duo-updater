import Foundation

enum com_google_antigravity {
    static let set = AppRecipeSet(
        family: "com-google-antigravity",
        probes: [
        // History: docs/app-audits/com-google-antigravity.md#历史与实测
        // Antigravity — its own electron-builder feed, on the Cloud Run service the
        // app's updater polls (no Omaha entry was found: the plausible appids tried
        // answered `error-unknownApplication`; History has the check).
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
        // not — that header is a per-machine identifier. The feed `vary`s on it,
        // and what a header-less request gets during a rollout has gone BOTH
        // ways (History has both measurements): on 2026-09-14 it was served
        // 2.13.0 at `stagingPercentage: 10`, i.e. offered here before most
        // installs take it; on 2026-09-23 it got the previous 2.15.1 every time
        // while random staging ids drew 2.16.0 by bucket, i.e. trailing. So
        // neither direction is a rule. When it trails, the changelog page lists
        // the release from its first day and `duo verify` reports the notes
        // "AHEAD of every probe row" until the feed catches up; when it leads,
        // an installed copy can be offered a build its own feed hasn't given it
        // yet. Check the live feed before dismissing either as the rollout.
        //
        // The feed's `sha512` is verifiable: on both checks (History) the served zip's
        // Content-Length was exactly the `size` it states, so the hash was
        // taken on the bytes we will actually download — unlike Signal's feed,
        // where a size delta gave away a hash computed before stapling.
        VendorProbeRecipe(
            bundleID: "com.google.antigravity",
            url: URL(string: "https://antigravity-hub-auto-updater-974169037036"
                + ".us-central1.run.app/manifest/latest-arm64-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*([0-9][0-9.]*)\s*$"#,
            changelogURL: URL(string: "https://antigravity.google/docs/changelog"),
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
            // reads the `ide` panel of `antigravity.google/docs/changelog`.
            downloadURL: URL(string: "https://antigravity.google/download")),
        ],
        changelogs: [
        // History: docs/app-audits/com-google-antigravity.md#历史与实测
        // Antigravity — antigravity.google/docs/changelog, which the hub's
        // `VendorProbeRecipe` also links as its `changelogURL`. The old
        // `/changelog` is now a meta-refresh stub pointing here; a meta refresh is
        // not an HTTP redirect, so URLSession does not follow it and the recipe
        // must name the new URL itself.
        //
        // Read the DECODED body: the server answers gzip even for
        // `Accept-Encoding: identity`, and counting the compressed stream is how
        // this page was once misread as a JS-rendered shell with no versions.
        // Decoded, it is fully server-rendered Astro markup carrying every release
        // for all four products — which is also why both apps can be covered from
        // the one page.
        //
        // One page, four products, one panel each (`data-panel-id`), so the two
        // recipes must not read each other's releases. They anchor on the row
        // instead of the panel wrapper, because the wrapper is an ancestor a flat
        // regex cannot scope to: every row is an `<article>` whose id carries the
        // product and the bare version, e.g. `id="rel-hub-2.19.1"`. The id is read
        // rather than the link text, which is `v`-prefixed (`v2.19.1`).
        //
        // `body` stops at the row's own `</article>` (rows do not nest), and the
        // runs up to the date and the `<h3>` are fenced by it too: a row shipped
        // without a headline would otherwise pair its version with the NEXT row's
        // notes, and the last hub row would reach into the next panel. Items are
        // the lead paragraph (`div.rn-summary`) followed by every `li.rn-item` in
        // the "Improvements" / "Fixes" disclosure groups — the group labels
        // themselves are dropped, as everywhere else.
        ChangelogRecipe(
            bundleID: "com.google.antigravity",
            source: URL(string: "https://antigravity.google/docs/changelog")!,
            entryPattern: antigravityEntryPattern(tab: "hub"),
            itemPatterns: [antigravityItemPattern],
            maxEntries: 20),

        // Antigravity IDE — the `ide` panel of the same page, for the second,
        // separate app (`com.google.antigravity-ide`, a VS Code fork), whose probe
        // recipe carries no `changelogURL`. The page does describe the IDE: its own
        // tab strip has an "Antigravity IDE" panel. See the hub recipe above for the
        // shape; this differs only in the `rel-ide-` anchor.
        ChangelogRecipe(
            bundleID: "com.google.antigravity-ide",
            source: URL(string: "https://antigravity.google/docs/changelog")!,
            entryPattern: antigravityEntryPattern(tab: "ide"),
            itemPatterns: [antigravityItemPattern],
            maxEntries: 20),
        ])

    /// One row of the `tab` panel — see the hub `ChangelogRecipe` for the shape.
    private static func antigravityEntryPattern(tab: String) -> String {
        #"<article[^>]*\bid="rel-"# + tab + #"-(?<version>[^"]+)"[^>]*>"#
            + #"(?:(?!</article>).)*?<time[^>]*>(?<date>[^<]*)</time>"#
            + #"(?:(?!</article>).)*?<h3[^>]*class="rn-headline[^"]*"[^>]*>(?<title>.*?)</h3>"#
            + #"(?<body>.*?)</article>"#
    }

    private static let antigravityItemPattern =
        #"(?:<div class="rn-summary[^"]*"[^>]*><p>|<li[^>]*class="rn-item[^"]*"[^>]*>)"#
        + #"(?<item>.*?)(?:</p>|</li>)"#
}
