import Foundation

enum com_docker_docker {
    static let set = AppRecipeSet(
        family: "com-docker-docker",
        probes: [
        // History: docs/app-audits/com-docker-docker.md#历史与实测
        // Docker Desktop — Sparkle appcast. Titles read "<ver> (<build>)" (and
        // "Version <ver> (<build>)"); take the highest since the feed isn't
        // strictly ordered. The channel title "Docker for Mac" carries no
        // version-paren and is skipped. Build number ignored in comparison.
        VendorProbeRecipe(
            bundleID: "com.docker.docker",
            url: URL(string: "https://desktop.docker.com/mac/main/arm64/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<title>(?:Version\s*)?([0-9]+\.[0-9]+\.[0-9]+)\s*\("#,
            changelogURL: URL(string: "https://docs.docker.com/desktop/release-notes/"),
            selectHighest: true,
            // The install pattern anchors on `Docker.dmg` for a reason: this feed
            // nests `<sparkle:deltas>` whose entries are `<enclosure>` too, pointing
            // at `Docker-<prev>.delta`. A looser match would happily install a patch
            // file as if it were the app. (Same trap that made the Sparkle parser
            // drop whole feeds — see `SparkleAppcastParser`.)
            //
            // And the entry is chosen by the version it declares, not by position:
            // this feed is NOT newest-first, so a first-match download can fetch an
            // older build than the version reported (History has the incident).
            // `sparkle:shortVersionString` sits in the same tag as the URL, so the
            // two can no longer disagree.
            //
            // The image holds `Docker.app` — bundle id com.docker.docker, Team
            // 9BNSXJN65R, notarized Developer ID.
            install: VendorInstallSpec(
                urlSource: .bodyPatternHighestVersioned(
                    #"<enclosure[^>]*url="(https://desktop\.docker\.com/[^"]+/Docker\.dmg)"[^>]*sparkle:shortVersionString="([0-9][0-9.]*)""#),
                kind: .dmg)),
        ],
        changelogs: [
        // Docker Desktop — the release-notes page in its Markdown source form.
        // `docs.docker.com/desktop/release-notes.md` serves `text/markdown`
        // directly (the `.md` twin of the HTML page).
        //
        // The `- [Windows](…)` / `- [Mac …]` / `- [Linux …]` installer links each
        // release opens with are excluded by the item pattern's negative lookahead:
        // they are the same seven download URLs every time and say nothing about
        // what changed. Everything after them — the `### Updates` component list
        // and the `### Bug fixes and enhancements` sections — is kept.
        //
        // `markdownSource` because the notes link out mid-sentence
        // (e.g. `[Docker Compose v5.4.0](…)`); without it a plain-text render prints the
        // brackets and the URL.
        ChangelogRecipe(
            bundleID: "com.docker.docker",
            source: URL(string: "https://docs.docker.com/desktop/release-notes.md")!,
            entryPattern:
                #"## (?<version>[0-9]+\.[0-9]+\.[0-9]+)\n\n"#
                + #"<em[^>]*>(?<date>[0-9-]+)</em>"#
                + #"(?<body>[\s\S]*?)(?=\n## |\z)"#,
            itemPatterns: [#"(?:^|\n)- (?!\[(?:Windows|Mac|Linux))(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            maxEntries: 20,
            minItemLength: 6),
        ])
}
