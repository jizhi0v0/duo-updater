import Foundation

enum com_1password_1password {
    static let set = AppRecipeSet(
        family: "com-1password-1password",
        probes: [
        // History: docs/app-audits/com-1password-1password.md#历史与实测
        // 1Password 8 — self-updates via its own EdDSA updater, so no standard
        // source resolves it. The vendor's app-updates.agilebits.com/check JSON
        // API only serves the NIGHTLY channel for product OPM8 (no stable param
        // exists), so it can't be used for a stable install.
        //
        // The version comes from the stable channel's RSS FEED
        // (`…/mac/stable/index.xml`), not from scraping the HTML page beside it:
        // a feed is a published interface with fixed element names, while the
        // page's version sat in a `c-updates__title` class that a redesign renames
        // without anyone calling it breaking. The same feed backs
        // `ChangelogRecipe(com.1password.1password)`.
        //
        // `selectHighest` rather than first-match, because the feed is ASCENDING
        // (8.7.0 from 2022 is item 1) — first-match here would report a
        // four-year-old release as current, which reads as "up to date" forever.
        // Comparing numerically means the order stops mattering at all.
        //
        // ONE-CLICK — but NOT from the URL the download page hands out.
        // `downloads.1password.com/mac/1Password.zip` looks perfect (stable URL,
        // Developer ID 2BUA8C4S2C, notarized) and is a trap: it contains
        // `1Password Installer.app` (`com.1password.1password-installer`), a
        // stub that fetches the real app. Swapping THAT over
        // `/Applications/1Password.app` would replace the password manager with its
        // own installer — and every signature gate would pass, because the stub is
        // genuinely signed by AgileBits. Only the bundle-id gate stands between
        // that URL and a broken install.
        //
        // The payload the stub itself downloads is per-architecture and public
        // (read out of the installer binary's own strings, 2026-08-16):
        //   downloads.1password.com/mac/1Password-latest-{aarch64,x86_64}.zip
        // plus `.BETA-` / `.NIGHTLY-` variants for the other channels. The aarch64
        // one unzips to `1Password.app` itself — Team 2BUA8C4S2C, notarized (History
        // has the verification).
        //
        // A "latest" URL rather than a version template: 1Password publishes no
        // versioned artifact path, so this can in principle serve a build newer
        // than the page reported. That is the same shape as the other `latest`
        // installs here (Termius, iStat Menus) and the gates still apply; what it
        // must never become is the stub URL above.
        VendorProbeRecipe(
            bundleID: "com.1password.1password",
            url: URL(string: "https://releases.1password.com/mac/stable/index.xml")!,
            mode: .responseBody,
            versionPattern: #"<title>1Password for Mac\s+([0-9]+\.[0-9]+\.[0-9]+)</title>"#,
            downloadURL: URL(string: "https://1password.com/downloads/mac/"),
            changelogURL: URL(string: "https://releases.1password.com/mac/stable/"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://downloads.1password.com/mac/1Password-latest-aarch64.zip")!),
                kind: .zip)),
        ],
        changelogs: [
        // 1Password 8 (Mac) — the STABLE channel's RSS feed, `…/mac/stable/index.xml`,
        // not the HTML page next to it (the bare /mac/ landing page is only a
        // two-card hub with no change items; the beta channel has its own
        // /mac/beta/ feed). Both carry the same releases; the feed is the sturdier
        // read — it is a published interface with fixed element names, where the
        // page's `c-updates__release` / `c-updates__title` class names are styling
        // that a site redesign renames without anyone calling it a breaking change.
        //
        // Each item (captured verbatim 2026-08-16):
        //   <item><title>1Password for Mac 8.12.33</title><link>…</link>
        //   <pubDate>Wed, 12 Aug 2026 00:00:00 +0000</pubDate><guid>…</guid>
        //   <description>&lt;ul&gt;&lt;li&gt;We&amp;rsquo;ve fixed …&lt;/li&gt;&lt;/ul&gt;</description></item>
        //
        // Two consequences of it being a feed rather than a page:
        //   * items are ASCENDING (8.7.0 from 2022 first), so
        //     `newestLast` flips them — the HTML page was newest-first;
        //   * the change list lives ENTITY-ESCAPED inside <description>, so the
        //     item pattern matches `&lt;li&gt;`, not `<li>`. Matching a raw `<li>`
        //     here finds nothing at all.
        // Items keep the vendor's inline issue refs ([[!40819]]) as written.
        ChangelogRecipe(
            bundleID: "com.1password.1password",
            source: URL(string: "https://releases.1password.com/mac/stable/index.xml")!,
            entryPattern:
                #"<item>\s*<title>1Password for Mac\s*(?<version>[0-9][0-9.]*)</title>.*?"#
                + #"<pubDate>(?<date>[^<]+)</pubDate>.*?"#
                + #"<description>(?<body>.*?)</description>\s*</item>"#,
            itemPatterns: [#"&lt;li&gt;(?<item>.*?)&lt;/li&gt;"#],
            escapedMarkup: true,
            newestLast: true),
        ])
}
