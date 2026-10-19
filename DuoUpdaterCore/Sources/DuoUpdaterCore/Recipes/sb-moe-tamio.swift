import Foundation

enum sb_moe_tamio {
    static let set = AppRecipeSet(
        family: "sb-moe-tamio",
        changelogs: [
        // History: docs/app-audits/sb-moe-tamio.md#历史与实测
        // Tamio — detection and one-click come from the bundle's own Sparkle feed
        // (`SUFeedURL` = the latest GitHub release's `appcast.xml` asset). That
        // appcast is rewritten on every release and holds ONE item, whose
        // `<description>` is that release's notes as plain text: no history, and
        // no structure in the pane.
        //
        // The repo's `CHANGELOG.md` is where those notes come from: the release
        // workflow refuses a tag with no section there, and copies the section
        // into the GitHub release and the update window. Keep a Changelog, the
        // same shape as Mac Performance Monitor's
        // (`Recipes/uk-co-bzwrd-macperfmonitor.swift`, whose comment explains each
        // pattern):
        //
        //   ## [0.2.4] - 2026-10-18
        //   ### Added
        //   - **A proxy command for a server.** In Edit Server › Advanced, a …
        //     field carries the connection through a command instead of …
        //
        //  * a digit inside `\[…\]` skips the `## [Unreleased]` section at the top;
        //  * bullets wrap with a two-space continuation indent, so the item runs
        //    to the next bullet, `###` group, `##` entry, link definition or end;
        //  * every `###` is a real Keep a Changelog group (Added / Changed / Fixed /
        //    Removed), so `headingPattern` keeps them as headings.
        //
        // The file has no link-reference block today; the `\n\[` boundary costs
        // nothing and holds if one is added.
        ChangelogRecipe(
            bundleID: "sb.moe.tamio",
            source: URL(string: "https://raw.githubusercontent.com/missuo/tamio/main/CHANGELOG.md")!,
            entryPattern:
                #"(?:^|\n)##\s+\[(?<version>[0-9][^\]]*)\]\s*-\s*(?<date>[^\n]+)\n(?<body>.*?)(?=\n##\s|\z)"#,
            itemPatterns: [#"\n-\s+(?<item>.+?)(?=\n-\s|\n###\s|\n##\s|\n\[|\z)"#],
            markdownSource: true,
            headingPattern: #"\n###\s+(?<heading>[^\n]+)"#),
        ])
}
