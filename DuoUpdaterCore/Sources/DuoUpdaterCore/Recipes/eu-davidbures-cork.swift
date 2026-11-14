import Foundation

enum eu_davidbures_cork {
    static let set = AppRecipeSet(
        family: "eu-davidbures-cork",
        probes: [
        // History: docs/app-audits/eu-davidbures-cork.md#历史与实测
        // Cork — a Homebrew GUI. No self-updater: no Sparkle, no feed in the
        // bundle, and the binary's "Updates available" strings are about
        // Homebrew packages, not the app. The vendor publishes every release as
        // `corkmac.app/RLS/<version>/Cork.zip` and lists them all at
        // `corkmac.app/releases.json`, an endpoint the vendor made for us
        // (buresdv/Cork#687, 2026-10-18): a JSON array of
        // `{"name": "<version>", "url": "<zip>"}`. GitHub Releases of
        // buresdv/Cork lag the site (a version can be tagged with no release),
        // so the site is the source.
        //
        // The list is sorted as strings (`0.1.10` before `0.1.2`), so
        // `selectHighest`. It also holds `latest`, `macos-13` (a frozen build
        // for macOS 13, below DuoUpdater's floor) and `1.6.x+Sonoma`; the
        // pattern takes only an all-digit dotted name closed by its quote, so
        // none of those match. A name equals the zip's
        // `CFBundleShortVersionString` (two-, three- and four-part alike).
        //
        // Before the endpoint the probe read the folder index `corkmac.app/RLS/`,
        // which the vendor's anti-scraping measure answers with a 403 on every
        // other request; the endpoint answered 20 of 20 with the JSON. See the
        // audit's 历史与实测.
        //
        // One-click via `.versionTemplate` (the resolved version, never the first
        // name in a string-sorted list). The zip holds `Cork.app`,
        // eu.davidbures.cork, universal, notarized Developer ID, Team
        // ZSVA6DVZHM, the same Team on every release read (0.9 through 2.0.3);
        // nothing inside but the app (no helpers, login items or launch
        // agents; launch at login is `SMAppService.mainApp`, the app itself),
        // so `.zip`. A copy on the two older ids is served through
        // `BundleIDMigration`.
        VendorProbeRecipe(
            bundleID: "eu.davidbures.cork",
            url: URL(string: "https://corkmac.app/releases.json")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://corkmac.app/"),
            changelogURL: URL(string: "https://forum.rikidar.eu/category/17/announcements?sort=recently_created"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate("https://corkmac.app/RLS/{version}/Cork.zip"),
                kind: .zip)),
        ],
        changelogs: [
        // History: docs/app-audits/eu-davidbures-cork.md#历史与实测
        // The vendor publishes release posts in its forum's Cork Announcements
        // category. Sort by creation, not replies: a reply on an old release
        // must not make it the latest. Follow the first stable release title;
        // beta/RC and general announcements do not have `<version> (is) out`.
        //
        // Read the topic's original post (`data-index="0"`) only. The category
        // RSS description is the LAST REPLY, not release notes. The body stops
        // at the original post's footer and cannot cross into another post if
        // that footer disappears. Paragraphs and list lines share one pattern
        // so neither drops the other; nested lists are separate items.
        ChangelogRecipe(
            bundleID: "eu.davidbures.cork",
            source: URL(string: "https://forum.rikidar.eu/category/17/announcements?sort=recently_created")!,
            entryPattern:
                #"<span\b[^>]*\bcomponent="topic/title"[^>]*>\s*Cork (?<version>[0-9]+(?:\.[0-9]+)+) (?:is )?out\b[^<]*</span>"#
                + #".*?<li\b(?=[^>]*\bcomponent="post")(?=[^>]*\bdata-index="0")[^>]*>"#
                + #"(?:(?!<li\b[^>]*\bcomponent="post").)*?<meta\b[^>]*\bitemprop="datePublished"[^>]*\bcontent="(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})T[^"]*"[^>]*>"#
                + #"(?:(?!<li\b[^>]*\bcomponent="post").)*?<div\b[^>]*\bcomponent="post/content"[^>]*>"#
                + #"(?<body>(?:(?!<li\b[^>]*\bcomponent="post").)*?)</div>\s*<div\b[^>]*\bcomponent="post/footer""#,
            itemPatterns: [#"<(?:p|li)\b[^>]*>(?<item>(?:(?!<(?:p|li|ul|ol)\b).)*?)(?=</(?:p|li)>|<(?:ul|ol)\b)"#],
            maxEntries: 1,
            indexLinkPattern: #"<h3\b[^>]*\bcomponent="topic/header"[^>]*>\s*<a\b[^>]*href="(?<link>/topic/[0-9]+/cork-[^"/]+)"[^>]*>\s*Cork [0-9]+(?:\.[0-9]+)+ (?:is )?out\b"#,
            headingPattern: #"<h[1-6]\b[^>]*>(?<heading>.*?)</h[1-6]>"#),
        ])
}
