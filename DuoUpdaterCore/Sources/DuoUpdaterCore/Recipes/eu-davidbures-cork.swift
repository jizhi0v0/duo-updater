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
            changelogURL: URL(string: "https://blog.corkmac.app/"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate("https://corkmac.app/RLS/{version}/Cork.zip"),
                kind: .zip)),
        ],
        changelogs: [
        // History: docs/app-audits/eu-davidbures-cork.md#历史与实测
        // The vendor's release posts on its Substack blog, read from the RSS
        // feed: one `<item>` per post, the post's HTML inlined as
        // `<content:encoded>` CDATA. Only titles shaped `Cork <version> (is) out`
        // are releases; the public betas and the release candidate are titled
        // `Cork 2.0.0 Public Beta 4 is out!` / `… Release Candidate …` and never
        // match, nor do non-release posts. A release with no post (2.0.2, a
        // rebuild of 2.0.1) has no entry.
        //
        // Posts nest lists inside lists, every line in its own `<p>`, so items
        // are the paragraphs (intro lines and list lines alike) and `<h2>`
        // sections (Additions / Fixes / Adjustments) are headings. The body ends
        // before the vendor's closing boilerplate (`NO AI USED, EVER`,
        // `Cork Community` with its social links), and the Substack subscribe
        // box's `cta-caption` paragraph is skipped.
        ChangelogRecipe(
            bundleID: "eu.davidbures.cork",
            source: URL(string: "https://blog.corkmac.app/feed")!,
            entryPattern:
                #"<item>\s*<title><!\[CDATA\[Cork (?<version>[0-9]+(?:\.[0-9]+)+) (?:is )?out\b[^\]]*\]\]></title>"#
                + #".*?<pubDate>[A-Za-z]{3}, (?<date>[0-9]{1,2} [A-Za-z]{3} [0-9]{4})[^<]*</pubDate>"#
                + #".*?<content:encoded><!\[CDATA\[(?<body>.*?)"#
                + #"(?:<h2>(?:NO AI USED|Cork Community)|\]\]></content:encoded>)"#,
            itemPatterns: [#"<p(?![^>]*cta-caption)\b[^>]*>(?<item>.*?)</p>"#],
            maxEntries: 15,
            headingPattern: #"<h2[^>]*>(?<heading>.*?)</h2>"#),
        ])
}
