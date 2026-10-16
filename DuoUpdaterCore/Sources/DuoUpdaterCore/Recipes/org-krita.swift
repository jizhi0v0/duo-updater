import Foundation

enum org_krita {
    static let set = AppRecipeSet(
        family: "org-krita",
        probes: [
        // History: docs/app-audits/org-krita.md#历史与实测
        // Krita (KDE) — no Sparkle, no self-installer. The app's own check only
        // reads krita.org's news feed and links to the download page. KDE ships
        // two lines from one source tree under ONE bundle id, `org.krita`: 5.x
        // (Qt 5, the vendor's recommendation for productive work) and 6.x (Qt 6,
        // "more experimental"). Nothing but the major version tells them apart,
        // so each line gets its own recipe, split by `installedVersionPattern`
        // (the Carbon Copy Cloner shape), and a distinct `variant`.
        //
        // Versions: KDE publishes hotfixes as a fourth component (`5.3.4.1`), but
        // the bundle's `CFBundleShortVersionString` and `CFBundleVersion` carry
        // only three (`5.3.4` for the 5.3.4.1 dmg). Both patterns therefore
        // capture the first three components and drop the fourth: reading
        // `5.3.4.1` would compare above the `5.3.4` a hotfixed copy reports, an
        // update offered forever. A hotfix over its own base release is not
        // offered (the two read the same); the next release is.
        //
        // Recommended line: `krita.org/en/download/`, the page the app and the
        // vendor send users to. It links exactly one macOS dmg, the current
        // recommended release, hotfix included
        // (`download.kde.org/stable/krita/<v>/krita-<v>-signed.dmg`); version and
        // install URL are read off that same link. Applies to every installed
        // copy except the 6.x line, so when KDE moves the page to 6.x (the 5.3.0
        // post says it expects 6 to become the main version), 5.x copies are
        // offered what the page offers.
        //
        // One-click: universal dmg holding only `krita.app`, Developer ID Team
        // DL93766A3G, notarized. download.kde.org redirects to a mirror; the
        // Team-ID gate is the integrity check (the vendor publishes md5 only,
        // which `checksumFormat` cannot take). The bundle's Quick Look and
        // Spotlight extensions run on demand, no resident helper.
        VendorProbeRecipe(
            bundleID: "org.krita",
            url: URL(string: "https://krita.org/en/download/")!,
            mode: .responseBody,
            versionPattern:
                #"https://download\.kde\.org/stable/krita/([0-9]+\.[0-9]+\.[0-9]+)(?:\.[0-9]+)?/krita-[0-9.]+-signed\.dmg"#,
            downloadURL: URL(string: "https://krita.org/en/download/"),
            changelogURL: URL(string: "https://krita.org/en/posts/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://download\.kde\.org/stable/krita/[0-9]+(?:\.[0-9]+){2,3}/krita-[0-9]+(?:\.[0-9]+){2,3}-signed\.dmg)"#),
                kind: .dmg),
            variant: "download-page",
            installedVersionPattern: #"^(?!6\.)"#),
        // 6.x line: the download page does not link it, so this reads
        // krita.org's own news feed (the URL the app's update check fetches,
        // `/en/feed/`, 301s here). Each release post links both lines' dmgs; the
        // highest `stable/krita/6.*` dmg wins, by the version each link names, in
        // any order. Pinned to major 6 on both sides: a 5.x link is the other
        // line, and a future major that appears beside 6 is a separate decision.
        // Betas live under `unstable/` and never match.
        //
        // The feed keeps the newest 20 posts; a release older than that is not
        // read. Hotfixes appear here only when KDE wrote a post for them, so the
        // install can be the base release rather than its hotfix (same reported
        // version either way).
        VendorProbeRecipe(
            bundleID: "org.krita",
            url: URL(string: "https://krita.org/en/index.xml")!,
            mode: .responseBody,
            versionPattern:
                #"https://download\.kde\.org/stable/krita/(6\.[0-9]+\.[0-9]+)(?:\.[0-9]+)?/krita-[0-9.]+-signed\.dmg"#,
            downloadURL: URL(string: "https://krita.org/en/posts/"),
            changelogURL: URL(string: "https://krita.org/en/posts/"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .bodyPatternHighestVersioned(
                    #"(https://download\.kde\.org/stable/krita/(6\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)/krita-[0-9.]+-signed\.dmg)"#),
                kind: .dmg),
            variant: "krita6",
            installedVersionPattern: #"^6\."#),
        ],
        changelogs: [
        // Krita — the release posts in krita.org's RSS feed. Each item's
        // <description> carries the whole post ENTITY-ESCAPED (`&lt;li&gt;`), so
        // the item pattern matches the escaped form and `escapedMarkup` strips
        // the tags it unescapes. The body stops at the first download heading
        // (`<h2 id="download-534">` / `<h2 id="531-download">`): everything after
        // it is per-platform download links, not changes. A post whose changes
        // are prose (5.3.0's "What's New") or that only ships a hotfix yields no
        // items.
        //
        // One post covers both lines ("Today we're releasing Krita 5.3.4 and
        // 6.0.4"), titled by the 5.x number. The 5.x recipe takes the title's
        // version; the 6.x recipe takes the version from the post's own 6.x
        // download heading, so each line's entries carry its own numbers.
        // `belowAppVersion`/`minimumAppVersion` "6" tile the two.
        ChangelogRecipe(
            bundleID: "org.krita",
            source: URL(string: "https://krita.org/en/index.xml")!,
            entryPattern:
                #"<item>\s*<title>Krita (?<version>[0-9]+(?:\.[0-9]+){2,3})(?: Released!| bugfix release!)</title>.*?"#
                + #"<pubDate>(?<date>[^<]+)</pubDate>.*?"#
                + #"<description>(?<body>.*?)(?=&lt;h2 id="[^"]*download|</description>)"#,
            itemPatterns: [#"&lt;li&gt;(?<item>.*?)&lt;/li&gt;"#],
            escapedMarkup: true,
            belowAppVersion: "6"),
        ChangelogRecipe(
            bundleID: "org.krita",
            source: URL(string: "https://krita.org/en/index.xml")!,
            entryPattern:
                #"<item>\s*<title>Krita [0-9.]+(?: Released!| bugfix release!)</title>.*?"#
                + #"<pubDate>(?<date>[^<]+)</pubDate>.*?"#
                + #"<description>(?<body>.*?)(?=&lt;h2 id="[^"]*download)"#
                + #"(?:(?!</item>).)*?&lt;h2 id="[^"]*"&gt;(?:Download )?"#
                + #"(?<version>(?!5\.)[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)(?: Download)?&lt;/h2&gt;"#,
            itemPatterns: [#"&lt;li&gt;(?<item>.*?)&lt;/li&gt;"#],
            escapedMarkup: true,
            minimumAppVersion: "6"),
        ])
}
