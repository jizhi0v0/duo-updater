import Foundation

enum eu_davidbures_cork {
    static let set = AppRecipeSet(
        family: "eu-davidbures-cork",
        probes: [
        // History: docs/app-audits/eu-davidbures-cork.md#历史与实测
        // Cork — a Homebrew GUI. No self-updater: no Sparkle, no feed in the
        // bundle, and the binary's "Updates available" strings are about
        // Homebrew packages, not the app. The vendor publishes every release as
        // `corkmac.app/RLS/<version>/Cork.zip`, and the folder index at
        // `corkmac.app/RLS/` (nginx autoindex) is what the Homebrew cask's
        // livecheck reads. GitHub Releases of buresdv/Cork lag the site (a
        // version can be tagged with no release), so the site is the source.
        //
        // The index also holds `latest/`, `macos-13/` (a frozen build for
        // macOS 13, below DuoUpdater's floor) and `1.6.x%2BSonoma/` folders.
        // The pattern takes only an all-digit dotted name right before `/"`,
        // so none of those match, and an `-beta`-style folder could not either.
        // The index is alphabetical, so `selectHighest`. A folder's name equals
        // the zip's `CFBundleShortVersionString` (two-, three- and four-part
        // names alike).
        //
        // THE SERVER ANSWERS EVERY OTHER REQUEST WITH ITS HOME PAGE: HTTP 200,
        // the full site HTML, for the index and for every zip URL. That body
        // is recognised as transient (an HTML5 document titled `Cork: …`; the
        // healthy index is a bare `<html>` titled `Index of /RLS/`) and retried
        // once, which lands on the other answer. The download has no such
        // retry: when the zip request draws the home page, unpacking fails and
        // the install fails without touching the app; the next attempt draws
        // the zip. See the audit's 已知问题.
        //
        // One-click via `.versionTemplate` (the resolved version, never a first
        // match on an alphabetical index). The zip holds `Cork.app`,
        // eu.davidbures.cork, universal, notarized Developer ID, Team
        // ZSVA6DVZHM, the same Team on every release read (0.9 through 2.0.3);
        // nothing inside but the app (no helpers, login items or launch
        // agents; launch at login is `SMAppService.mainApp`, the app itself),
        // so `.zip`. A copy on the two older ids is served through
        // `BundleIDMigration`.
        VendorProbeRecipe(
            bundleID: "eu.davidbures.cork",
            url: URL(string: "https://corkmac.app/RLS/")!,
            mode: .responseBody,
            versionPattern: #"href="([0-9]+(?:\.[0-9]+)+)/""#,
            transientBodyPattern: #"(?s)\A\s*<!DOCTYPE html>.*?<title>Cork:[^<]*</title>"#,
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
