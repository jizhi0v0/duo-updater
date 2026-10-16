import Foundation

enum com_xk72_Charles {
    static let set = AppRecipeSet(
        family: "com-xk72-Charles",
        probes: [
        // History: docs/app-audits/com-xk72-Charles.md#历史与实测
        // Charles (XK72) — a Java app with no Sparkle and no feed in the bundle.
        // Its own check POSTs the installed version to `latest.do` and gets back
        // a bare version string, or an empty body when the copy is current. That
        // answer depends on the version sent, which a recipe cannot template, so
        // this reads the vendor's own download page instead.
        //
        // THE PAGE is `/download/latest-release/`. Its download form carries the
        // release as hidden inputs, `beta` then `version`:
        //   <input type="hidden" name="beta" value="false" />
        //   <input type="hidden" name="version" value="5.2.2" />
        // The pattern requires `beta` to be `false` right before the version, and
        // the version to be digits and dots up to the closing quote, so a beta
        // (`5.1.1b11`) never reads as stable. Two-part releases (`5.2`) match.
        // The leading `5` is the major-version pin explained below.
        // The value equals `CFBundleShortVersionString` (and `CFBundleVersion`).
        // Everyone gets the same page: this is the public GA build, the one the
        // download page offers by hand.
        //
        // Both sides are pinned to Charles 5. A licence covers one major version
        // and the next one is a paid upgrade, while 4.x stays downloadable from
        // `/download/previous-release/`. `installedVersionPattern` keeps a 4.x
        // copy from being offered 5.x. The `5` in `versionPattern` covers the
        // other direction: when Charles 6 takes over this page, the probe reads
        // nothing and fails (visible in `duo verify`) instead of offering a 5.x
        // copy a paid 6.x. At that point this row moves to the page 5.x is
        // served from, and 6.x gets its own row.
        //
        // One-click: the dmg path is built from the version this probe resolved.
        // It is the address the Homebrew cask uses. The package holds
        // `Charles.app`, Developer ID Team 9A5PCU4FSD, notarized, universal.
        VendorProbeRecipe(
            bundleID: "com.xk72.Charles",
            url: URL(string: "https://www.charlesproxy.com/download/latest-release/")!,
            mode: .responseBody,
            versionPattern:
                #"name="beta"\s+value="false"\s*/>\s*<input\s+type="hidden"\s+name="version"\s+value="(5(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.charlesproxy.com/download/"),
            changelogURL: URL(string: "https://www.charlesproxy.com/documentation/version-history/"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://www.charlesproxy.com/assets/release/{version}/charles-proxy-{version}.dmg"),
                kind: .dmg),
            installedVersionPattern: #"^5\."#),
        ],
        changelogs: [
        // The version history page: one `<h4>Version X</h4>` per release, newest
        // first, then a `<p>` date ("11 October 2026"), then `<p>` category
        // headings each followed by a `<ul>`. Betas (`Version 5.1.1b11`) are on
        // the same page and are skipped: the version must be digits and dots up
        // to `</h4>`. Old-major maintenance releases (4.6.x) are interleaved by
        // date, as the vendor lists them.
        //
        // A body runs to the next `<h4` (or the content's `</div>`). Items stop
        // at the next list tag, so a nested list ("Various UI enhancements:"
        // with its sub-items) gives the parent line and each child, not one
        // merged line. A few old releases have no list; their `<p>` text is the
        // fallback. A `<p>` directly followed by a `<ul>` is a heading.
        ChangelogRecipe(
            bundleID: "com.xk72.Charles",
            source: URL(string: "https://www.charlesproxy.com/documentation/version-history/")!,
            entryPattern:
                #"<h4>\s*Version\s+(?<version>[0-9]+(?:\.[0-9]+)+)\s*</h4>\s*"#
                + #"(?:<p>\s*(?<date>[0-9]{1,2}\s+[A-Za-z]+\s+[0-9]{4})\s*</p>)?"#
                + #"(?<body>.*?)(?=<h4|</div>)"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>(?:(?!</?(?:li|ul|ol)\b).)+)"#,
                #"<p[^>]*>(?<item>.*?)</p>"#,
            ],
            maxEntries: 20,
            headingPattern: #"<p[^>]*>(?<heading>[^<]{1,80})</p>\s*(?=<ul)"#),
        ])
}
