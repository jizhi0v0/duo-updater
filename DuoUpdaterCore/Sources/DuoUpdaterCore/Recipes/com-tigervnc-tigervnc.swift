import Foundation

enum com_tigervnc_tigervnc {
    static let set = AppRecipeSet(
        family: "com-tigervnc-tigervnc",
        probes: [
        // History: docs/app-audits/com-tigervnc-tigervnc.md#历史与实测
        // TigerVNC — Developer ID (Brian Hinz, S5LX88A9BW), notarized; `spctl`
        // accepts the app mounted from the one-click dmg (checked 2026-08-16;
        // History has the dmg version).
        VendorProbeRegistry.sourceForgeMacRecipe(
            bundleID: "com.tigervnc.tigervnc",
            project: "tigervnc",
            versionPattern:
                #""mac":\s*\{[^}]*?"filename":\s*"/stable/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/TigerVNC-[0-9.]+\.dmg""#,
            changelogURL: URL(string: "https://github.com/TigerVNC/tigervnc/releases")!,
            installKind: .dmg),
        ],
        changelogs: [
        // History: docs/app-audits/com-tigervnc-tigervnc.md#历史与实测
        // TigerVNC — the release announcements on TigerVNC/tigervnc's GitHub
        // releases (the probe's `changelogURL`), read with regexes over the API
        // JSON rather than `.gitHubReleases`. Every body is one mail-style
        // announcement: an intro sentence, then EITHER an indented `  - ` list OR
        // (bug-fix and security releases) one or two prose paragraphs, then a
        // fixed footer — "Binaries are available from SourceForge:", the link,
        // "Regards", "The TigerVNC Developers". `GitHubMarkdownParser`'s prose
        // pass keeps every line of a list-less body, so for those releases the
        // footer became three of the entry's five "changes".
        //
        //  - `body` stops at the blank line before the footer ("Binaries are
        //    available" now; "You can download binary builds" in 1.3.0), so the
        //    footer never reaches the item patterns. A body without it runs to
        //    its closing quote.
        //  - Item patterns, first-wins per entry: the `-`/`*` list lines when
        //    there are any (the intro sentence is then dropped, as the decoder
        //    drops it), else each paragraph's text.
        //  - `"prerelease":false`: the `.90` tags are betas of the next minor,
        //    and the probe reads SourceForge's stable folder only.
        //  - Tags are `v<version>`, the probe's version shape (`1.16.0`).
        //  - Captures run before the JSON unescape, hence `(?:\\[^rn]|[^"\\])`
        //    and both newline spellings (1.3.0's body uses `\n`, later ones
        //    `\r\n`); `\s*` around colons because the API answers compact or
        //    pretty, as in `Recipes/net-imput-helium.swift`.
        //  - `markdownSource` flattens the `[text](url)` links the 1.4.x
        //    notes carry.
        ChangelogRecipe(
            bundleID: "com.tigervnc.tigervnc",
            source: URL(string: "https://api.github.com/repos/TigerVNC/tigervnc/releases?per_page=40")!,
            entryPattern:
                #""tag_name"\s*:\s*"v(?<version>[0-9]+(?:\.[0-9]+)+)""#
                + #"(?:(?!"tag_name"\s*:).)*?"prerelease"\s*:\s*false\s*,"#
                + #"(?:(?!"tag_name"\s*:).)*?"published_at"\s*:\s*"(?<date>[^"T]+)T"#
                + #"(?:(?!"tag_name"\s*:).)*?"body"\s*:\s*"(?<body>(?:(?!"#
                + #"\\(?:r\\)?n\\(?:r\\)?n(?:Binaries are available|You can download binary))"#
                + #"(?:\\.|[^"\\]))*)"#,
            itemPatterns: [
                #"\\(?:r\\)?n[ \t]*[-*][ \t]+(?<item>(?:\\[^rn]|[^"\\])+)"#,
                #"(?:^|\\(?:r\\)?n\\(?:r\\)?n)(?<item>(?:\\[^rn]|[^"\\])+)"#,
            ],
            mode: .json,
            markdownSource: true,
            maxEntries: 20),
        ])
}
