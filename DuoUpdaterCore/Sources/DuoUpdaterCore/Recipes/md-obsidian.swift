import Foundation

enum md_obsidian {
    static let set = AppRecipeSet(
        family: "md-obsidian",
        probes: [
        // Obsidian — official desktop-releases manifest (the same file Obsidian's
        // own updater reads). Two "latestVersion" keys live here: the TOP-LEVEL
        // one is STABLE, then a nested "beta" object carries the (currently HIGHER)
        // insider build. We anchor to the FIRST match so we read STABLE only;
        // selectHighest stays false (true would grab the bigger beta value and
        // invent a phantom update for a stable install). ChangelogRecipe(md.obsidian)
        // renders the notes natively. One-click CAVEAT: this manifest's own
        // `downloadUrl` is an `.asar.gz` — Obsidian's in-place patch format, which we
        // can't apply. The full signed dmg lives only on the GitHub release, named
        // `Obsidian-<ver>.dmg`, so we template that URL from the stable `latestVersion`
        // (first match — the nested `beta` object's higher version comes later and is
        // intentionally NOT picked). A full-bundle dmg swap supersedes Obsidian's own
        // lighter asar self-update; the same-Team gate still guards it.
        VendorProbeRecipe(
            bundleID: "md.obsidian",
            url: URL(string: "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/desktop-releases.json")!,
            mode: .responseBody,
            versionPattern: #""latestVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://obsidian.md/download"),
            changelogURL: URL(string: "https://obsidian.md/changelog/"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://github.com/obsidianmd/obsidian-releases/releases/download/v{0}/Obsidian-{0}.dmg",
                    fields: [#""latestVersion"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#]),
                kind: .dmg)),
        ],
        changelogs: [
        // Notion's OTHER changelog, deliberately not registered: www.notion.com/
        // releases is the *product* announcement feed (feature launches like "Plan
        // Mode"), server-rendered and scrapeable, but carrying no build number at
        // all — the old recipe used each post's title as the `version`, which never
        // matched the build on the row. That mismatch is what the recipe above
        // fixes, so the two must not both claim to be this app's release notes.
        //
        // The scrape pattern is not kept here as commented-out code; it is in git
        // (3603c3c^ and earlier), and `notionProductAnnouncementsRecipe()` in the
        // tests still builds it, so its regression coverage survives. If those
        // product announcements are ever wanted, they should come back as a
        // separate, clearly-labelled source — not as a second recipe for this id.

        // Obsidian — obsidian.md/changelog is one server-rendered page listing
        // every release newest-first, with BOTH Mobile and Desktop posts. Each
        // block is a sticky header anchor + a notes column. We key on the header
        // anchor's `-desktop-v` slug, which (a) drops the interleaved Mobile posts
        // and (b) yields the version directly from the href — more reliable than
        // the visible <span class="text-sm"> label, which for some releases prints
        // a truncated "1.12" while the slug stays full ("…-desktop-v1.12.4"). The
        // date link must be anchored on its `class="font-semibold…"` — a bare href
        // match also hits in-body links like "<a …>Obsidian Desktop v1.12.7</a>"
        // and would steal the date. The typeset body closes with three nested
        // </div> (notes col → basis-3/4 → flex row); the lookahead stops there so
        // it can't bleed into the next entry. Only <li> become items.
        ChangelogRecipe(
            bundleID: "md.obsidian",
            source: URL(string: "https://obsidian.md/changelog/")!,
            entryPattern:
                #"<a href="/changelog/[^"]*-desktop-v(?<version>[\d.]+)/?"\s+class="font-semibold[^"]*"[^>]*>\s*(?<date>[^<]+?)\s*</a>"#
                + #".*?<div class="typeset break-words"[^>]*>(?<body>.*?)</div>\s*</div>\s*</div>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 20),
        ])
}
