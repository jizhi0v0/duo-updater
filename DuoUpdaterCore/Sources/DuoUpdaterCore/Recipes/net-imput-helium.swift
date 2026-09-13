import Foundation

enum net_imput_helium {
    static let set = AppRecipeSet(
        family: "net-imput-helium",
        changelogs: [
        // Helium — its GitHub releases, again with regexes rather than
        // `.gitHubReleases`: the body is a hash dump followed by two fenced commit
        // logs, and `GitHubMarkdownParser`'s prose pass would render the md5/sha
        // lines as "changes" while the fences it skips hold the only real content.
        //
        // Nothing else can supply notes. `updates.helium.computer/mac/appcast-arm64.xml`
        // (the app's own Sparkle feed, and its update source here) carries no
        // `<description>` and no `<sparkle:releaseNotesLink>` on any item, and
        // helium.computer publishes no changelog page at all (`/changelog` and
        // `/releases` both 404) — so the pane fell back to embedding the GitHub
        // releases page.
        //
        // What the vendor does publish is the commit log of the two repos each
        // build merges — `helium-macos` and `helium-chromium` — as
        // `<hash> <subject>` lines inside fenced blocks. The hash is consumed
        // rather than captured: it is a link the pane cannot follow and it pushes
        // the subject off the row. The `[0-9a-f]{7,10} ` anchor after a newline is
        // what keeps the hash block out — `md5:`/`sha256:` lines start with
        // letters and a colon, so no line of them can match at a line start.
        //
        // The item capture is `(?:\\[^rn]|[^"\\])`, not `[^\\]`: the capture runs
        // BEFORE the JSON unescape, so a commit subject containing `\"` — five of
        // them in the current 40-release window — would be cut at the backslash and
        // shown as half a line. Same trap `StructuredFormat.postmanReleaseNotes`
        // documents as the reason that format abandoned regex.
        //
        // That newline is `\\(?:r\\)?n`, both spellings, because the vendor uses
        // both: every stable body sampled ends its lines `\\r\\n` and every
        // prerelease one `\\n`. A pattern that knows only the first does not fail
        // on the second — it yields an entry with no changes, which is invisible.
        //
        // `"prerelease":false` for the same reason as Headlamp above, and it is not
        // theoretical here: the vendor tags a build as prerelease for a day or two
        // before the appcast picks it up (0.16.4.1 on 2026-09-03), and listing it
        // would show notes for a version this app is not being offered. 33 entries
        // on the live endpoint, newest 0.16.3.1 — the version the appcast serves.
        //
        // `\s*` around every colon: this endpoint serves the SAME document compact
        // (`"tag_name":"v0.45.0"`) and pretty-printed (`"tag_name": "v0.45.0"`),
        // and which one you get is not the recipe's to choose — it varied by
        // request on 2026-09-03. A pattern written against either form alone reads
        // as a clean "the vendor restyled their page" failure against the other.
        // The registry's other GitHub-API recipes never met this because they go
        // through `Decodable`, which cannot see whitespace at all.
        ChangelogRecipe(
            bundleID: "net.imput.helium",
            source: URL(
                string: "https://api.github.com/repos/imputnet/helium-macos/releases?per_page=40"
            )!,
            entryPattern:
                #""tag_name"\s*:\s*"(?<version>[0-9][^"]*)""#
                + #"(?:(?!"tag_name"\s*:).)*?"prerelease"\s*:\s*false\s*,"#
                + #"(?:(?!"tag_name"\s*:).)*?"published_at"\s*:\s*"(?<date>[^"T]+)T"#
                + #"(?:(?!"tag_name"\s*:).)*?"body"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [#"\\(?:r\\)?n[0-9a-f]{7,10} (?<item>(?:\\[^rn]|[^"\\]){3,})"#],
            mode: .json,
            maxEntries: 20),
        ],
        githubRules: [
        // Helium — Chromium-based AI browser (imputnet/helium-macos). Bare tags
        // (`0.16.2.1`, no v), and the repo DOES cut prerelease releases with
        // the same all-digit tag shape (`0.16.1.1`) — /releases/latest excludes
        // prereleases, so the stable rule never sees them. One-click pins the
        // arm64 dmg; the x86_64 dmg ships beside it. Mounted 0.16.2.1:
        // net.imput.helium, short == build == tag, Team S4Q33XPHB4, notarized.
        GitHubReleaseRule(
            bundleID: "net.imput.helium",
            owner: "imputnet", repo: "helium-macos",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^helium_[0-9.]+_arm64-macos\.dmg$"#,
            installerKind: .dmg),
        ],
        sparkleFeeds: [
        // Helium — Chromium-based browser (imputnet/helium-macos). Ships Sparkle
        // but no `SUFeedURL`; the address is in the binary alongside a
        // `custom-update-server-url` flag. One feed PER ARCHITECTURE
        // (`appcast-x86_64.xml` is the sibling), and arm64 is pinned here because
        // DuoUpdater is arm64-only — see `App/project.yml`.
        //
        // Reading it buys two things the GitHub rule cannot: the beta train
        // (`<sparkle:channel>beta</sparkle:channel>` on one item), and the delta
        // patches every item publishes — ~40 MB against a 124 MB full download.
        // Its enclosures are RELATIVE (`assets/helium_….dmg`), which Sparkle
        // resolves against the appcast URL and we now do too; before that fix
        // this entry would have produced a schemeless, unfetchable download.
        "net.imput.helium": URL(string: "https://updates.helium.computer/mac/appcast-arm64.xml")!,
        ],
        changelogPages: [
        // Helium — moved from the GitHub source to its own Sparkle feed
        // (`SparkleFeedCatalog`) for the beta train and the delta patches. That
        // trade costs the notes: the GitHub release body was carrying them, and
        // the vendor's appcast has no `<description>` and no
        // `sparkle:releaseNotesLink` on any of its 9 items. Without this entry
        // the move would have silently emptied the notes pane, so the fallback
        // points back at the releases the body lives on.
        "net.imput.helium": URL(string: "https://github.com/imputnet/helium-macos/releases")!,
        ])
}
