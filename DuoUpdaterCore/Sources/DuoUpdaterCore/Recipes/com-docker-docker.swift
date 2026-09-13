import Foundation

enum com_docker_docker {
    static let set = AppRecipeSet(
        family: "com-docker-docker",
        probes: [
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
            // this feed is NOT newest-first. On 2026-08-17 it listed 4.86.0 (build
            // 236216) ahead of 4.87.0 (236836), so a first-match download fetched
            // 4.86.0 over an installed 4.86.0 — 574 MB, a 2.26 GB backup, "install
            // done", and the update still pending. `sparkle:shortVersionString` sits
            // in the same tag as the URL, so the two can no longer disagree.
            //
            // Verified 2026-08-09 on 4.85.0 (build 235549): `Docker.app` in the
            // image, bundle id com.docker.docker, Team 9BNSXJN65R, spctl "Notarized
            // Developer ID". 573 MB, arm64-specific feed path.
            install: VendorInstallSpec(
                urlSource: .bodyPatternHighestVersioned(
                    #"<enclosure[^>]*url="(https://desktop\.docker\.com/[^"]+/Docker\.dmg)"[^>]*sparkle:shortVersionString="([0-9][0-9.]*)""#),
                kind: .dmg)),
        ],
        changelogs: [
        // Docker Desktop — the release-notes page in its Markdown source form.
        // `docs.docker.com/desktop/release-notes.md` serves `text/markdown`
        // directly (the `.md` twin of the HTML page), 142 versions deep, newest
        // 4.87.0 on 2026-08-17 — the installed version here.
        //
        // The `- [Windows](…)` / `- [Mac …]` / `- [Linux …]` installer links each
        // release opens with are excluded by the item pattern's negative lookahead:
        // they are the same seven download URLs every time and say nothing about
        // what changed. Everything after them — the `### Updates` component list
        // and the `### Bug fixes and enhancements` sections — is kept.
        //
        // `markdownSource` because the notes link out mid-sentence
        // (`[Docker Compose v5.4.0](…)`); without it a plain-text render prints the
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
