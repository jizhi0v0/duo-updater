import Foundation

enum com_microsoft_Headlamp {
    static let set = AppRecipeSet(
        family: "com-microsoft-Headlamp",
        changelogs: [
        // History: docs/app-audits/com-microsoft-Headlamp.md#历史与实测
        // Headlamp — its GitHub releases, read with regexes rather than through
        // `structuredFormat: .gitHubReleases`, because that decoder deliberately
        // refuses this body: `GitHubMarkdownParser` bails on a Markdown TABLE, and
        // Headlamp writes its whole changelog as tables (its own doc comment names
        // this app as the reason the guard exists). So
        // the pane had nothing structured to show and fell back to embedding the
        // releases page.
        //
        // Each table is `| change | Thanks to:<br>@who<br>#issue |` under a
        // section heading, with a two-row preamble per table: an `<img>`-only
        // header pair (stripped to nothing, then dropped by `minItemLength`) and
        // the `|:--|--:|` alignment row (dropped by requiring a letter-ish first
        // character and 15+ characters). Only the first cell is taken — the second
        // is attribution, not a change.
        //
        // The bullet pattern behind it is not redundancy for its own sake: the
        // table layout starts at 0.44.0, and the older releases on the page are
        // plain bullet lists. First-pattern-wins picks per
        // entry, so both eras render.
        //
        // That bullet is `[-*]`, both markers, because this vendor has used both
        // (History has which releases use which). A `-`-only pattern does not fail
        // on the `* ` ones — it yields an entry with no items, which
        // `ChangelogExtractor` drops, so those releases vanish from the rail while
        // the recipe still reports success.
        //
        // The item capture is `(?:\\[^rn]|[^"\\])`, not `[^\\]`, because the
        // capture happens BEFORE the JSON unescape: a cell containing `\"` would
        // be cut at the backslash and rendered as half a sentence. This is the
        // trap `StructuredFormat.postmanReleaseNotes` documents as the reason that
        // format stopped using regex at all.
        //
        // `"prerelease":false` in the entry pattern keeps this to the track the
        // user is on — the same policy `.gitHubReleases` states — and the `v`
        // prefix keeps it to the app: the repo interleaves `headlamp-helm-<ver>`
        // and `headlamp-plugin-*` tags its own `GitHubReleaseRule` already filters.
        // The gaps between fields refuse to cross a `"tag_name":` so a release with
        // a null body cannot pair one release's version with the next one's notes.
        //
        // `\s*` around every colon: this endpoint serves the SAME document compact
        // (e.g. `"tag_name":"v0.45.0"`) and pretty-printed (`"tag_name": "v0.45.0"`),
        // and which one you get is not the recipe's to choose — it has varied by
        // request. A pattern written against either form alone reads
        // as a clean "the vendor restyled their page" failure against the other.
        // The GitHub-API recipes that go through `Decodable` never meet this,
        // because it cannot see whitespace at all; Helium's
        // (`Recipes/net-imput-helium.swift`) is also a regex and carries the same
        // `\s*`.
        ChangelogRecipe(
            bundleID: "com.microsoft.Headlamp",
            source: URL(
                string:
                    "https://api.github.com/repos/kubernetes-sigs/headlamp/releases?per_page=40"
            )!,
            entryPattern:
                #""tag_name"\s*:\s*"v(?<version>[0-9][^"]*)""#
                + #"(?:(?!"tag_name"\s*:).)*?"prerelease"\s*:\s*false\s*,"#
                + #"(?:(?!"tag_name"\s*:).)*?"published_at"\s*:\s*"(?<date>[^"T]+)T"#
                + #"(?:(?!"tag_name"\s*:).)*?"body"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [
                #"\\(?:r\\)?n\|\s(?<item>[A-Za-z(`\[][^|]{15,}?)\s\|"#,
                #"\\(?:r\\)?n[-*]\s(?<item>(?:\\[^rn]|[^"\\]){15,})"#,
            ],
            mode: .json,
            markdownSource: true,
            maxEntries: 20),
        ],
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Headlamp — the repo interleaves `headlamp-helm-<ver>` and
        // `headlamp-plugin-<ver>` tags with the app's own `v<ver>`, and those chart
        // releases can be published after the app's, which would make GitHub's
        // "latest" a chart. Reading the LIST and anchoring `^v…$` takes the newest
        // APP tag instead. (No prereleases in this repo, so the list can't hand back
        // a preview build.) One-click: com.microsoft.Headlamp, Team 5N2JF58U87,
        // notarized.
        //
        // ⚠️ Renamed headlamp-k8s/headlamp -> kubernetes-sigs/headlamp. The canonical
        // name is pinned here on purpose, and it is not cosmetic: GitHub answers the
        // old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
        // `Authorization` while following it — the fetch that actually returns
        // the releases comes back ANONYMOUS, whatever token the user configured.
        // See #135.
        // listPageSize: the interleaved `headlamp-helm-`/`headlamp-plugin-` tags this
        // comment warns about (which don't match `^v…$`) can put two app tags a few
        // releases apart; 8 keeps 2x headroom over the widest run measured, and
        // because each release's `body` dominates the response, a page of 8 costs
        // little more than a page of 5 (History has the dated counts and sizes).
        GitHubReleaseRule(
            bundleID: "com.microsoft.Headlamp",
            owner: "kubernetes-sigs", repo: "headlamp",
            usePrereleases: true,
            listPageSize: 8,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Headlamp-[0-9.]+-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
