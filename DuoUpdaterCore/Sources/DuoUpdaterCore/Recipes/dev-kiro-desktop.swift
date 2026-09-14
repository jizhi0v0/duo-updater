import Foundation

enum dev_kiro_desktop {
    static let set = AppRecipeSet(
        family: "dev-kiro-desktop",
        probes: [
        // History: docs/app-audits/dev-kiro-desktop.md#历史与实测
        // Kiro — the Squirrel.Mac metadata its own updater reads (found by
        // capturing that request, 2026-08-16). One small JSON, already scoped
        // to this architecture by its filename, stating `currentRelease` and the
        // exact artifact for it.
        //
        // Preferred over the download page: that page carries both architectures'
        // links under the same version and its version text sits in hash-named
        // utility classes, so reading it means naming the architecture in a regex
        // and hoping the markup holds. The electron-builder manifest shapes
        // (`latest-mac.yml` / `latest.yml` / `/latest`) answered 403 on this host
        // when checked (2026-08-16; History has how the recipe got from the page
        // to this metadata).
        //
        // The metadata offers a zip where the page offers a dmg; the zip is the
        // same release and unpacks straight into the swap, so it is the better of
        // the two. `pub_date` is a bare `2026-08-13`, no time. #300 wired
        // `VendorProbeSource` to `ReleaseDate.publishedFields`, so a
        // `publishedAtPattern` here would now land honestly in
        // `RemoteVersion.vendorDay` instead of being silently inert — the
        // mechanism is ready. Adding the pattern itself is left for a
        // follow-up: per this repo's fragile-recipe rule, a recipe change needs
        // the real broken response reproduced and `duo verify` run against it,
        // not just a mechanism change.
        //
        // One-click: the zip holds Kiro.app, dev.kiro.desktop, Developer ID
        // `AMZN Mobile LLC (94KV3E626L)`, notarized and accepted by `spctl`
        // (checked 2026-08-16; History has the version); the gate compares that
        // Team against the installed copy's at install time.
        VendorProbeRecipe(
            bundleID: "dev.kiro.desktop",
            url: URL(string: "https://prod.download.desktop.kiro.dev"
                + "/stable/metadata-darwin-arm64-stable.json")!,
            mode: .responseBody,
            versionPattern: #""currentRelease":\s*"([0-9][0-9.]*)""#,
            downloadURL: URL(string: "https://kiro.dev/downloads/"),
            changelogURL: URL(string: "https://kiro.dev/changelog/ide/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url":\s*"(https://prod\.download\.desktop\.kiro\.dev/[^"]+darwin-arm64\.zip)""#),
                kind: .zip)),
        ],
        changelogs: [
        // Kiro — the changelog's RSS feed, filtered to the IDE.
        //
        // The feed mixes three products (`<category>` is IDE, CLI or Web) and the
        // installed app is the IDE, so the entry pattern requires that category
        // rather than filtering afterwards: a CLI release note under an IDE version
        // heading would be worse than no note.
        //
        // Only some titles carry a version ("IDE 1.0.337: Agent Focus, …"); the
        // rest are titled but unversioned ("IDE: Permission Improvements …"). Both
        // shapes are kept — `Changelog.Entry` accepts a title without a version,
        // and dropping the unversioned ones would silently lose about half the IDE
        // entries (History has the count when this was written). The `IDE` prefix
        // is consumed either way so the rail doesn't repeat it on every row.
        //
        // Notes are prose paragraphs, not lists, so the whole description is one
        // item — this feed has no bullets to find.
        //
        // `pubDate` is RFC-822 and the rail's date formatter only normalizes
        // ISO-8601, so the weekday and the time are dropped in the capture rather
        // than rendered verbatim as "Tue, 18 Aug 2026 20:04:00 GMT" under every
        // version. What's left ("18 Aug 2026") matches the shape Alcove's feed
        // already supplies.
        ChangelogRecipe(
            bundleID: "dev.kiro.desktop",
            source: URL(string: "https://kiro.dev/changelog/feed.rss")!,
            entryPattern:
                #"<item>\s*<title>(?:IDE(?: (?<version>[0-9][0-9.]*))?: )?(?<title>[^<]*)</title>\s*"#
                + #"<link>[^<]*</link>\s*<guid>[^<]*</guid>\s*"#
                + #"<pubDate>[A-Za-z]{3}, (?<date>[0-9]{2} [A-Za-z]{3} [0-9]{4})[^<]*</pubDate>\s*"#
                + #"<category>IDE</category>\s*"#
                + #"<description><!\[CDATA\[(?<body>[\s\S]*?)\]\]></description>"#,
            itemPatterns: [#"(?<item>[\s\S]+)"#],
            maxEntries: 20,
            minItemLength: 10),
        ])
}
