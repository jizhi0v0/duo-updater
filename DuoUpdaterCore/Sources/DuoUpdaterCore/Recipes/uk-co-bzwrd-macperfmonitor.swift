import Foundation

enum uk_co_bzwrd_macperfmonitor {
    static let set = AppRecipeSet(
        family: "uk-co-bzwrd-macperfmonitor",
        changelogs: [
        // History: docs/app-audits/uk-co-bzwrd-macperfmonitor.md#历史与实测
        // Mac Performance Monitor — through 1.7.1 the repo's CHANGELOG.md was the
        // only place its notes existed: the `appcast.xml` asset its `SUFeedURL`
        // points at had no `sparkle:releaseNotesLink`, no
        // `sparkle:fullReleaseNotesLink` and no `<description>`, and the GitHub
        // release body was one sentence pointing at CHANGELOG.md (History quotes
        // both as fetched). Since 2.0.0 the appcast's one item carries that
        // release's notes as an HTML `<description>`, and so does the release body;
        // both cover only the newest release, so this recipe is still the only
        // source of the history, and CHANGELOG.md has entries for 2.0.0 and 2.1.0
        // (all checked 2026-09-14; History has the appcasts). Requested in #374.
        //
        // Keep a Changelog, with the version in BRACKETS:
        //
        //   ## [1.7.1] - 2026-09-03
        //   ### Fixed
        //   - In Simplified Chinese, the Hardware tab listed every CPU
        //     instruction-set feature as unsupported. The check compared …
        //
        // Two things differ from the Copilot recipe (`Recipes/com-github-CopilotForXcode.swift`), and both are the file's
        // doing rather than taste:
        //
        //  * `\[…\]` around the version, and a leading `[0-9]` inside it — that is
        //    what keeps the `## [Unreleased]` section at the top of the file from
        //    becoming an entry. It is a real section with real bullets, and it
        //    describes a build nobody can install yet.
        //  * The item pattern spans lines. This vendor wraps its bullets at ~78
        //    columns with a two-space continuation indent, so `[^\n]+` (what every
        //    single-line recipe uses) truncates most items mid-sentence. The lazy
        //    scan runs to the next bullet, the next `###` group heading, the next
        //    `##` entry, a Keep a Changelog LINK DEFINITION, or the end.
        //
        // ⚠️ `\n\[` is in that list because the file ends with the link-reference
        // block the format prescribes (`[1.3.2]: https://…/compare/…`), and the
        // last entry's body runs to `\z`. Without that boundary the oldest entry's
        // final bullet swallowed every one of them, compare URLs and all (History
        // has the measured lengths). Nothing else changes: the same entries parse
        // with the same item counts, and no item carries a link definition any
        // more. Unindented, so it cannot fire on a wrapped continuation line, which
        // this vendor indents by two spaces.
        //
        // `headingPattern` (#554, part of #399) turns the `### Added` / `###
        // Fixed` group headings back into real `.heading` blocks instead of
        // letting them keep serving only as the `itemPattern` boundary above —
        // this is a genuine Keep a Changelog file, so every `###` heading it has
        // IS a real category, unconditionally (no "≥2 siblings" guess needed the
        // way `GitHubMarkdownParser` needs one across dozens of unrelated GitHub
        // vendors — see `Changelog.parserGeneration`'s generation-3 entry).
        // A heading is one line, so it needs none of the item pattern's lookahead
        // boundary list above: `[^\n]+` is a negated character class, which
        // already cannot cross the newline that ends it. Simpler than the item
        // pattern by construction, not by omission — there is no multi-line
        // heading to bound against here.
        ChangelogRecipe(
            bundleID: "uk.co.bzwrd.macperfmonitor",
            source: URL(string: "https://raw.githubusercontent.com/Zesty0wl/mac-performance-monitor/main/CHANGELOG.md")!,
            entryPattern:
                #"(?:^|\n)##\s+\[(?<version>[0-9][^\]]*)\]\s*-\s*(?<date>[^\n]+)\n(?<body>.*?)(?=\n##\s|\z)"#,
            itemPatterns: [#"\n-\s+(?<item>.+?)(?=\n-\s|\n###\s|\n##\s|\n\[|\z)"#],
            markdownSource: true,
            headingPattern: #"\n###\s+(?<heading>[^\n]+)"#),
        ])
}
