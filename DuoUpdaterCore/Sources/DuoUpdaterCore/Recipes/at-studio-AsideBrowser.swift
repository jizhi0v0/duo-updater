import Foundation

enum at_studio_AsideBrowser {
    static let set = AppRecipeSet(
        family: "at-studio-AsideBrowser",
        probes: [
        // Aside (At Inc., Team 8CPD4K4TBB) — a Chromium browser that updates itself
        // through Chromium's own updater (Omaha), so there is no `SUFeedURL` and no
        // generic source answers. The Homebrew cask is `auto_updates true`.
        //
        // Reads the vendor's `version_info.json`, the same document the cask's
        // livecheck reads. It carries one object per PLATFORM, and the platforms do
        // not ship together: on 2026-09-14 it said mac `1.0.910.1` and win
        // `1.0.914.1`, and the changelog page already led with 914.1. So both
        // patterns are fenced inside the `"mac"` object by `[^{}]*?`, which cannot
        // cross into `"win"` whichever order the keys come in.
        // snapshot-lint:allow — catch-up batch after 2f
        //
        // NOT `entryStartPattern` with a plain `"version"` pattern, although this
        // looks like the case for it: that primitive slices the body and keeps the
        // entry whose version compares HIGHEST, which on this document is the
        // Windows build. Every reader would then agree on a version the Mac cannot
        // download. The fence has to be in the pattern.
        //
        // The version is the marketing string (`CFBundleShortVersionString`
        // `1.0.910.1`, build `910.1`), so no `versionIsBuild`. The mac `url` is the
        // same DMG `aside.com/api/download/macos` redirects to, and the Omaha check
        // answered `nextversion 1.0.910.1` for an older install on the same day, so
        // this is the build anyone can download by hand, not one ahead of an
        // allocation. The mac track had a single build when measured, so a staged
        // rollout would not have been visible; re-check when one could be.
        //
        // Detection-only. The app runs its own updater (LaunchAgents plus a
        // privileged helper) and whether a one-click swap races it is not checked.
        VendorProbeRecipe(
            bundleID: "at.studio.AsideBrowser",
            url: URL(string:
                "https://ptqgesmtzwdmeiknncqc.supabase.co/functions/v1/omaha/version_info.json")!,
            mode: .responseBody,
            versionPattern: #""mac"\s*:\s*\{[^{}]*?"version"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://aside.com/"),
            changelogURL: URL(string: "https://docs.aside.com/changelog/native")),
        ],
        changelogs: [
        // Aside — the Mintlify docs site serves every page as Markdown too
        // (`…/changelog/native.md`, `text/markdown`), so this reads that rather than
        // the rendered HTML.
        //
        // ONE page for every platform, and entries are not marked with one. An entry
        // can therefore be newer than anything the Mac has been offered: `v1.0.914.1`
        // ("Aside is now officially available on Windows!") topped the page while
        // the mac track was still on 1.0.910.1. That is the vendor shipping Windows
        // first, not a stale probe.
        //
        // Shape (51 entries on 2026-09-14): `## v1.0.914.1` headings from 1.0.626.1
        // up, bare `## 1.0.624.1` below that. A `Month D, YYYY` line follows the
        // heading only on 1.0.626.1 and older (38 entries); the newest 13 have none,
        // and the version's middle digits are a month-day with no year, so no date
        // is derived from it. Bodies mix `### Section` headings, `* ` bullets
        // (sometimes indented), plain paragraphs and the odd fenced command, so the
        // item pattern takes every non-blank line that is not a heading or a fence
        // marker — a paragraph like "You can now switch profiles inside a single
        // window." is the note itself. `**bold**` stays literal: `markdownSource`
        // only unwraps code spans and links (4 items in the newest ten carry it).
        // snapshot-lint:allow — catch-up batch after 2f
        //
        // `/changelog/components` is the in-browser components' log, not the app's.
        ChangelogRecipe(
            bundleID: "at.studio.AsideBrowser",
            source: URL(string: "https://docs.aside.com/changelog/native.md")!,
            entryPattern:
                #"(?m)^## v?(?<version>[0-9]+(?:\.[0-9]+){3})[ \t]*\n\s*"#
                + #"(?:(?<date>(?:January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{1,2}, [0-9]{4})[ \t]*\n)?"#
                + #"(?<body>.*?)(?=\n## |\z)"#,
            itemPatterns: [
                #"(?m)^[ \t]*(?:[*-][ \t]+)?(?<item>[^\s#`>][^\n]*?)[ \t]*$"#
            ],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            maxEntries: 10,
            headingPattern: #"(?m)^###[ \t]+(?<heading>[^\n]+?)[ \t]*$"#),
        ])
}
